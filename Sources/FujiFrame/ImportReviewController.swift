import SwiftUI
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

@MainActor final class ImportReviewController: ObservableObject, Identifiable {
    let id = UUID()
    let recipes: [Recipe]
    let versions: [RecipeVersion]
    @Published var items: [ImportReviewItem] = []
    @Published var processing = true
    @Published var committing = false
    @Published var cancelling = false
    @Published var progress = 0.0
    @Published var message = "准备读取照片…"
    @Published var error: String?
    private let library: PhotoLibrary
    private let analyzer: ImportAnalyzer
    private var worker: Task<Void, Never>?
    private var results: [ImportResult] = []
    var onClose: (([ImportResult]) -> Void)?
    init(library: PhotoLibrary, recipes: [Recipe], versions: [RecipeVersion]) throws {
        self.library = library; self.recipes = recipes; self.versions = versions; analyzer = try ImportAnalyzer()
    }
    var readyCount: Int { items.filter(\.ready).count }
    var unresolvedCount: Int { items.filter(\.needsAction).count }
    var canConfirm: Bool { !processing && !committing && !cancelling && readyCount > 0 && unresolvedCount == 0 }
    var canEdit: Bool { !processing && !committing && !cancelling }
    func label(_ id: String?) -> String {
        guard let id, let version = versions.first(where: { $0.id == id }), let recipe = recipes.first(where: { $0.id == version.recipeID }) else { return "未分配" }
        return "\(recipe.name) · v\(version.number)\(recipe.archived ? "（已归档）" : "")"
    }
    func start(_ urls: [URL], fixedTarget: String?) {
        // Deduplicate only identical URLs; content dedup remains a confirmed import operation.
        var seen: Set<URL> = []
        let urls = urls.filter { seen.insert($0.standardizedFileURL).inserted }
        worker = Task {
            do {
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    message = "分析 \(index + 1) / \(urls.count)：\(url.lastPathComponent)"
                    let item = try await analyzer.analyze(url, recipes: recipes, versions: versions, fixedTarget: fixedTarget)
                    try Task.checkCancellation()
                    items.append(item); progress = Double(index + 1) / Double(urls.count)
                }
                processing = false; message = "分析完成。确认前不会写入正式资料库。"
            } catch is CancellationError { await finish() }
            catch { self.error = error.localizedDescription; processing = false }
            worker = nil
        }
    }
    func assign(_ ids: Set<UUID>, target: String?) {
        guard canEdit, target == nil || versions.contains(where: { $0.id == target }) else { return }
        for i in items.indices where ids.contains(items[i].id) && !items[i].completed { items[i].assign(target) }
    }
    func exclude(_ ids: Set<UUID>, value: Bool) {
        guard canEdit else { return }
        for i in items.indices where ids.contains(items[i].id) && !items[i].completed { items[i].excluded = value }
    }
    func reanalyze(_ ids: Set<UUID>) {
        guard canEdit else { return }
        processing = true
        worker = Task {
            do {
                let indices = items.indices.filter { ids.contains(items[$0].id) && !items[$0].completed }
                for (index, i) in indices.enumerated() {
                    try Task.checkCancellation()
                    let previous = items[i]
                    message = "重新分析：\(previous.source.lastPathComponent)"
                    var fresh = try await analyzer.analyze(previous.source, recipes: recipes, versions: versions, fixedTarget: previous.manual ? previous.targetVersionID : nil)
                    try Task.checkCancellation()
                    // A changed file must be reviewed again; preserve only explicit manual targets.
                    fresh.excluded = previous.excluded
                    items[i] = fresh; progress = Double(index + 1) / Double(max(indices.count, 1))
                }
                processing = false; message = "重新分析完成，请检查目标后确认。"
            } catch is CancellationError { await finish() }
            catch { self.error = error.localizedDescription; processing = false }
            worker = nil
        }
    }
    func confirm() {
        guard canConfirm else { return }
        committing = true
        worker = Task {
            let indices = items.indices.filter { items[$0].ready }
            for (index, i) in indices.enumerated() {
                let item = items[i]
                message = "导入 \(index + 1) / \(indices.count)：\(item.source.lastPathComponent)"
                let result = await library.importPhoto(item.source, versionID: item.targetVersionID!, expectedHash: item.hash!)
                results.append(result)
                if result.failed { items[i].importError = result.message }
                else { items[i].completed = true; items[i].importError = nil }
                progress = Double(index + 1) / Double(indices.count)
            }
            committing = false
            if items.contains(where: { $0.importError != nil && !$0.excluded }) {
                message = "部分导入失败，成功项已保留。可重试失败项；原文件变化时请先重新分析。"
            } else { await finish() }
            worker = nil
        }
    }
    func cancel() {
        guard !committing, !cancelling else { return }
        cancelling = true
        if let worker { worker.cancel() }
        else { Task { await finish() } }
    }
    private func finish() async {
        await analyzer.cleanup()
        onClose?(results)
        onClose = nil
    }
}
