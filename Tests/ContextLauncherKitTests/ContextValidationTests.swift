import Foundation
import XCTest
@testable import ContextLauncherKit

final class ContextValidationTests: XCTestCase {
    func testRoundTripContext() throws {
        let original = LauncherContext(id: "leet", name: "Leet", subtitle: "Practice", icon: .symbol("chevron.left.forwardslash.chevron.right"), chromeProfileID: "Profile 1", urls: [URL(string: "https://leetcode.com/")!], vscodeProjects: [URL(fileURLWithPath: "/tmp/leetcode-solutions")], applications: [])

        XCTAssertEqual(try JSONDecoder().decode(LauncherContext.self, from: JSONEncoder().encode(original)), original)
    }

    func testValidationRejectsUnsafeIDInvalidURLAndDuplicateID() {
        var context = LauncherContext(id: "Leet; rm", name: "Leet")
        context.urls = [URL(string: "file:///etc/passwd")!]

        let issues = ContextValidator.validate(context, among: [LauncherContext(id: "leet", name: "Existing")])

        XCTAssertTrue(issues.contains { $0.field == .id })
        XCTAssertTrue(issues.contains { $0.field == .urls })
    }

    func testValidationAcceptsValidContextAndResourceURLs() {
        let context = LauncherContext(id: "daily-practice", name: "Daily Practice", urls: [URL(string: "http://localhost:3000")!], vscodeProjects: [URL(fileURLWithPath: "/tmp/project")], applications: [URL(fileURLWithPath: "/Applications/Safari.app")])

        XCTAssertTrue(ContextValidator.validate(context, among: []).isEmpty)
        XCTAssertEqual(URL.validatedWebURL(URL(string: "https://example.com")!), URL(string: "https://example.com"))
        XCTAssertNil(URL.validatedWebURL(URL(string: "ftp://example.com")!))
    }

    func testValidationRejectsBlankNameAndInvalidResourceURLs() {
        let context = LauncherContext(id: "valid", name: "   ", urls: [URL(string: "mailto:test@example.com")!], vscodeProjects: [URL(string: "https://example.com/project")!], applications: [URL(fileURLWithPath: "/Applications/Safari")])

        let fields = Set(ContextValidator.validate(context, among: []).map(\.field))

        XCTAssertTrue(fields.contains(.name))
        XCTAssertTrue(fields.contains(.urls))
        XCTAssertTrue(fields.contains(.vscodeProjects))
        XCTAssertTrue(fields.contains(.applications))
    }
}
