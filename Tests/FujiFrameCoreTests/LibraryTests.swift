import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import FujiFrameCore

final class LibraryTests: XCTestCase {
    var workspace: URL!
    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("FujiFrame-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: workspace) }
    func makeLibrary(_ name: String = "Library") throws -> PhotoLibrary { try PhotoLibrary(root: workspace.appendingPathComponent(name), create: true) }
    func fixture(_ name: String = "DSCF0001.JPG", metadata: Bool = true, orientation: Int = 1, red: CGFloat = 0.3) throws -> URL {
        let url = workspace.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: 0.55, blue: 0.62, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 80, y: 80, width: 170, height: 160))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if metadata {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifExposureTime: 1.0 / 250, kCGImagePropertyExifISOSpeedRatings: [400], kCGImagePropertyExifExposureBiasValue: -0.67, kCGImagePropertyExifFocalLength: 35, kCGImagePropertyExifLensModel: "XF35mmF1.4 R", kCGImagePropertyExifDateTimeOriginal: "2026:10:28 16:30:00"] as [CFString: Any]
            props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFModel: "X-T5"]
        }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
    func version(_ library: PhotoLibrary, recipe: Recipe = Recipe(name: "日光配方"), params: [String: String] = ["film": "CLASSIC CHROME"]) async throws -> RecipeVersion {
        try await library.saveRecipe(recipe, parameters: params, firmware: "", exposureAdvice: "", note: "")
    }
    func testVersionHistoryAndMetadataOnlyEdit() async throws {
        let lib = try makeLibrary(); var recipe = Recipe(name: "日光")
        let v1 = try await version(lib, recipe: recipe)
        let original = try fixture()
        let result = await lib.importPhoto(original, versionID: v1.id); XCTAssertFalse(result.failed)
        recipe.name = "晴天"; recipe.summary = "日间街拍"
        let renamed = try await version(lib, recipe: recipe); XCTAssertEqual(renamed.id, v1.id)
        let v2 = try await version(lib, recipe: recipe, params: ["film": "CLASSIC Neg."])
        XCTAssertEqual(v2.number, 2)
        let snapshot = try await lib.snapshot()
        XCTAssertEqual(snapshot.versions.count, 2); XCTAssertEqual(snapshot.links.first?.versionID, v1.id)
        XCTAssertEqual(snapshot.versions.first { $0.id == v1.id }?.parameters["film"], "CLASSIC CHROME")
        try await lib.archive(recipe)
        let archived = try await lib.snapshot(); XCTAssertTrue(archived.recipes[0].archived)
        let database = try Database(lib.root.appendingPathComponent("library.sqlite"), create: false)
        XCTAssertThrowsError(try database.execute("UPDATE versions SET number=99"))
    }
    func testRecipeNotesPersistAndLegacyRecipesDecode() async throws {
        let legacy = Data(#"{"id":"old","name":"旧配方","summary":"","source":"","archived":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Recipe.self, from: legacy).notes)
        let lib = try makeLibrary(); var recipe = Recipe(name: "配方")
        let original = try await version(lib, recipe: recipe)
        recipe.notes = "第一行\n第二行"
        let updated = try await version(lib, recipe: recipe)
        let snapshot = try await lib.snapshot()
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(snapshot.recipes.first?.notes, recipe.notes)
    }
    func testDeduplicationCrossVersionAndMoveMerge() async throws {
        let lib = try makeLibrary(); let recipe = Recipe(name: "配方")
        let v1 = try await version(lib, recipe: recipe)
        let v2 = try await version(lib, recipe: recipe, params: ["film": "ACROS"])
        let original = try fixture()
        let first = await lib.importPhoto(original, versionID: v1.id)
        let duplicate = await lib.importPhoto(original, versionID: v1.id)
        XCTAssertFalse(first.failed); XCTAssertTrue(duplicate.message.contains("跳过"))
        let cross = await lib.importPhoto(original, versionID: v2.id); XCTAssertFalse(cross.failed)
        var snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.photos.count, 1); XCTAssertEqual(snapshot.links.count, 2)
        try await lib.moveLink(snapshot.links.first { $0.versionID == v1.id }!, to: v2.id)
        snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.links.count, 1)
        try await lib.moveLink(snapshot.links[0], to: v1.id)
        snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.links[0].versionID, v1.id)
        let database = try Database(lib.root.appendingPathComponent("library.sqlite"), create: false)
        XCTAssertEqual(try database.query("SELECT id FROM links")[0]["id"], snapshot.links[0].id)
        XCTAssertEqual(try Imaging.hash(original), snapshot.photos[0].id)
    }
    func testMetadataAndRotatedThumbnail() throws {
        let original = try fixture(orientation: 6)
        let metadata = try Imaging.inspect(original)
        XCTAssertEqual(metadata.aperture, 2.8); XCTAssertEqual(metadata.iso, 400)
        XCTAssertEqual(metadata.camera, "X-T5"); XCTAssertEqual(metadata.shutterText, "1/250 s")
        XCTAssertEqual(metadata.lens, "XF35mmF1.4 R"); XCTAssertEqual(metadata.orientation, 6)
        let thumb = workspace.appendingPathComponent("thumb.jpg"); try Imaging.thumbnail(original, to: thumb)
        let thumbnail = try Imaging.inspect(thumb)
        XCTAssertLessThan(thumbnail.width!, thumbnail.height!)
        var long = PhotoMetadata(); long.exposure = 30; XCTAssertEqual(long.shutterText, "30 s")
        long.exposure = 0; XCTAssertEqual(long.shutterText, "未记录")
        let noExif = try Imaging.inspect(fixture("no-exif.jpg", metadata: false))
        XCTAssertNil(noExif.aperture); XCTAssertNil(noExif.camera); XCTAssertEqual(noExif.shutterText, "未记录")
    }
    func testBadFilesDoNotAffectSuccessfulImports() async throws {
        let lib = try makeLibrary(); let v = try await version(lib)
        let broken = workspace.appendingPathComponent("broken.jpg"); try Data("invalid jpeg".utf8).write(to: broken)
        let failed = await lib.importPhoto(broken, versionID: v.id); XCTAssertTrue(failed.failed)
        let missing = await lib.importPhoto(workspace.appendingPathComponent("missing.jpg"), versionID: v.id); XCTAssertTrue(missing.failed)
        let success = await lib.importPhoto(try fixture(), versionID: v.id); XCTAssertFalse(success.failed)
        let snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.photos.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: lib.root.appendingPathComponent(".staging").path).count, 0)
        let invalidVersion = await lib.importPhoto(try fixture("other.jpg"), versionID: "missing"); XCTAssertTrue(invalidVersion.failed)
    }
    func testSameFilenameDifferentContents() async throws {
        let lib = try makeLibrary(); let v = try await version(lib)
        let first = await lib.importPhoto(try fixture(red: 0.1), versionID: v.id)
        let second = await lib.importPhoto(try fixture(red: 0.8), versionID: v.id)
        XCTAssertFalse(first.failed); XCTAssertFalse(second.failed)
        let snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.photos.count, 2); XCTAssertEqual(snapshot.links.count, 2)
    }
    func testBackupRestoreAndThumbnailRebuild() async throws {
        let lib = try makeLibrary(); let recipe = Recipe(name: "备份验证")
        let v1 = try await version(lib, recipe: recipe)
        _ = try await version(lib, recipe: recipe, params: ["film": "ACROS"])
        let input = try fixture(); _ = await lib.importPhoto(input, versionID: v1.id)
        let backup = workspace.appendingPathComponent("Backup"); try await lib.backup(to: backup)
        let restoredRoot = workspace.appendingPathComponent("Restored")
        try PhotoLibrary.restore(from: backup, to: restoredRoot)
        let restored = try PhotoLibrary(root: restoredRoot)
        let snapshot = try await restored.snapshot()
        XCTAssertEqual(snapshot.recipes.first?.name, "备份验证"); XCTAssertEqual(snapshot.versions.count, 2)
        XCTAssertEqual(snapshot.links.first?.versionID, v1.id)
        XCTAssertEqual(try Imaging.hash(restoredRoot.appendingPathComponent(snapshot.photos[0].relativePath)), try Imaging.hash(input))
        let thumbnail = try await restored.thumbnail(for: snapshot.photos[0]); XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnail.path))
        XCTAssertThrowsError(try PhotoLibrary.restore(from: backup, to: restoredRoot))
        let extra = try await lib.snapshot(); XCTAssertEqual(extra.photos.count, 1)
    }
    func testCorruptBackupIsRejectedWithoutDestination() async throws {
        let lib = try makeLibrary(); let v = try await version(lib)
        _ = await lib.importPhoto(try fixture(), versionID: v.id)
        let snapshot = try await lib.snapshot()
        let backup = workspace.appendingPathComponent("Backup"); try await lib.backup(to: backup)
        try Data("corrupted".utf8).write(to: backup.appendingPathComponent(snapshot.photos[0].relativePath))
        let destination = workspace.appendingPathComponent("Rejected")
        XCTAssertThrowsError(try PhotoLibrary.restore(from: backup, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
    func testLockRecoveryAndMovedLibrary() async throws {
        let root = workspace.appendingPathComponent("Library")
        var lib: PhotoLibrary? = try PhotoLibrary(root: root, create: true)
        let v = try await version(lib!)
        _ = await lib!.importPhoto(try fixture(), versionID: v.id)
        XCTAssertThrowsError(try PhotoLibrary(root: root))
        try Data("unfinished".utf8).write(to: root.appendingPathComponent(".staging/interrupted.jpg"))
        lib = nil
        let moved = workspace.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: root, to: moved)
        let reopened = try PhotoLibrary(root: moved)
        let snapshot = try await reopened.snapshot(); XCTAssertEqual(snapshot.links.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent(snapshot.photos[0].relativePath).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.appendingPathComponent(".staging").path).count, 0)
    }
    func testRemoveSharedLinkKeepsOriginal() async throws {
        let lib = try makeLibrary(); let recipe = Recipe(name: "共享照片")
        let v1 = try await version(lib, recipe: recipe); let v2 = try await version(lib, recipe: recipe, params: ["film": "ACROS"])
        let original = try fixture()
        _ = await lib.importPhoto(original, versionID: v1.id); _ = await lib.importPhoto(original, versionID: v2.id)
        let before = try await lib.snapshot(); try await lib.removeLink(before.links[0])
        let after = try await lib.snapshot(); XCTAssertEqual(after.links.count, 1); XCTAssertEqual(after.photos.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.root.appendingPathComponent(after.photos[0].relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }
    func testImportPermissionFailureIsIsolated() async throws {
        let lib = try makeLibrary(); let v = try await version(lib)
        let input = try fixture()
        let staging = lib.root.appendingPathComponent(".staging")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: staging.path)
        let result = await lib.importPhoto(input, versionID: v.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
        XCTAssertTrue(result.failed)
        let empty = try await lib.snapshot(); XCTAssertEqual(empty.links.count, 0)
        let retry = await lib.importPhoto(input, versionID: v.id); XCTAssertFalse(retry.failed)
    }
    func testMaliciousBackupPathRejected() async throws {
        let lib = try makeLibrary(); _ = try await version(lib)
        let backup = workspace.appendingPathComponent("Backup"); try await lib.backup(to: backup)
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        var files = manifest["files"] as! [String: String]
        files["originals/../../outside.jpg"] = "fake"
        manifest["files"] = files
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let destination = workspace.appendingPathComponent("Rejected")
        XCTAssertThrowsError(try PhotoLibrary.restore(from: backup, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
    func testMissingParametersAreNotAssumed() {
        XCTAssertEqual(XT5.displayValue("kelvin", values: [:]), "未记录")
        XCTAssertEqual(XT5.displayValue("monoWC", values: [:]), "未记录")
        XCTAssertEqual(XT5.displayValue("dr", values: ["drPriority": "AUTO"]), "由相机自动控制")
        XCTAssertEqual(XT5.displayValue("kelvin", values: ["wb": "日光"]), "不适用")
        XCTAssertEqual(XT5.displayValue("color", values: ["color": "0"]), "0")
    }
    func testValidationAndNormalization() throws {
        XCTAssertThrowsError(try XT5.validate(["color": "9"]))
        XCTAssertThrowsError(try XT5.validate(["drPriority": "STRONG", "dr": "DR100"]))
        XCTAssertEqual(XT5.normalized(["drPriority": "STRONG", "dr": "DR100", "highlights": "2", "film": ""]), ["drPriority": "STRONG"])
        XCTAssertEqual(XT5.normalized(["grain": "OFF", "grainSize": "LARGE", "wb": "AUTO", "kelvin": "5500"]), ["grain": "OFF", "wb": "AUTO"])
        XCTAssertNoThrow(try XT5.validate(["highlights": "-1.5", "clarity": "5", "film": "ACROS", "monoWC": "18"]))
    }
}
