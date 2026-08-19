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

    func testPendingSetupSurvivesRestartUntilSuccessfulLauncherRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in
            throw ExpectedFailure()
        }
        model.starterContexts[0].name = "Customized Uni"

        XCTAssertTrue(model.needsOnboarding)

        await model.completeOnboarding()

        XCTAssertTrue(model.needsOnboarding)
        XCTAssertFalse(model.showsOnboardingCompletion)
        XCTAssertFalse(model.isSynchronizingLaunchers)
        XCTAssertEqual(try Data(contentsOf: fixture.setupPendingURL), Data())

        let resumed = AppModel(arguments: [], environment: fixture.environment) { _, _ in }
        XCTAssertTrue(resumed.needsOnboarding)
        XCTAssertFalse(resumed.showsOnboardingCompletion)
        XCTAssertEqual(resumed.starterContexts.first(where: { $0.id == "uni" })?.name, "Customized Uni")

        await resumed.completeOnboarding()

        XCTAssertFalse(resumed.needsOnboarding)
        XCTAssertTrue(resumed.showsOnboardingCompletion)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.setupPendingURL.path))

        let finished = AppModel(arguments: [], environment: fixture.environment) { _, _ in }
        XCTAssertFalse(finished.needsOnboarding)
        XCTAssertFalse(finished.showsOnboardingCompletion)
    }

    func testSavingURLsWithoutAChromeProfileIsRejectedByTheModelAndStore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in }
        let context = LauncherContext(
            id: "web",
            name: "Web",
            urls: [URL(string: "https://example.com")!]
        )

        await model.save(context)

        XCTAssertTrue(model.contexts.isEmpty)
        XCTAssertTrue(model.alert?.message.contains("Chrome profile") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.contextsURL.path))
    }

    func testInstallerInitializedStarterDataKeepsOnboardingActive() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ContextStore(fileURL: fixture.contextsURL).save(StarterContexts.all)
        try Data().write(to: fixture.setupPendingURL, options: .atomic)

        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in }

        XCTAssertTrue(model.needsOnboarding)
        XCTAssertEqual(model.starterContexts.map(\.id), StarterContexts.all.map(\.id).sorted())
        XCTAssertFalse(model.canUseGlobalActions)
    }

    func testApplicationURLRoutesUpdateTheExistingModelWithoutBypassingOnboarding() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ContextStore(fileURL: fixture.contextsURL).save([
            LauncherContext(id: "first", name: "First"),
            LauncherContext(id: "second", name: "Second")
        ])
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in }

        model.handle(url: URL(string: "contextlauncher://edit/second")!)
        XCTAssertEqual(model.draft?.id, "second")

        model.handle(url: URL(string: "contextlauncher://new")!)
        XCTAssertEqual(model.draft?.name, "New Context")

        model.handle(url: URL(string: "contextlauncher://edit/UPPER")!)
        XCTAssertTrue(model.alert?.message.contains("contextlauncher") == true)
    }

    func testManualSyncFailureRefreshesDiagnostics() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ContextStore(fileURL: fixture.contextsURL).save([LauncherContext(id: "work", name: "Work")])
        let model = AppModel(arguments: [], environment: fixture.environment) { _, _ in
            throw ExpectedFailure()
        }
        XCTAssertTrue(model.diagnostics.contains { $0.code == "launcher.missing" })
        try makeLauncher(
            at: fixture.directory.appendingPathComponent("launchers/Work.app"),
            identifier: "dev.contextlauncher.context.work"
        )

        await model.synchronizeLaunchers()

        XCTAssertTrue(model.diagnostics.contains { $0.code == "launcher.valid" })
    }

    func testSaveReportsLauncherCollisionAndPreservesGuiDestinationDecoy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let decoy = fixture.directory.appendingPathComponent("launchers/Work.app")
        try makeLauncher(at: decoy, identifier: "com.example.unrelated")
        try Data("decoy".utf8).write(to: decoy.appendingPathComponent("marker"))
        let cliURL = fixture.directory.appendingPathComponent("support/bin/context")
        let launcherRoot = fixture.directory.appendingPathComponent("launchers")
        let model = AppModel(arguments: [], environment: fixture.environment) { contexts, _ in
            let generator = LauncherBundleGenerator()
            for context in contexts {
                try generator.generate(for: context, among: contexts, cliURL: cliURL, in: launcherRoot)
            }
        }

        await model.save(LauncherContext(id: "work", name: "Work"))

        XCTAssertEqual(try String(contentsOf: decoy.appendingPathComponent("marker"), encoding: .utf8), "decoy")
        XCTAssertTrue(model.alert?.title.contains("launcher needs attention") == true)
    }

    private func makeLauncher(at bundle: URL, identifier: String) throws {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/launcher")
        let icon = contents.appendingPathComponent("Resources/AppIcon.icns")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try Data().write(to: icon)
        let plist = ["CFBundleIdentifier": identifier]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
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

    var setupPendingURL: URL {
        directory.appendingPathComponent("support/setup-pending")
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
