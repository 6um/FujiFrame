import Foundation

public struct DetectedRecipeSettings: Sendable {
    public var values: [String: String]
    public var notes: [String]
    public init(values: [String: String] = [:], notes: [String] = []) { self.values = values; self.notes = notes }
}

/// Read-only JPEG/EXIF parser. Fuji tag meanings follow ExifTool FujiFilm.pm;
/// see docs/FUJI_METADATA.md. Unknown values never become camera defaults.
public enum FujiMetadata {
    public static func read(_ url: URL, camera: String?) throws -> DetectedRecipeSettings {
        guard camera?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "X-T5" else {
            return .init(notes: ["机型不是可确认的 X-T5，请手动选择配方。"])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func read(_ count: Int) throws -> Data {
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw FrameError("JPEG 元数据截断") }
            return data
        }
        guard try read(2) == Data([0xff, 0xd8]) else { throw FrameError("不是 JPEG 文件") }
        for _ in 0..<4096 {
            try Task.checkCancellation()
            guard try read(1)[0] == 0xff else { throw FrameError("无效 JPEG 标记") }
            var marker = try read(1)[0]
            var padding = 0
            while marker == 0xff {
                padding += 1; guard padding < 1024 else { throw FrameError("无效 JPEG 标记长度") }
                marker = try read(1)[0]
            }
            if marker == 0xda || marker == 0xd9 { break }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) { continue }
            let lengthBytes = try read(2)
            let length = Int(lengthBytes[0]) * 256 + Int(lengthBytes[1])
            guard length >= 2 else { throw FrameError("无效 JPEG 段长度") }
            let segment = try read(length - 2)
            if marker == 0xe1, segment.starts(with: [0x45, 0x78, 0x69, 0x66, 0, 0]) {
                let result = try parseEXIF(Data(segment.dropFirst(6)))
                if !result.values.isEmpty { return result }
            }
        }
        return .init(notes: ["未找到可识别的富士配方参数；可能已被编辑软件移除。"])
    }
    static func parseEXIF(_ data: Data) throws -> DetectedRecipeSettings {
        guard data.count >= 8 else { throw FrameError("EXIF 头截断") }
        let order = Array(data.prefix(2))
        guard order == [0x49, 0x49] || order == [0x4d, 0x4d] else { throw FrameError("未知 EXIF 字节序") }
        let tiff = TIFFReader(data: data, little: order[0] == 0x49)
        guard try tiff.uint(2, 2) == 42 else { throw FrameError("无效 EXIF TIFF 头") }
        let ifd = try tiff.directory(at: tiff.uint(4, 4))
        guard let exifEntry = ifd[0x8769], let exifOffset = try tiff.numbers(exifEntry)?.first else { return .init() }
        let exif = try tiff.directory(at: Int(exifOffset))
        guard let maker = exif[0x927c] else { return .init() }
        return try parseMakerNote(tiff.bytes(maker))
    }
    static func parseMakerNote(_ data: Data) throws -> DetectedRecipeSettings {
        guard data.starts(with: Array("FUJIFILM".utf8)) else { return .init(notes: ["不是富士 MakerNotes"] ) }
        let reader = TIFFReader(data: data, little: true)
        let offset = try reader.uint(8, 4)
        guard offset >= 12 else { throw FrameError("无效富士目录偏移") }
        let entries = try reader.directory(at: offset)
        var tags: [Int: [Int64]] = [:]
        let recognized: Set<Int> = [0x1001,0x1002,0x1003,0x1005,0x100a,0x100e,0x100f,0x1040,0x1041,0x1045,0x1047,0x1048,0x1049,0x104b,0x104c,0x104e,0x1401,0x1402,0x1403,0x1443,0x1445]
        for (id, entry) in entries where recognized.contains(id) { tags[id] = try reader.numbers(entry) }
        return normalize(tags)
    }
    static func normalize(_ tags: [Int: [Int64]]) -> DetectedRecipeSettings {
        var values: [String: String] = [:]
        func scalar(_ tag: Int) -> Int? { guard let array = tags[tag], array.count == 1 else { return nil }; return Int(exactly: array[0]) }
        func map(_ key: String, _ tag: Int, _ table: [Int: String]) { if let n = scalar(tag), let value = table[n] { values[key] = value } }
        let monochrome = [0x300:"MONOCHROME",0x301:"MONOCHROME + R",0x302:"MONOCHROME + Ye",0x303:"MONOCHROME + G",0x310:"SEPIA",0x500:"ACROS",0x501:"ACROS + R",0x502:"ACROS + Ye",0x503:"ACROS + G"]
        if let saturation = scalar(0x1003), let mono = monochrome[saturation] { values["film"] = mono }
        else {
            // Require a known color Saturation value: an unknown code could be a new B&W mode.
            let colors = [0:"0",0x80:"1",0x100:"2",0xc0:"3",0xe0:"4",0x180:"-1",0x400:"-2",0x4c0:"-3",0x4e0:"-4"]
            map("color", 0x1003, colors)
            if let saturation = scalar(0x1003), colors[saturation] != nil || saturation == 0x8000 {
                map("film", 0x1401, [0:"PROVIA / 标准",0x120:"ASTIA / 柔和",0x200:"Velvia / 鲜艳",0x500:"PRO Neg. Std",0x501:"PRO Neg. Hi",0x600:"CLASSIC CHROME",0x700:"ETERNA / 电影",0x800:"CLASSIC Neg.",0x900:"ETERNA BLEACH BYPASS",0xa00:"NOSTALGIC Neg.",0xb00:"REALA ACE"])
            }
        }
        map("wb", 0x1002, [0:"AUTO",1:"自动：白色优先",2:"自动：氛围优先",0x100:"日光",0x300:"荧光灯 1",0x301:"荧光灯 2",0x302:"荧光灯 3",0x400:"白炽灯",0x600:"水下",0xf00:"自定义 1",0xf01:"自定义 2",0xf02:"自定义 3",0xff0:"色温"])
        // 0x200 is documented as Cloudy, not the app's Shade. Leave it unknown.
        if values["wb"] == "色温", let kelvin = scalar(0x1005), (2500...10000).contains(kelvin), kelvin % 10 == 0 { values["kelvin"] = String(kelvin) }
        if let wb = tags[0x100a], wb.count == 2 {
            for (key, raw) in zip(["wbR", "wbB"], wb) where raw % 20 == 0 && (-180...180).contains(raw) { values[key] = String(raw / 20) }
        }
        map("sharpness", 0x1001, [0:"-4",1:"-3",2:"-2",3:"0",4:"2",5:"3",6:"4",0x82:"-1",0x84:"1"])
        map("noise", 0x100e, [0:"0",0x100:"2",0x180:"1",0x1c0:"3",0x1e0:"4",0x200:"-2",0x280:"-1",0x2c0:"-3",0x2e0:"-4"])
        if let raw = scalar(0x100f), raw % 1000 == 0, (-5000...5000).contains(raw) { values["clarity"] = String(raw / 1000) }
        for (key, tag) in [("shadows",0x1040),("highlights",0x1041)] {
            if let raw = scalar(tag), raw % 8 == 0, (-64...32).contains(raw) { values[key] = String(format: "%g", -Double(raw) / 16) }
        }
        for (key, tag) in [("grain",0x1047),("chrome",0x1048),("blue",0x104e)] { map(key, tag, [0:"OFF",32:"WEAK",64:"STRONG"]) }
        map("grainSize", 0x104c, [16:"SMALL",32:"LARGE"])
        map("lmo", 0x1045, [0:"OFF",1:"ON"])
        for (key, tag) in [("monoWC",0x1049),("monoGM",0x104b)] {
            if let raw = scalar(tag), (-18...18).contains(raw) { values[key] = String(raw) }
        }
        if scalar(0x1443) == 0 { values["drPriority"] = "AUTO" }
        else if scalar(0x1443) == 1 { map("drPriority", 0x1445, [1:"WEAK",2:"STRONG"]) }
        // An absent priority tag does NOT establish OFF.
        if scalar(0x1402) == 0 { values["dr"] = "AUTO" }
        else if scalar(0x1402) == 0x100 { values["dr"] = "DR100" }
        else if scalar(0x1402) == 1 { map("dr", 0x1403, [100:"DR100",200:"DR200",400:"DR400"]) }
        return .init(values: XT5.normalized(values), notes: ["仅使用可可靠转换的字段；缺失值不等于 OFF。"])
    }
}

