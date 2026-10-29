import SwiftUI
import AppKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

@MainActor final class AppModel: ObservableObject {
    @Published var library: PhotoLibrary?
    @Published var recipes: [Recipe] = []
    @Published var versions: [RecipeVersion] = []
    @Published var photos: [Photo] = []
    @Published var links: [PhotoLink] = []
    @Published var selectedRecipe: String?
    @Published var selectedVersion = ""
    @Published var selectedLink: String?
    @Published var search = ""
    @Published var film = ""
    @Published var showArchived = false
    @Published var filterDates = false
    @Published var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @Published var dateTo = Date()
    @Published var busy = false
    @Published var progress = 0.0
    @Published var status = ""
    @Published var error: String?
    @Published var results: [ImportResult] = []
    @Published var showResults = false
    @Published var review: ImportReviewController?
    private var photoIndex: [String: Photo] = [:]
    private var scopedRoot: URL?
    var recipe: Recipe? { recipes.first { $0.id == selectedRecipe } }
    var recipeVersions: [RecipeVersion] { versions.filter { $0.recipeID == selectedRecipe }.sorted { $0.number > $1.number } }
    var version: RecipeVersion? { recipeVersions.first { $0.id == selectedVersion } }
    var visibleRecipes: [Recipe] {
        recipes.filter { r in
            r.archived == showArchived && (search.isEmpty || r.name.localizedCaseInsensitiveContains(search) || r.summary.localizedCaseInsensitiveContains(search) || links.contains { l in
                l.filename.localizedCaseInsensitiveContains(search) && versions.contains { $0.id == l.versionID && $0.recipeID == r.id }
            }) && (film.isEmpty || versions.contains { $0.recipeID == r.id && $0.parameters["film"] == film })
        }
    }
    var visibleLinks: [PhotoLink] {
        let recipeMatches = recipe.map { $0.name.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search) } ?? false
        let versionIDs = Set(recipeVersions.filter { (selectedVersion.isEmpty || $0.id == selectedVersion) && (film.isEmpty || $0.parameters["film"] == film) }.map(\.id))
        return links.filter { link in
            guard versionIDs.contains(link.versionID), search.isEmpty || recipeMatches || link.filename.localizedCaseInsensitiveContains(search) else { return false }
            if filterDates {
                guard let captured = photoIndex[link.photoID]?.metadata.captured, captured.count >= 10 else { return false }
                let day = String(captured.prefix(10))
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy:MM:dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
                return day >= formatter.string(from: dateFrom) && day <= formatter.string(from: dateTo)
            }
            return true
        }
    }
    var currentLink: PhotoLink? { visibleLinks.first { $0.id == selectedLink } }
    func photo(_ link: PhotoLink) -> Photo? { photoIndex[link.photoID] }
    func selectRecipe() { selectedVersion = recipeVersions.first?.id ?? ""; selectedLink = nil }
    func navigate(_ delta: Int) {
        let list = visibleLinks
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedLink } ?? (delta > 0 ? -1 : list.count)
        selectedLink = list[min(max(index + delta, 0), list.count - 1)].id
    }
    func reload() async throws {
        guard let library else { return }
        let snapshot = try await library.snapshot()
        recipes = snapshot.recipes; versions = snapshot.versions; photos = snapshot.photos; links = snapshot.links
        photoIndex = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
    }
    func startup() {
        guard let path = UserDefaults.standard.string(forKey: "libraryPath") else { return }
        openLibrary(URL(fileURLWithPath: path), create: false)
    }
    func openLibrary(_ url: URL, create: Bool) {
        guard !busy else { return }
        busy = true; status = "正在打开资料库…"
        Task {
            do {
                let lib = try await Task.detached { try PhotoLibrary(root: url, create: create) }.value
                if let scopedRoot { scopedRoot.stopAccessingSecurityScopedResource() }
                if url.startAccessingSecurityScopedResource() { scopedRoot = url }
                library = lib
                UserDefaults.standard.set(url.path, forKey: "libraryPath")
                try await reload()
                search = ""; film = ""; showArchived = false; filterDates = false; results = []; progress = 0
                selectedRecipe = recipes.first(where: { !$0.archived })?.id
                selectRecipe()
                status = "资料库已打开"
            } catch { self.error = error.localizedDescription; status = "未能打开资料库" }
            busy = false
        }
    }
    func closeLibrary() {
        guard !busy else { return }
        library = nil; recipes = []; versions = []; photos = []; links = []; photoIndex = [:]
        selectedRecipe = nil; selectedVersion = ""; selectedLink = nil
        search = ""; film = ""; showArchived = false; filterDates = false
        status = ""; results = []; progress = 0
        if let scopedRoot { scopedRoot.stopAccessingSecurityScopedResource(); self.scopedRoot = nil }
        UserDefaults.standard.removeObject(forKey: "libraryPath")
    }
    func chooseLibrary(create: Bool) {
        guard !busy else { return }
        if create {
            let panel = NSSavePanel(); panel.title = "创建 FujiFrame 资料库"; panel.prompt = "创建"
            panel.nameFieldStringValue = "FujiFrame Library"
            panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url { openLibrary(url, create: true) }
        } else {
            let panel = NSOpenPanel(); panel.title = "选择资料库文件夹"; panel.canChooseFiles = false; panel.canChooseDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                if url.standardizedFileURL == library?.root { return }
                openLibrary(url, create: false)
            }
        }
    }
    func save(_ recipe: Recipe, parameters: [String: String], firmware: String, exposure: String, note: String) async -> Bool {
        guard let library, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let version = try await library.saveRecipe(recipe, parameters: XT5.normalized(parameters), firmware: firmware, exposureAdvice: exposure, note: note)
            try await reload(); selectedRecipe = recipe.id; selectedVersion = version.id; selectedLink = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func archive(_ recipe: Recipe) {
        guard let library, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await library.archive(recipe); try await reload(); selectedRecipe = nil; selectedLink = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    func choosePhotos(fixedTarget: String? = nil) {
        guard library != nil, !busy else { return }
        guard !recipes.isEmpty else { error = "请先创建至少一个配方，再导入照片。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg]; panel.allowsMultipleSelection = true
        panel.title = fixedTarget == nil ? "智能导入 JPEG" : "导入到当前版本"; panel.prompt = "分析照片"
        if panel.runModal() == .OK { importPhotos(panel.urls, fixedTarget: fixedTarget) }
    }
    func importPhotos(_ urls: [URL], fixedTarget: String? = nil) {
        guard let library, !busy, !urls.isEmpty else { return }
        guard !recipes.isEmpty else { error = "请先创建至少一个配方，再导入照片。"; return }
        do {
            let session = try ImportReviewController(library: library, recipes: recipes, versions: versions)
            busy = true; status = "正在审核导入照片…"; progress = 0
            session.onClose = { [weak self] report in
                guard let self else { return }
                self.review = nil
                Task {
                    do { try await self.reload() } catch { self.error = error.localizedDescription }
                    self.results = report
                    self.status = report.isEmpty ? "已取消导入，资料库未改变" : "导入结束：\(report.count) 次处理，\(report.filter(\.failed).count) 次失败"
                    self.busy = false
                }
            }
            review = session; session.start(urls, fixedTarget: fixedTarget)
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ link: PhotoLink) {
        guard let library, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await library.removeLink(link); selectedLink = nil; try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    func move(_ link: PhotoLink, to id: String) async -> Bool {
        guard let library, !busy else { return false }
        busy = true; defer { busy = false }
        do { try await library.moveLink(link, to: id); selectedLink = nil; try await reload(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func backup() {
        guard let library, !busy else { return }
        let panel = NSSavePanel(); panel.title = "备份整个资料库"; panel.prompt = "备份"
        panel.nameFieldStringValue = "FujiFrame Backup \(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "正在校验并备份，暂时停止写入…"
        Task {
            do { try await library.backup(to: url); status = "备份完成"; NSWorkspace.shared.activateFileViewerSelecting([url]) }
            catch { self.error = error.localizedDescription; status = "备份失败" }
            busy = false
        }
    }
    func restore() {
        guard !busy else { return }
        let source = NSOpenPanel(); source.title = "选择备份文件夹"; source.canChooseFiles = false; source.canChooseDirectories = true
        guard source.runModal() == .OK, let backup = source.url else { return }
        let target = NSSavePanel(); target.title = "恢复到新的资料库文件夹"; target.prompt = "恢复"; target.nameFieldStringValue = "FujiFrame Restored Library"
        guard target.runModal() == .OK, let destination = target.url else { return }
        busy = true; status = "正在验证备份并恢复…"
        Task {
            do {
                try await Task.detached { try PhotoLibrary.restore(from: backup, to: destination) }.value
                busy = false; openLibrary(destination, create: false)
            } catch { self.error = error.localizedDescription; busy = false; status = "恢复失败" }
        }
    }
}
