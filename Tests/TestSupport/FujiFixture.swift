import Foundation

/// Construct synthetic EXIF for parser tests; these bytes are not camera samples.
public enum FujiFixture {
    public static func integer(_ value: Int64, size: Int, little: Bool = true) -> Data {
        let raw = UInt64(bitPattern: value)
        return Data((0..<size).map { UInt8(truncatingIfNeeded: raw >> (8 * (little ? $0 : size - $0 - 1))) })
    }
    public static func maker(_ tags: [Int: [Int64]]) -> Data {
        let sorted = tags.sorted { $0.key < $1.key }
        var header = Data("FUJIFILM".utf8) + integer(12, size: 4) + integer(Int64(sorted.count), size: 2)
        var extra = Data()
        let extraOffset = 12 + 2 + 12 * sorted.count + 4
        for (id, values) in sorted {
            // signed LONG covers negative tone values and WB pairs; BYTE for BW tones.
            header += integer(Int64(id), size: 2) + integer(9, size: 2) + integer(Int64(values.count), size: 4)
            let bytes = values.reduce(Data()) { $0 + integer($1, size: 4) }
            if bytes.count <= 4 { header += bytes + Data(repeating: 0, count: 4 - bytes.count) }
            else { header += integer(Int64(extraOffset + extra.count), size: 4); extra += bytes }
        }
        return header + integer(0, size: 4) + extra
    }
    public static func exif(_ tags: [Int: [Int64]], little: Bool = true) -> Data {
        func n(_ value: Int64, _ size: Int) -> Data { integer(value, size: size, little: little) }
        let makerData = maker(tags)
        var data = Data(little ? [0x49,0x49] : [0x4d,0x4d]) + n(42,2) + n(8,4)
        data += n(2,2)
        data += n(0x110,2) + n(2,2) + n(5,4) + n(38,4)
        data += n(0x8769,2) + n(4,2) + n(1,4) + n(44,4)
        data += n(0,4) + Data([0x58,0x2d,0x54,0x35,0,0])
        data += n(1,2) + n(0x927c,2) + n(7,2) + n(Int64(makerData.count),4) + n(62,4) + n(0,4)
        return data + makerData
    }
    public static func inject(_ tags: [Int: [Int64]], into url: URL) throws {
        let jpeg = try Data(contentsOf: url)
        let payload = Data([0x45,0x78,0x69,0x66,0,0]) + exif(tags)
        let marker = Data([0xff,0xe1]) + integer(Int64(payload.count + 2), size: 2, little: false)
        try (Data(jpeg.prefix(2)) + marker + payload + jpeg.dropFirst(2)).write(to: url)
    }
    public static let daylight: [Int: [Int64]] = [0x1401:[0x600],0x1003:[0],0x1002:[0x100],0x100a:[40,-60],0x1041:[16],0x1040:[-16],0x100e:[0x2e0],0x100f:[0],0x1047:[32],0x104c:[16]]
}
