import Foundation

public struct ParameterComparison: Identifiable, Sendable {
    public var id: String
    public var expected: String
    public var detected: String?
    public var agrees: Bool { detected == expected }
}
public struct RecipeMatch: Identifiable, Sendable {
    public var id: String { versionID }
    public var versionID: String
    public var comparisons: [ParameterComparison]
    public var matches: Int { comparisons.filter(\.agrees).count }
    public var missing: Int { comparisons.filter { $0.detected == nil }.count }
    public var conflicts: Int { comparisons.filter { $0.detected != nil && !$0.agrees }.count }
    public var strict: Bool {
        comparisons.count >= 4 && missing == 0 && conflicts == 0 && comparisons.contains { $0.id == "film" && $0.agrees }
    }
}
public struct MatchSuggestion: Sendable {
    public var targetVersionID: String?
    public var candidates: [RecipeMatch]
    public var reason: String
    public init(targetVersionID: String? = nil, candidates: [RecipeMatch], reason: String) {
        self.targetVersionID = targetVersionID; self.candidates = candidates; self.reason = reason
    }
}
public enum RecipeMatcher {
    public static func compare(_ settings: DetectedRecipeSettings, to version: RecipeVersion) -> RecipeMatch {
        let parameters = XT5.normalized(version.parameters)
        return RecipeMatch(versionID: version.id, comparisons: parameters.keys.sorted().map {
            ParameterComparison(id: $0, expected: parameters[$0]!, detected: settings.values[$0])
        })
    }
    public static func suggest(_ settings: DetectedRecipeSettings, recipes: [Recipe], versions: [RecipeVersion]) -> MatchSuggestion {
        let latest = recipes.filter { !$0.archived }.compactMap { recipe in
            versions.filter { $0.recipeID == recipe.id }.max { $0.number < $1.number }
        }
        guard let film = settings.values["film"] else { return .init(candidates: [], reason: "无法可靠读取胶片模拟，请手动指定。") }
        let candidates = latest.filter { $0.parameters["film"] == film }.map { compare(settings, to: $0) }.sorted {
            if $0.conflicts != $1.conflicts { return $0.conflicts < $1.conflicts }
            if $0.matches != $1.matches { return $0.matches > $1.matches }
            if $0.missing != $1.missing { return $0.missing < $1.missing }
            return $0.versionID < $1.versionID
        }
        let strict = candidates.filter(\.strict)
        return .init(targetVersionID: strict.count == 1 ? strict[0].versionID : nil,
                     candidates: Array(candidates.prefix(3)),
                     reason: strict.count == 1 ? "唯一严格匹配；等待你确认导入。" : strict.count > 1 ? "多个配方完全符合，请手动指定。" : candidates.isEmpty ? "最新配方中没有相同胶片模拟，请手动指定。" : "参数不同或信息不足，请查看差异后指定。")
    }
}
public struct ImportReviewItem: Identifiable, Sendable {
    public let id: UUID
    public var source: URL
    public var hash: String?
    public var preview: URL?
    public var settings: DetectedRecipeSettings
    public var suggestion: MatchSuggestion
    public var targetVersionID: String?
    public var excluded = false
    public var manual = false
    public var analysisError: String?
    public var importError: String?
    public var completed = false
    public init(id: UUID = UUID(), source: URL, hash: String? = nil, preview: URL? = nil, settings: DetectedRecipeSettings = .init(), suggestion: MatchSuggestion = .init(candidates: [], reason: "等待分析"), targetVersionID: String? = nil, analysisError: String? = nil) {
        self.id = id; self.source = source; self.hash = hash; self.preview = preview; self.settings = settings
        self.suggestion = suggestion; self.targetVersionID = targetVersionID; self.analysisError = analysisError
    }
    public var ready: Bool { !excluded && !completed && analysisError == nil && hash != nil && targetVersionID != nil }
    public var needsAction: Bool { !excluded && !completed && !ready }
    public mutating func assign(_ target: String?) { targetVersionID = target; manual = true; importError = nil }
    public var status: String {
        if completed { return "已完成" }
        if excluded { return "已排除" }
        if analysisError != nil { return "读取失败" }
        if importError != nil { return "导入失败，可重试" }
        if targetVersionID != nil { return manual ? "手动指定" : "已匹配" }
        return "待处理"
    }
}
/// Isolated actor bounds analysis to one file at a time and owns preview lifetime.
public actor ImportAnalyzer {
    private let directory: URL
    public init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FujiFrame-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func analyze(_ url: URL, recipes: [Recipe], versions: [RecipeVersion], fixedTarget: String? = nil) throws -> ImportReviewItem {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let preview = directory.appendingPathComponent("\(id).jpg")
        do {
            let hash = try Imaging.hash(url)
            let metadata = try Imaging.inspect(url)
            var settings: DetectedRecipeSettings
            do { settings = try FujiMetadata.read(url, camera: metadata.camera) }
            catch is CancellationError { throw CancellationError() }
            catch { settings = .init(notes: ["配方参数无法解析：\(error.localizedDescription)。仍可手动指定。"]) }
            try Task.checkCancellation()
            try Imaging.thumbnail(url, to: preview)
            guard try Imaging.hash(url) == hash else { throw FrameError("分析期间原文件发生变化，请重新分析") }
            let suggestion = RecipeMatcher.suggest(settings, recipes: recipes, versions: versions)
            var item = ImportReviewItem(id: id, source: url, hash: hash, preview: preview, settings: settings, suggestion: suggestion, targetVersionID: fixedTarget ?? suggestion.targetVersionID)
            item.manual = fixedTarget != nil
            return item
        } catch is CancellationError { throw CancellationError() }
        catch {
            try? FileManager.default.removeItem(at: preview)
            return ImportReviewItem(id: id, source: url, targetVersionID: fixedTarget, analysisError: error.localizedDescription)
        }
    }
    public func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
