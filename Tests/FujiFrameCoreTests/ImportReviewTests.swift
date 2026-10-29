import XCTest
import FujiFrameTestSupport
@testable import FujiFrameCore

extension LibraryTests {
    func testFujiParserConvertsToneWBAndGrain() throws {
        let parsed = try FujiMetadata.parseEXIF(FujiFixture.exif(FujiFixture.daylight))
        XCTAssertEqual(parsed.values["film"], "CLASSIC CHROME")
        XCTAssertEqual(parsed.values["wb"], "日光")
        XCTAssertEqual(parsed.values["wbR"], "2"); XCTAssertEqual(parsed.values["wbB"], "-3")
        XCTAssertEqual(parsed.values["highlights"], "-1"); XCTAssertEqual(parsed.values["shadows"], "1")
        XCTAssertEqual(parsed.values["noise"], "-4"); XCTAssertEqual(parsed.values["grainSize"], "SMALL")
        XCTAssertEqual(try FujiMetadata.parseEXIF(FujiFixture.exif(FujiFixture.daylight, little: false)).values, parsed.values)
    }
    func testFujiBlackWhiteOverridesFilmMode() throws {
        var tags = FujiFixture.daylight; tags[0x1003] = [0x501]; tags[0x1049] = [-3]
        let parsed = try FujiMetadata.parseMakerNote(FujiFixture.maker(tags))
        XCTAssertEqual(parsed.values["film"], "ACROS + R"); XCTAssertEqual(parsed.values["monoWC"], "-3")
        XCTAssertNil(parsed.values["color"])
        tags[0x1003] = [0x302]
        XCTAssertEqual(try FujiMetadata.parseMakerNote(FujiFixture.maker(tags)).values["film"], "MONOCHROME + Ye")
    }
    func testFujiAutomaticSettingsAndMissingOff() {
        var tags = FujiFixture.daylight; tags[0x1402] = [0]; tags[0x1403] = [400]
        var parsed = FujiMetadata.normalize(tags)
        XCTAssertEqual(parsed.values["dr"], "AUTO"); XCTAssertNil(parsed.values["drPriority"])
        tags[0x1402] = [1]; parsed = FujiMetadata.normalize(tags); XCTAssertEqual(parsed.values["dr"], "DR400")
        tags[0x1443] = [0]; parsed = FujiMetadata.normalize(tags)
        XCTAssertEqual(parsed.values["drPriority"], "AUTO"); XCTAssertNil(parsed.values["highlights"]); XCTAssertNil(parsed.values["dr"])
        tags[0x1443] = [1]; tags[0x1445] = [2]
        XCTAssertEqual(FujiMetadata.normalize(tags).values["drPriority"], "STRONG")
    }
    func testFujiUnknownValuesStayUnknown() {
        var tags = FujiFixture.daylight; tags[0x1003] = [999]; tags[0x1002] = [0x200]; tags[0x100a] = [41,-60]; tags[0x1047] = [999]
        let values = FujiMetadata.normalize(tags).values
        XCTAssertNil(values["film"]); XCTAssertNil(values["wb"]); XCTAssertNil(values["wbR"]); XCTAssertNil(values["grain"])
        XCTAssertEqual(values["wbB"], "-3")
    }
    func testFujiMalformedOffsetsAndTruncation() throws {
        let good = FujiFixture.exif(FujiFixture.daylight)
        for length in [0,1,7,12,40,60,good.count-1] { XCTAssertThrowsError(try FujiMetadata.parseEXIF(Data(good.prefix(length)))) }
        var invalid = good; invalid.replaceSubrange(4..<8, with: [255,255,255,255])
        XCTAssertThrowsError(try FujiMetadata.parseEXIF(invalid))
        var maker = FujiFixture.maker([0x100a:[40,-60]])
        maker.replaceSubrange(22..<26, with: [255,255,255,255])
        XCTAssertThrowsError(try FujiMetadata.parseMakerNote(maker))
        XCTAssertTrue(try FujiMetadata.parseMakerNote(Data("NOTFUJI".utf8)).values.isEmpty)
    }
    func testJPEGFujiExtractionAndModelGating() throws {
        let url = try fixture(metadata: false); try FujiFixture.inject(FujiFixture.daylight, into: url)
        let metadata = try Imaging.inspect(url); XCTAssertEqual(metadata.camera, "X-T5")
        XCTAssertEqual(try FujiMetadata.read(url, camera: metadata.camera).values["film"], "CLASSIC CHROME")
        XCTAssertTrue(try FujiMetadata.read(url, camera: "X-T4").values.isEmpty)
    }
    func testStrictMatchLatestOnlyAndArchivedManualOnly() {
        let r = Recipe(name: "Daylight"); var archived = Recipe(name: "Archive"); archived.archived = true
        let settings = FujiMetadata.normalize(FujiFixture.daylight)
        let old = RecipeVersion(recipeID: r.id, number: 1, parameters: settings.values)
        var changed = settings.values; changed["wbR"] = "3"
        let latest = RecipeVersion(recipeID: r.id, number: 2, parameters: changed)
        let other = RecipeVersion(recipeID: archived.id, parameters: settings.values)
        var result = RecipeMatcher.suggest(settings, recipes: [r,archived], versions: [old,latest,other])
        XCTAssertNil(result.targetVersionID); XCTAssertEqual(result.candidates.map(\.versionID), [latest.id])
        result = RecipeMatcher.suggest(settings, recipes: [r], versions: [old])
        XCTAssertEqual(result.targetVersionID, old.id)
    }
    func testAmbiguityMissingAndInsufficientFieldsDoNotAssign() {
        let settings = FujiMetadata.normalize(FujiFixture.daylight)
        let a = Recipe(name: "A"), b = Recipe(name: "B")
        let va = RecipeVersion(recipeID: a.id, parameters: settings.values), vb = RecipeVersion(recipeID: b.id, parameters: settings.values)
        XCTAssertNil(RecipeMatcher.suggest(settings, recipes: [a,b], versions: [va,vb]).targetVersionID)
        let sparse = RecipeVersion(recipeID: a.id, parameters: ["film":"CLASSIC CHROME"])
        XCTAssertNil(RecipeMatcher.suggest(settings, recipes: [a], versions: [sparse]).targetVersionID)
        var full = settings.values; full["drPriority"] = "OFF"
        let incomplete = RecipeVersion(recipeID: a.id, parameters: full)
        let match = RecipeMatcher.compare(settings, to: incomplete)
        XCTAssertEqual(match.missing,1); XCTAssertFalse(match.strict)
    }
    func testCandidateRankingAndLimit() {
        let settings = FujiMetadata.normalize(FujiFixture.daylight)
        let recipes = (0..<5).map { Recipe(name: "Recipe \($0)") }
        let versions = recipes.enumerated().map { index, r -> RecipeVersion in
            var p = settings.values; if index != 0 { p["wbR"] = String(index + 2) }
            return RecipeVersion(recipeID: r.id, parameters: p)
        }
        let result = RecipeMatcher.suggest(settings, recipes: recipes, versions: versions)
        XCTAssertEqual(result.candidates.count,3); XCTAssertEqual(result.targetVersionID,versions[0].id)
        XCTAssertEqual(result.candidates.first?.conflicts,0)
    }
    func testReviewAssignmentExclusionAndRestore() {
        var item = ImportReviewItem(source: workspace.appendingPathComponent("test.jpg"), hash: "hash")
        XCTAssertTrue(item.needsAction)
        item.assign("chosen"); XCTAssertTrue(item.ready); XCTAssertTrue(item.manual)
        item.excluded = true; XCTAssertFalse(item.ready); XCTAssertFalse(item.needsAction)
        item.excluded = false; XCTAssertTrue(item.ready); XCTAssertEqual(item.targetVersionID,"chosen")
        item.completed = true; XCTAssertFalse(item.ready)
    }
    func testReviewAnalysisHasNoLibraryWritesAndCleansPreview() async throws {
        let lib = try makeLibrary(); let r = Recipe(name: "Daylight")
        let settings = FujiMetadata.normalize(FujiFixture.daylight)
        let v = try await version(lib, recipe: r, params: settings.values)
        let url = try fixture(metadata: false); try FujiFixture.inject(FujiFixture.daylight, into: url)
        let analyzer = try ImportAnalyzer()
        let item = try await analyzer.analyze(url, recipes: [r], versions: [v])
        XCTAssertEqual(item.targetVersionID,v.id); XCTAssertNotNil(item.hash)
        let before = try await lib.snapshot(); XCTAssertTrue(before.photos.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: lib.root.appendingPathComponent("originals").path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.preview!.path))
        await analyzer.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.preview!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testChangedSourceRejectedAndOtherFileStillImports() async throws {
        let lib = try makeLibrary(); let v = try await version(lib)
        let url = try fixture(); let oldHash = try Imaging.hash(url)
        _ = try fixture(red:0.9)
        let failed = await lib.importPhoto(url, versionID:v.id, expectedHash:oldHash)
        XCTAssertTrue(failed.failed); XCTAssertTrue(failed.message.contains("改变"))
        let empty = try await lib.snapshot(); XCTAssertTrue(empty.photos.isEmpty)
        let retry = await lib.importPhoto(url, versionID:v.id, expectedHash:try Imaging.hash(url)); XCTAssertFalse(retry.failed)
        let second = try fixture("another.jpg", red:0.1)
        let success = await lib.importPhoto(second, versionID:v.id, expectedHash:try Imaging.hash(second)); XCTAssertFalse(success.failed)
        let snapshot = try await lib.snapshot(); XCTAssertEqual(snapshot.links.count,2)
    }
    func testMalformedMakerNoteStillAllowsManualReview() async throws {
        let url = try fixture(); let analyzer = try ImportAnalyzer()
        let item = try await analyzer.analyze(url, recipes:[], versions:[], fixedTarget:"manual-version")
        XCTAssertNil(item.analysisError); XCTAssertTrue(item.settings.values.isEmpty)
        XCTAssertEqual(item.targetVersionID,"manual-version"); XCTAssertTrue(item.ready)
        await analyzer.cleanup()
    }
}
