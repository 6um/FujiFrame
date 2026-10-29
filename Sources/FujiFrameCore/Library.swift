import Foundation
import Darwin

private final class LibraryLock {
    let descriptor: Int32
    init(_ root: URL) throws {
        descriptor = Darwin.open(root.appendingPathComponent(".library-lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw FrameError("无法锁定资料库，请检查文件夹权限") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw FrameError("资料库已在另一个 FujiFrame 窗口或进程中打开")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
private struct Manifest: Codable {
    var format: Int
    var created: Date
    var files: [String: String]
}

public actor PhotoLibrary {
    public nonisolated let root: URL
    private let db: Database
    private let lock: LibraryLock
    private let fm = FileManager.default
    public init(root: URL, create: Bool = false) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let database = self.root.appendingPathComponent("library.sqlite")
        if !fm.fileExists(atPath: database.path) {
            guard create else { throw FrameError("所选文件夹没有 FujiFrame 资料库") }
            if fm.fileExists(atPath: self.root.path) {
                let contents = try fm.contentsOfDirectory(atPath: self.root.path).filter { $0 != ".DS_Store" }
                guard contents.isEmpty else { throw FrameError("请为新资料库选择空文件夹") }
            } else { try fm.createDirectory(at: self.root, withIntermediateDirectories: true) }
        }
        self.lock = try LibraryLock(self.root)
        self.db = try Database(database, create: create)
        try db.verify()
        for name in ["originals", "thumbnails", ".staging"] {
            try fm.createDirectory(at: self.root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        // These files were never committed to the database. Original files are never purged here.
        for url in try fm.contentsOfDirectory(at: self.root.appendingPathComponent(".staging"), includingPropertiesForKeys: nil) { try fm.removeItem(at: url) }
    }
    public func snapshot() throws -> LibrarySnapshot {
        LibrarySnapshot(recipes: try db.all("recipes", as: Recipe.self).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                        versions: try db.all("versions", as: RecipeVersion.self).sorted { $0.number > $1.number },
                        photos: try db.all("photos", as: Photo.self),
                        links: try db.all("links", as: PhotoLink.self).sorted { $0.imported > $1.imported })
    }
    @discardableResult
    public func saveRecipe(_ recipe: Recipe, parameters: [String: String], firmware: String, exposureAdvice: String, note: String) throws -> RecipeVersion {
        var recipe = recipe
        recipe.name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipe.name.isEmpty else { throw FrameError("请填写配方名称") }
        if !recipe.source.isEmpty {
            guard let url = URL(string: recipe.source), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw FrameError("来源链接须为有效的 http 或 https 地址") }
        }
        try XT5.validate(parameters)
        return try db.transaction {
            let versions = try db.all("versions", as: RecipeVersion.self).filter { $0.recipeID == recipe.id }
            let latest = versions.max { $0.number < $1.number }
            try db.execute("INSERT INTO recipes(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body", [recipe.id, try Database.json(recipe)])
            if let latest, latest.parameters == parameters, latest.firmware == firmware, latest.exposureAdvice == exposureAdvice { return latest }
            let version = RecipeVersion(recipeID: recipe.id, number: (latest?.number ?? 0) + 1, parameters: parameters, firmware: firmware, exposureAdvice: exposureAdvice, note: note)
            try db.execute("INSERT INTO versions(id,recipeID,number,body) VALUES(?,?,?,?)", [version.id, recipe.id, String(version.number), try Database.json(version)])
            return version
        }
    }
    public func archive(_ recipe: Recipe) throws {
        var updated = recipe; updated.archived.toggle()
        try db.execute("UPDATE recipes SET body=? WHERE id=?", [try Database.json(updated), recipe.id])
    }
    public func importPhoto(_ source: URL, versionID: String, expectedHash: String? = nil) -> ImportResult {
        let filename = source.lastPathComponent
        var stage: URL?
        do {
            guard !(try db.query("SELECT id FROM versions WHERE id=?", [versionID])).isEmpty else { throw FrameError("配方版本不存在") }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let temp = root.appendingPathComponent(".staging/\(UUID().uuidString).jpg")
            stage = temp
            try fm.copyItem(at: source, to: temp)
            let metadata = try Imaging.inspect(temp)
            let hash = try Imaging.hash(temp)
            if let expectedHash, expectedHash != hash { throw FrameError("原文件已改变，请重新分析并确认后导入") }
            if !(try db.query("SELECT id FROM links WHERE photoID=? AND versionID=?", [hash, versionID])).isEmpty {
                try fm.removeItem(at: temp)
                return ImportResult(filename: filename, message: "已跳过：此版本已有相同照片", failed: false)
            }
            let relative = "originals/\(hash).jpg"
            let destination = root.appendingPathComponent(relative)
            let thumb = root.appendingPathComponent("thumbnails/\(hash).jpg")
            if fm.fileExists(atPath: destination.path) {
                guard try Imaging.hash(destination) == hash else { throw FrameError("资料库原图校验失败，请先从备份恢复") }
                try fm.removeItem(at: temp)
            } else { try fm.moveItem(at: temp, to: destination) }
            // A crash before this commit leaves an unreferenced original; it can be reused on retry.
            try Imaging.thumbnail(destination, to: thumb)
            let photo = Photo(id: hash, relativePath: relative, metadata: metadata)
            let link = PhotoLink(id: UUID().uuidString, photoID: hash, versionID: versionID, filename: filename, imported: Date())
            try db.transaction {
                try db.execute("INSERT OR IGNORE INTO photos(id,body) VALUES(?,?)", [hash, try Database.json(photo)])
                try db.execute("INSERT INTO links(id,photoID,versionID,body) VALUES(?,?,?,?)", [link.id, hash, versionID, try Database.json(link)])
            }
            return ImportResult(filename: filename, message: "已导入", failed: false)
        } catch {
            if let stage { try? fm.removeItem(at: stage) }
            return ImportResult(filename: filename, message: error.localizedDescription, failed: true)
        }
    }
    public func moveLink(_ link: PhotoLink, to versionID: String) throws {
        guard versionID != link.versionID else { return }
        var changed = link; changed.versionID = versionID
        try db.transaction {
            guard !(try db.query("SELECT id FROM versions WHERE id=?", [versionID])).isEmpty else { throw FrameError("目标版本不存在") }
            if (try db.query("SELECT id FROM links WHERE photoID=? AND versionID=?", [link.photoID, versionID])).isEmpty {
                changed.id = UUID().uuidString
                try db.execute("INSERT INTO links(id,photoID,versionID,body) VALUES(?,?,?,?)", [changed.id, changed.photoID, changed.versionID, try Database.json(changed)])
            }
            try db.execute("DELETE FROM links WHERE id=?", [link.id])
        }
    }
    public func removeLink(_ link: PhotoLink) throws {
        guard !(try db.query("SELECT id FROM links WHERE id=?", [link.id])).isEmpty else { return }
        let count = try db.query("SELECT id FROM links WHERE photoID=?", [link.photoID]).count
        if count > 1 { try db.execute("DELETE FROM links WHERE id=?", [link.id]); return }
        guard let photo = try db.all("photos", as: Photo.self).first(where: { $0.id == link.photoID }) else { throw FrameError("照片记录不存在") }
        let original = try safeURL(photo.relativePath)
        var trashed: NSURL?
        if fm.fileExists(atPath: original.path) { try fm.trashItem(at: original, resultingItemURL: &trashed) }
        do {
            try db.transaction {
                try db.execute("DELETE FROM links WHERE id=?", [link.id])
                try db.execute("DELETE FROM photos WHERE id=?", [link.photoID])
            }
        } catch {
            if let trashed { try? fm.moveItem(at: trashed as URL, to: original) }
            throw error
        }
        try? fm.removeItem(at: root.appendingPathComponent("thumbnails/\(link.photoID).jpg"))
    }
    public func thumbnail(for photo: Photo) throws -> URL {
        let target = root.appendingPathComponent("thumbnails/\(photo.id).jpg")
        if !fm.fileExists(atPath: target.path) { try Imaging.thumbnail(try safeURL(photo.relativePath), to: target) }
        return target
    }
    private func safeURL(_ relative: String) throws -> URL {
        try Self.safeURL(relative, root: root)
    }
    private static func safeURL(_ relative: String, root: URL) throws -> URL {
        guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw FrameError("资料库包含非法路径") }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw FrameError("资料库文件路径越界") }
        return url
    }
    public func backup(to destination: URL) throws {
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !destination.path.hasPrefix(root.path + "/"), destination != root else { throw FrameError("备份不能放在当前资料库内部") }
        guard !fm.fileExists(atPath: destination.path) else { throw FrameError("备份目标已存在，请使用新名称") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".FujiFrame-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try db.verify()
            var files = [String: String]()
            let photos = try db.all("photos", as: Photo.self)
            let paths = ["library.sqlite"] + photos.map(\.relativePath)
            for path in paths {
                let source = try safeURL(path)
                let target = try Self.safeURL(path, root: staging)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                files[path] = try Imaging.hash(target)
                if let photo = photos.first(where: { $0.relativePath == path }), files[path] != photo.id { throw FrameError("原图损坏：\(path)") }
            }
            let manifest = Manifest(format: 1, created: Date(), files: files)
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try fm.moveItem(at: staging, to: destination)
        } catch { try? fm.removeItem(at: staging); throw error }
    }
    public static func restore(from backup: URL, to destination: URL) throws {
        let fm = FileManager.default
        let backup = backup.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !fm.fileExists(atPath: destination.path), !destination.path.hasPrefix(backup.path + "/") else { throw FrameError("请选择备份之外的新文件夹名称；恢复不会覆盖已有目录") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: backup.appendingPathComponent("manifest.json")))
        guard manifest.format == 1, manifest.files["library.sqlite"] != nil else { throw FrameError("不支持或不完整的备份") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".FujiFrame-restore-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for (path, expected) in manifest.files {
                guard path == "library.sqlite" || path.hasPrefix("originals/") else { throw FrameError("无效的备份文件清单") }
                let source = try safeURL(path, root: backup)
                let target = try safeURL(path, root: staging)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                guard try Imaging.hash(target) == expected else { throw FrameError("备份校验失败：\(path)") }
            }
            try validateRestore(staging, manifest: manifest)
            try fm.moveItem(at: staging, to: destination)
        } catch { try? fm.removeItem(at: staging); throw error }
    }
    private static func validateRestore(_ root: URL, manifest: Manifest) throws {
        let database = try Database(root.appendingPathComponent("library.sqlite"), create: false)
        try database.verify()
        let recipes = try database.all("recipes", as: Recipe.self)
        let versions = try database.all("versions", as: RecipeVersion.self)
        let photos = try database.all("photos", as: Photo.self)
        let links = try database.all("links", as: PhotoLink.self)
        for version in versions {
            guard recipes.contains(where: { $0.id == version.recipeID }) else { throw FrameError("备份的配方版本关联缺失") }
            try XT5.validate(version.parameters)
        }
        for photo in photos {
            guard photo.relativePath == "originals/\(photo.id).jpg", manifest.files[photo.relativePath] == photo.id else { throw FrameError("备份缺少原图或原图内容不符") }
        }
        for link in links {
            guard photos.contains(where: { $0.id == link.photoID }), versions.contains(where: { $0.id == link.versionID }) else { throw FrameError("备份照片关联不完整") }
        }
    }
}
