import Foundation
import XCTest
@testable import ContextLauncherApp
@testable import ContextLauncherKit

@MainActor
final class AppModelTests: XCTestCase {
    private struct ExpectedFailure: Error {}

    func testMalformedConfigurationBlocksSaveAndPreservesStoredBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("{ malformed".utf8)
        try original.write(to: fixture.contextsURL)
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in }

        XCTAssertFalse(model.allowsStorageMutations)

        await model.save(LauncherContext(id: "work", name: "Work"))

        XCTAssertEqual(try Data(contentsOf: fixture.contextsURL), original)
    }

    func testFailedLauncherSyncKeepsOnboardingActiveAndCompletionHidden() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in
            throw ExpectedFailure()
        }

        XCTAssertTrue(model.needsOnboarding)

        await model.completeOnboarding()

        XCTAssertTrue(model.needsOnboarding)
        XCTAssertFalse(model.showsOnboardingCompletion)
        XCTAssertFalse(model.isSynchronizingLaunchers)
    }
}

private struct Fixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("support", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    var contextsURL: URL {
        directory.appendingPathComponent("support/contexts.json")
    }

    var environment: [String: String] {
        [
            "CONTEXT_LAUNCHER_HOME": directory.appendingPathComponent("support").path,
            "INSTALL_ROOT": directory.appendingPathComponent("launchers").path,
            "PATH": ""
        ]
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
