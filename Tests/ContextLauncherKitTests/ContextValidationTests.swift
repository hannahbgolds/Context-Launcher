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

    func testValidationAcceptsValidContextAndResourceURLs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("project")
        let application = directory.appendingPathComponent("Safari.app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        let context = LauncherContext(id: "daily-practice", name: "Daily Practice", chromeProfileID: "Default", urls: [URL(string: "http://localhost:3000")!], vscodeProjects: [project], applications: [application])

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

    func testValidationRejectsASCIIControlCharactersInNameAndSubtitle() {
        let context = LauncherContext(id: "safe", name: "Safe\nvictim", subtitle: "tab\tvalue")

        let issues = ContextValidator.validate(context, among: [])

        XCTAssertTrue(issues.contains { $0.field == .name })
        XCTAssertTrue(issues.contains { $0.field == .subtitle })
        XCTAssertTrue(issues.contains { $0.message.contains("control characters") })
    }

    func testValidationRejectsURLsWithoutAChromeProfile() {
        let context = LauncherContext(
            id: "web",
            name: "Web",
            urls: [URL(string: "https://example.com")!]
        )

        let issues = ContextValidator.validate(context, among: [])

        XCTAssertTrue(issues.contains {
            $0.field == .urls && $0.message.contains("Chrome profile")
        })
    }

    func testValidationRejectsTheReservedNewLauncherID() {
        let issues = ContextValidator.validate(LauncherContext(id: "new", name: "Anything"), among: [])

        XCTAssertTrue(issues.contains { $0.field == .id && $0.message.contains("reserved") })
    }

    func testValidationChecksTheShapeOfExistingProjectsAndApplications() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let projectDirectory = directory.appendingPathComponent("project")
        let workspace = directory.appendingPathComponent("team.code-workspace")
        let invalidProject = directory.appendingPathComponent("notes.txt")
        let application = directory.appendingPathComponent("Example.app")
        let invalidApplication = directory.appendingPathComponent("Fake.app")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try Data().write(to: workspace)
        try Data().write(to: invalidProject)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        try Data().write(to: invalidApplication)

        let valid = LauncherContext(
            id: "valid",
            name: "Valid",
            vscodeProjects: [projectDirectory, workspace],
            applications: [application]
        )
        let invalid = LauncherContext(
            id: "invalid",
            name: "Invalid",
            vscodeProjects: [invalidProject],
            applications: [invalidApplication]
        )

        XCTAssertTrue(ContextValidator.validate(valid, among: []).isEmpty)
        let fields = Set(ContextValidator.validate(invalid, among: []).map(\.field))
        XCTAssertTrue(fields.contains(.vscodeProjects))
        XCTAssertTrue(fields.contains(.applications))
    }

    func testValidationAllowsMissingResourcesToBecomeLaunchWarnings() {
        let context = LauncherContext(
            id: "missing",
            name: "Missing",
            vscodeProjects: [URL(fileURLWithPath: "/path/that/does/not/exist")],
            applications: [URL(fileURLWithPath: "/Applications/Missing.app")]
        )

        XCTAssertTrue(ContextValidator.validate(context, among: []).isEmpty)
    }
}