private struct TIFFEntry { var type: Int; var count: Int; var position: Int }
private struct TIFFReader {
    let data: Data
    let little: Bool
    func uint(_ offset: Int, _ size: Int) throws -> Int {
        guard offset >= 0, size > 0, offset <= data.count, size <= data.count - offset else { throw FrameError("元数据偏移或长度越界") }
        var result: UInt64 = 0
        for i in 0..<size { result |= UInt64(data[offset + i]) << (8 * (little ? i : size - i - 1)) }
        guard let value = Int(exactly: result) else { throw FrameError("元数据整数越界") }
        return value
    }
    func directory(at offset: Int) throws -> [Int: TIFFEntry] {
        let count = try uint(offset, 2)
        guard count <= 4096, offset <= data.count - 2, count <= (data.count - offset - 2) / 12 else { throw FrameError("元数据目录截断") }
        var result: [Int: TIFFEntry] = [:]
        for i in 0..<count {
            let p = offset + 2 + i * 12
            let id = try uint(p, 2)
            guard result[id] == nil else { throw FrameError("元数据包含重复标签") }
            result[id] = try TIFFEntry(type: uint(p+2, 2), count: uint(p+4, 4), position: p+8)
        }
        return result
    }
    func bytes(_ entry: TIFFEntry) throws -> Data {
        let sizes = [1:1,2:1,3:2,4:4,5:8,6:1,7:1,8:2,9:4,10:8,11:4,12:8]
        guard let size = sizes[entry.type], entry.count <= data.count / size else { throw FrameError("元数据类型或数量无效") }
        let length = entry.count * size
        let offset = length <= 4 ? entry.position : try uint(entry.position, 4)
        guard offset <= data.count, length <= data.count - offset else { throw FrameError("元数据内容越界") }
        return Data(data[offset..<(offset + length)])
    }
    func numbers(_ entry: TIFFEntry) throws -> [Int64]? {
        guard [1,3,4,6,8,9].contains(entry.type), entry.count <= 128 else { return nil }
        let bytes = try bytes(entry)
        let size = [1:1,3:2,4:4,6:1,8:2,9:4][entry.type]!
        let reader = TIFFReader(data: bytes, little: little)
        return try (0..<entry.count).map { i in
            let raw = Int64(try reader.uint(i * size, size))
            if [6,8,9].contains(entry.type), raw & (1 << (size * 8 - 1)) != 0 { return raw - (1 << (size * 8)) }
            return raw
        }
    }
}
