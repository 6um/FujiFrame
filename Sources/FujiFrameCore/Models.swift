import Foundation

public struct FrameError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ParameterField: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let options: [String]
    public let advanced: Bool
    public init(_ id: String, _ label: String, _ options: [String], advanced: Bool = false) {
        self.id = id; self.label = label; self.options = options; self.advanced = advanced
    }
}

public enum XT5 {
    public static let films = ["PROVIA / 标准", "Velvia / 鲜艳", "ASTIA / 柔和", "CLASSIC CHROME", "REALA ACE", "PRO Neg. Hi", "PRO Neg. Std", "CLASSIC Neg.", "NOSTALGIC Neg.", "ETERNA / 电影", "ETERNA BLEACH BYPASS", "ACROS", "ACROS + Ye", "ACROS + R", "ACROS + G", "MONOCHROME", "MONOCHROME + Ye", "MONOCHROME + R", "MONOCHROME + G", "SEPIA"]
    static func numbers(_ range: ClosedRange<Int>) -> [String] { range.map { String($0) } }
    static let effects = ["OFF", "WEAK", "STRONG"]
    public static let fields: [ParameterField] = [
        .init("film", "胶片模拟", films),
        .init("drPriority", "动态范围优先级", ["OFF", "AUTO", "WEAK", "STRONG"]),
        .init("dr", "动态范围", ["AUTO", "DR100", "DR200", "DR400"]),
        .init("wb", "白平衡", ["AUTO", "自动：白色优先", "自动：氛围优先", "日光", "阴影", "荧光灯 1", "荧光灯 2", "荧光灯 3", "白炽灯", "水下", "色温", "自定义 1", "自定义 2", "自定义 3"]),
        .init("kelvin", "色温 (K)", stride(from: 2500, through: 10000, by: 10).map { String($0) }),
        .init("wbR", "白平衡偏移 R", numbers(-9...9)),
        .init("wbB", "白平衡偏移 B", numbers(-9...9)),
        .init("highlights", "高光", stride(from: -2.0, through: 4.0, by: 0.5).map { String(format: "%g", $0) }),
        .init("shadows", "阴影", stride(from: -2.0, through: 4.0, by: 0.5).map { String(format: "%g", $0) }),
        .init("color", "色彩", numbers(-4...4)),
        .init("sharpness", "锐度", numbers(-4...4)),
        .init("noise", "高 ISO 降噪", numbers(-4...4)),
        .init("clarity", "清晰度", numbers(-5...5)),
        .init("grain", "颗粒强度", effects),
        .init("grainSize", "颗粒大小", ["SMALL", "LARGE"]),
        .init("chrome", "彩色效果", effects),
        .init("blue", "彩色 FX 蓝色", effects),
        .init("monoWC", "黑白色调：暖 / 冷", numbers(-18...18), advanced: true),
        .init("monoGM", "黑白色调：绿 / 洋红", numbers(-18...18), advanced: true),
        .init("skin", "柔肤", effects, advanced: true),
        .init("longNR", "长曝光降噪", ["OFF", "ON"], advanced: true),
        .init("lmo", "镜头优化", ["OFF", "ON"], advanced: true),
        .init("space", "色彩空间", ["sRGB", "Adobe RGB"], advanced: true)
    ]
    public static func disabled(_ key: String, values: [String: String]) -> Bool {
        if ["dr", "highlights", "shadows"].contains(key), let p = values["drPriority"], p != "OFF", !p.isEmpty { return true }
        if key == "kelvin" { return values["wb"] != "色温" }
        if key == "grainSize" { return values["grain"] == "OFF" }
        if ["monoWC", "monoGM"].contains(key) {
            let film = values["film"] ?? ""
            return !film.hasPrefix("ACROS") && !film.hasPrefix("MONOCHROME")
        }
        return false
    }
    public static func displayValue(_ key: String, values: [String: String]) -> String {
        if let value = values[key], !value.isEmpty { return value }
        if ["dr", "highlights", "shadows"].contains(key), let priority = values["drPriority"], !priority.isEmpty, priority != "OFF" { return "由相机自动控制" }
        if key == "kelvin", let wb = values["wb"], !wb.isEmpty, wb != "色温" { return "不适用" }
        if key == "grainSize", values["grain"] == "OFF" { return "不适用" }
        if ["monoWC", "monoGM"].contains(key), let film = values["film"], !film.isEmpty, !film.hasPrefix("ACROS"), !film.hasPrefix("MONOCHROME") { return "不适用" }
        return "未记录"
    }
    public static func normalized(_ values: [String: String]) -> [String: String] {
        values.filter { !$0.value.isEmpty && !disabled($0.key, values: values) }
    }
    public static func validate(_ values: [String: String]) throws {
        for (key, value) in values {
            guard let field = fields.first(where: { $0.id == key }), field.options.contains(value) else { throw FrameError("无效配方参数：\(key) = \(value)") }
            if disabled(key, values: values) { throw FrameError("参数冲突：\(field.label)") }
        }
    }
}

