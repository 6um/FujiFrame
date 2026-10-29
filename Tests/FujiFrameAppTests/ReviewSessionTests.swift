import XCTest
import FujiFrameTestSupport
import ImageIO
import UniformTypeIdentifiers
@testable import FujiFrame
import FujiFrameCore

@MainActor final class ReviewSessionTests: XCTestCase {
    func fixture(_ root: URL, name: String, red: CGFloat) throws -> URL {
        let url = root.appendingPathComponent(name)
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red:red,green:0.5,blue:0.3,alpha:1)); context.fill(CGRect(x:0,y:0,width:20,height:20))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,context.makeImage()!,nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest)); return url
    }
    func environment() async throws -> (URL, PhotoLibrary, Recipe, RecipeVersion, RecipeVersion) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FujiFrame-session-test-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let library = try PhotoLibrary(root:root.appendingPathComponent("Library"),create:true)
        let recipe = Recipe(name:"Review tests")
        let v1 = try await library.saveRecipe(recipe,parameters:["film":"ACROS"],firmware:"",exposureAdvice:"",note:"")
        let v2 = try await library.saveRecipe(recipe,parameters:["film":"CLASSIC CHROME"],firmware:"",exposureAdvice:"",note:"")
        return (root,library,recipe,v1,v2)
    }
    func until(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertTrue(condition(),"Session timed out")
    }
    func testMultiAssignmentExcludeRestoreAndCommit() async throws {
        let (root,lib,r,v1,v2) = try await environment()
        defer { try? FileManager.default.removeItem(at:root) }
        let urls = try (1...3).map { try fixture(root,name:"\($0).jpg",red:Double($0)/4) }
        let session = try ImportReviewController(library:lib,recipes:[r],versions:[v1,v2])
        var closed = false; session.onClose = { _ in closed = true }
        session.start(urls,fixedTarget:nil)
        try await until { !session.processing }
        XCTAssertFalse(session.canConfirm); XCTAssertEqual(session.unresolvedCount,3)
        session.assign(Set(session.items.prefix(2).map(\.id)),target:v1.id)
        session.assign([session.items[1].id],target:v2.id)
        let last = session.items[2].id
        session.exclude([last],value:true); XCTAssertTrue(session.canConfirm)
        session.exclude([last],value:false); XCTAssertFalse(session.canConfirm)
        session.exclude([last],value:true)
        let before = try await lib.snapshot(); XCTAssertTrue(before.links.isEmpty)
        session.confirm(); try await until { closed }
        let after = try await lib.snapshot(); XCTAssertEqual(after.links.count,2)
        XCTAssertEqual(Set(after.links.map(\.versionID)),Set([v1.id,v2.id]))
        for item in session.items { if let preview = item.preview { XCTAssertFalse(FileManager.default.fileExists(atPath:preview.path)) } }
        for url in urls { XCTAssertTrue(FileManager.default.fileExists(atPath:url.path)) }
    }
    func testCancelAnalysisDoesNotWriteLibrary() async throws {
        let (root,lib,r,v1,v2) = try await environment(); defer { try? FileManager.default.removeItem(at:root) }
        let url = try fixture(root,name:"cancel.jpg",red:0.1)
        let session = try ImportReviewController(library:lib,recipes:[r],versions:[v1,v2])
        var closed = false; session.onClose = { _ in closed = true }
        session.start([url],fixedTarget:v1.id); session.cancel()
        try await until { closed }
        let snapshot = try await lib.snapshot(); XCTAssertTrue(snapshot.links.isEmpty)
    }
    func testPartialFailurePreservesChoiceAndCanRetry() async throws {
        let (root,lib,r,v1,v2) = try await environment(); defer { try? FileManager.default.removeItem(at:root) }
        let a = try fixture(root,name:"a.jpg",red:0.1), b = try fixture(root,name:"b.jpg",red:0.2)
        let session = try ImportReviewController(library:lib,recipes:[r],versions:[v1,v2])
        var closed = false; session.onClose = { _ in closed = true }
        session.start([a,b],fixedTarget:v2.id); try await until { !session.processing }
        _ = try fixture(root,name:"b.jpg",red:0.9)
        session.confirm(); try await until { !session.committing }
        XCTAssertFalse(closed); XCTAssertTrue(session.items[0].completed)
        XCTAssertNotNil(session.items[1].importError); XCTAssertEqual(session.items[1].targetVersionID,v2.id)
        let partial = try await lib.snapshot(); XCTAssertEqual(partial.links.count,1)
        session.reanalyze([session.items[1].id]); try await until { !session.processing }
        XCTAssertEqual(session.items[1].targetVersionID,v2.id)
        session.confirm(); try await until { closed }
        let final = try await lib.snapshot(); XCTAssertEqual(final.links.count,2)
    }
    func testAutomaticMultiRecipeReviewEndToEnd() async throws {
        let (root, lib, existing, old, latest) = try await environment()
        defer { try? FileManager.default.removeItem(at:root) }
        let a = Recipe(name:"Daylight"), b = Recipe(name:"ACROS")
        let common = ["wb":"日光","wbR":"2","wbB":"-3"]
        let va = try await lib.saveRecipe(a,parameters:common.merging(["film":"CLASSIC CHROME"]){ _,new in new },firmware:"",exposureAdvice:"",note:"")
        let vb = try await lib.saveRecipe(b,parameters:common.merging(["film":"ACROS + R"]){ _,new in new },firmware:"",exposureAdvice:"",note:"")
        let urls = try (1...4).map { try fixture(root,name:"auto\($0).jpg",red:Double($0)/5) }
        try FujiFixture.inject(FujiFixture.daylight,into:urls[0])
        var mono = FujiFixture.daylight; mono[0x1003] = [0x501]
        try FujiFixture.inject(mono,into:urls[1])
        let session = try ImportReviewController(library:lib,recipes:[a,b,existing],versions:[old,latest,va,vb])
        var closed = false; session.onClose = { _ in closed = true }
        session.start(urls,fixedTarget:nil); try await until { !session.processing }
        XCTAssertEqual(session.items[0].targetVersionID,va.id)
        XCTAssertEqual(session.items[1].targetVersionID,vb.id)
        XCTAssertNil(session.items[2].targetVersionID)
        XCTAssertEqual(session.readyCount,2); XCTAssertFalse(session.canConfirm)
        session.assign([session.items[2].id],target:old.id)
        session.exclude([session.items[3].id],value:true)
        XCTAssertTrue(session.canConfirm)
        let before = try await lib.snapshot(); XCTAssertTrue(before.photos.isEmpty)
        session.confirm(); try await until { closed }
        let after = try await lib.snapshot()
        XCTAssertEqual(after.photos.count,3)
        XCTAssertEqual(Set(after.links.map(\.versionID)),Set([va.id,vb.id,old.id]))
        XCTAssertEqual(after.versions.first { $0.id == old.id }?.parameters,old.parameters)
        XCTAssertEqual(after.versions.count,4)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:lib.root.appendingPathComponent("originals").path).count,3)
        XCTAssertTrue(FileManager.default.fileExists(atPath:urls[3].path))
    }

}
