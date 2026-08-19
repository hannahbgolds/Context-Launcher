import Foundation
import XCTest
@testable import ContextLauncherKit

final class ContextLauncherRouteTests: XCTestCase {
    func testNewAndEditRoutesRoundTripThroughApplicationURLs() throws {
        let newURL = try XCTUnwrap(ContextLauncherRoute.new.url)
        let editURL = try XCTUnwrap(ContextLauncherRoute.edit("daily-work").url)

        XCTAssertEqual(newURL.absoluteString, "contextlauncher://new")
        XCTAssertEqual(editURL.absoluteString, "contextlauncher://edit/daily-work")
        XCTAssertEqual(ContextLauncherRoute(url: newURL), .new)
        XCTAssertEqual(ContextLauncherRoute(url: editURL), .edit("daily-work"))
    }

    func testRouteParserRejectsInvalidIDsAndExtraURLComponents() {
        XCTAssertNil(ContextLauncherRoute(url: URL(string: "contextlauncher://edit/UPPER")!))
        XCTAssertNil(ContextLauncherRoute(url: URL(string: "contextlauncher://edit/good/extra")!))
        XCTAssertNil(ContextLauncherRoute(url: URL(string: "contextlauncher://new?unexpected=1")!))
        XCTAssertNil(ContextLauncherRoute.edit("../bad").url)
        XCTAssertNil(ContextLauncherRoute(url: URL(string: "https://edit/work")!))
    }
}