public struct Recipe: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var source: String
    public var notes: String?
    public var archived: Bool
    public init(id: String = UUID().uuidString, name: String = "", summary: String = "", source: String = "", archived: Bool = false, notes: String? = nil) {
        self.id = id; self.name = name; self.summary = summary; self.source = source; self.archived = archived; self.notes = notes
    }
}
public struct RecipeVersion: Codable, Identifiable, Sendable {
    public var id: String
    public var recipeID: String
    public var number: Int
    public var parameters: [String: String]
    public var firmware: String
    public var exposureAdvice: String
    public var note: String
    public var created: Date
    public init(id: String = UUID().uuidString, recipeID: String, number: Int = 1, parameters: [String: String] = [:], firmware: String = "", exposureAdvice: String = "", note: String = "", created: Date = Date()) {
        self.id = id; self.recipeID = recipeID; self.number = number; self.parameters = parameters
        self.firmware = firmware; self.exposureAdvice = exposureAdvice; self.note = note; self.created = created
    }
}
public struct PhotoMetadata: Codable, Sendable {
    public var aperture: Double?
    public var exposure: Double?
    public var iso: Int?
    public var compensation: Double?
    public var focalLength: Double?
    public var lens: String?
    public var camera: String?
    public var captured: String?
    public var width: Int?
    public var height: Int?
    public var orientation: Int?
    public init() {}
    public var shutterText: String {
        guard let t = exposure, t > 0 else { return "未记录" }
        if t < 1 { return "1/\(Int((1 / t).rounded())) s" }
        return String(format: "%g s", t)
    }
    public var rows: [(String, String)] {
        [("光圈", aperture.map { String(format: "ƒ/%g", $0) } ?? "未记录"),
         ("快门", shutterText), ("ISO", iso.map(String.init) ?? "未记录"),
         ("曝光补偿", compensation.map { String(format: "%+.2g EV", $0) } ?? "未记录"),
         ("焦距", focalLength.map { String(format: "%g mm", $0) } ?? "未记录"),
         ("镜头", lens ?? "未记录"), ("机型", camera ?? "未记录"),
         ("拍摄时间", captured ?? "未记录"),
         ("尺寸", width.flatMap { w in height.map { "\(w) × \($0)" } } ?? "未记录")]
    }
}
public struct Photo: Codable, Identifiable, Sendable {
    public var id: String // SHA-256
    public var relativePath: String
    public var metadata: PhotoMetadata
}
public struct PhotoLink: Codable, Identifiable, Sendable {
    public var id: String
    public var photoID: String
    public var versionID: String
    public var filename: String
    public var imported: Date
}
public struct LibrarySnapshot: Sendable {
    public var recipes: [Recipe]
    public var versions: [RecipeVersion]
    public var photos: [Photo]
    public var links: [PhotoLink]
}
public struct ImportResult: Identifiable, Sendable {
    public let id = UUID()
    public let filename: String
    public let message: String
    public let failed: Bool
}
