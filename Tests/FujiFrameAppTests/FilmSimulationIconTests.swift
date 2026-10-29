import XCTest
import AppKit
import FujiFrameCore
@testable import FujiFrame

final class FilmSimulationIconTests: XCTestCase {
    func testEveryFilmHasADistinctRenderableBundledCameraIcon() throws {
        XCTAssertEqual(Set(FilmSimulationIcons.glyphs.keys), Set(XT5.films))
        XCTAssertEqual(Set(FilmSimulationIcons.images.keys), Set(XT5.films))
        var rendered = Set<Data>()
        for film in XT5.films {
            let image = try XCTUnwrap(FilmSimulationIcons.images[film], film)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 30, height: 18))
            rendered.insert(try XCTUnwrap(image.tiffRepresentation, film))
        }
        XCTAssertEqual(rendered.count, XT5.films.count)
    }
}
