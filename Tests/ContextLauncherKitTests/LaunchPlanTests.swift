import Foundation
import XCTest
@testable import ContextLauncherKit

final class LaunchPlanTests: XCTestCase {
    private final class RecordingProcessRunner: ProcessRunning {
        struct Call: Equatable {
            let executable: URL
            let arguments: [String]
        }

        var calls: [Call] = []
        var failures = Set<URL>()

        func run(executable: URL, arguments: [String]) throws {
            calls.append(Call(executable: executable, arguments: arguments))
            if failures.contains(executable) {
                throw CocoaError(.executableNotLoadable)
            }
        }
    }

    private final class RecordingApplicationOpener: ApplicationOpening {
        var openedURLs: [URL] = []
        var failures = Set<URL>()

        func openApplication(at url: URL) throws -> NSRunningApplication? {
            openedURLs.append(url)
            if failures.contains(url) {
                throw CocoaError(.fileNoSuchFile)
            }
            return nil
        }
    }

    private final class FailingChromeWindowTargeter: ChromeWindowTargeting {
        func open(urls: [URL], inProfile profileID: String) throws -> Bool {
            throw CocoaError(.executableNotLoadable)
        }
    }

    private final class RecordingScriptRunner: JavaScriptRunning {
        var calls: [(String, [String])] = []
        var output = "not-targeted"

        func run(script: String, arguments: [String]) throws -> String {
            calls.append((script, arguments))
            return output
        }
    }

    private let fixtureChromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    private let fixtureCodeURL = URL(fileURLWithPath: "/tmp/code")

    func testPlanKeepsArgumentsStructuredAndProjectsSeparate() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectWithSpace = directory.appendingPathComponent("backend one")
        let secondProject = directory.appendingPathComponent("frontend")
        try FileManager.default.createDirectory(at: projectWithSpace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)
        let context = LauncherContext(
            id: "work",
            name: "Work",
            chromeProfileID: "Profile 2",
            urls: [URL(string: "https://example.test/a?b=c")!],
            vscodeProjects: [projectWithSpace, secondProject]
        )

        let plan = LaunchPlanner.plan(for: context, environment: fixtureEnvironment)

        XCTAssertEqual(plan.actions.filter { if case .vscode = $0 { true } else { false } }.count, 2)
        XCTAssertTrue(plan.actions.contains(.vscode(executable: fixtureCodeURL, arguments: ["--new-window", projectWithSpace.path])))
        XCTAssertEqual(plan.actions.first, .chrome(executable: fixtureChromeURL, profileID: "Profile 2", urls: [URL(string: "https://example.test/a?b=c")!]))
    }

    func testMissingItemsBecomeWarningsWithoutRemovingValidActions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingProject = directory.appendingPathComponent("existing")
        let missingProject = directory.appendingPathComponent("missing")
        try FileManager.default.createDirectory(at: existingProject, withIntermediateDirectories: true)
        let context = LauncherContext(id: "work", name: "Work", vscodeProjects: [missingProject, existingProject])
        let environment = LaunchEnvironment(vscodeInstallation: VSCodeInstallation(executableURL: fixtureCodeURL, usesShellCommand: true))

        let plan = LaunchPlanner.plan(for: context, environment: environment)

        XCTAssertEqual(plan.actions, [.vscode(executable: fixtureCodeURL, arguments: ["--new-window", existingProject.path])])
        XCTAssertEqual(plan.warnings.count, 1)
    }

    func testUnavailableVSCodeDoesNotPreventApplicationPlanning() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("project")
        let application = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        let context = LauncherContext(id: "work", name: "Work", vscodeProjects: [project], applications: [application])

        let plan = LaunchPlanner.plan(for: context, environment: LaunchEnvironment())

        XCTAssertEqual(plan.actions, [.application(application.standardizedFileURL)])
        XCTAssertEqual(plan.warnings.count, 1)
    }

    func testLaunchContinuesAfterFailuresAndKeepsProcessArgumentsLiteral() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("project with spaces")
        let application = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        let context = LauncherContext(
            id: "work",
            name: "Work",
            chromeProfileID: "Profile 2",
            urls: [URL(string: "https://example.test/a?b=c")!],
            vscodeProjects: [project],
            applications: [application]
        )
        let processRunner = RecordingProcessRunner()
        processRunner.failures = [URL(fileURLWithPath: "/usr/bin/open")]
        let applicationOpener = RecordingApplicationOpener()
        applicationOpener.failures = [application.standardizedFileURL]
        let launcher = ContextLauncher(
            environment: fixtureEnvironment,
            processRunner: processRunner,
            applicationOpener: applicationOpener
        )

        let result = launcher.launch(context)

        XCTAssertEqual(processRunner.calls, [
            .init(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-na", fixtureChromeURL.path, "--args", "--profile-directory=Profile 2", "https://example.test/a?b=c"]),
            .init(executable: fixtureCodeURL, arguments: ["--new-window", project.path])
        ])
        XCTAssertEqual(applicationOpener.openedURLs, [application.standardizedFileURL])
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testNilApplicationLaunchResultsBecomeWarningsAndLaterApplicationsStillRun() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstApplication = directory.appendingPathComponent("First.app")
        let secondApplication = directory.appendingPathComponent("Second.app")
        try FileManager.default.createDirectory(at: firstApplication, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondApplication, withIntermediateDirectories: true)
        let applicationOpener = RecordingApplicationOpener()
        let launcher = ContextLauncher(environment: LaunchEnvironment(), applicationOpener: applicationOpener)
        let context = LauncherContext(id: "work", name: "Work", applications: [firstApplication, secondApplication])

        let result = launcher.launch(context)

        XCTAssertEqual(applicationOpener.openedURLs, [firstApplication.standardizedFileURL, secondApplication.standardizedFileURL])
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testFailedChromeWindowTargetingFallsBackToStructuredOpenCommand() {
        let runner = RecordingProcessRunner()
        let launcher = ContextLauncher(
            environment: fixtureEnvironment,
            processRunner: runner,
            applicationOpener: RecordingApplicationOpener(),
            chromeWindowTargeter: FailingChromeWindowTargeter()
        )
        let context = LauncherContext(
            id: "work",
            name: "Work",
            chromeProfileID: "Profile 2",
            urls: [URL(string: "https://example.test/a?b=c")!]
        )

        _ = launcher.launch(context)

        XCTAssertEqual(runner.calls, [
            .init(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-na", fixtureChromeURL.path, "--args", "--profile-directory=Profile 2", "https://example.test/a?b=c"])
        ])
    }

    func testProfileWithoutURLsStillPlansAChromeFocusOrLaunch() {
        let context = LauncherContext(id: "work", name: "Work", chromeProfileID: "Profile 2")

        let plan = LaunchPlanner.plan(for: context, environment: fixtureEnvironment)

        XCTAssertEqual(plan.actions, [
            .chrome(executable: fixtureChromeURL, profileID: "Profile 2", urls: [])
        ])
    }

    func testProductionChromeTargeterUsesDiscoveredProfileNameAndStructuredArguments() throws {
        let runner = RecordingScriptRunner()
        runner.output = "targeted\n"
        let targeter = ChromeAppleScriptWindowTargeter(
            profiles: [ChromeProfile(directoryID: "Profile 2", name: "Work")],
            runner: runner
        )
        let urls = [URL(string: "https://example.test/a?b=c")!]

        XCTAssertTrue(try targeter.open(urls: urls, inProfile: "Profile 2"))
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].1, ["Work", "https://example.test/a?b=c"])
        XCTAssertFalse(runner.calls[0].0.contains("Profile 2"))
    }

    func testProductionChromeTargeterDeclinesUnknownOrAmbiguousProfiles() throws {
        let runner = RecordingScriptRunner()
        let targeter = ChromeAppleScriptWindowTargeter(
            profiles: [
                ChromeProfile(directoryID: "Profile 2", name: "Same"),
                ChromeProfile(directoryID: "Profile 3", name: "Same")
            ],
            runner: runner
        )

        XCTAssertFalse(try targeter.open(urls: [], inProfile: "Missing"))
        XCTAssertFalse(try targeter.open(urls: [], inProfile: "Profile 2"))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testOsaScriptRunnerExecutesJavaScriptAndReportsFailure() throws {
        let runner = OsaScriptRunner()

        XCTAssertEqual(
            try runner.run(script: "function run(argv) { return argv.join('|'); }", arguments: ["one", "two words"]),
            "one|two words\n"
        )
        XCTAssertEqual(
            try runner.run(script: ChromeAppleScriptWindowTargeter.script, arguments: []),
            "not-targeted\n"
        )
        XCTAssertThrowsError(try runner.run(script: "function run() { throw new Error('failure'); }", arguments: []))
    }

    func testProcessRunnerWaitsAndReportsNonzeroExitStatus() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("finished")
        let runner = ProcessRunner()

        try runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf done > \"$1\"", "sh", marker.path])
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "done")
        XCTAssertThrowsError(try runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 7"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("status 7"))
            XCTAssertTrue(error.localizedDescription.contains("/bin/sh"))
        }
    }

    func testPlannerSkipsExistingResourcesWithInvalidShapes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectFile = directory.appendingPathComponent("plain.txt")
        let applicationFile = directory.appendingPathComponent("Fake.app")
        try Data().write(to: projectFile)
        try Data().write(to: applicationFile)
        let context = LauncherContext(
            id: "invalid",
            name: "Invalid",
            vscodeProjects: [projectFile],
            applications: [applicationFile]
        )

        let plan = LaunchPlanner.plan(for: context, environment: fixtureEnvironment)

        XCTAssertTrue(plan.actions.isEmpty)
        XCTAssertEqual(plan.warnings.count, 2)
        XCTAssertTrue(plan.warnings.allSatisfy { $0.contains("not a") })
    }

    private var fixtureEnvironment: LaunchEnvironment {
        LaunchEnvironment(
            chromeApplicationURL: fixtureChromeURL,
            vscodeInstallation: VSCodeInstallation(executableURL: fixtureCodeURL, usesShellCommand: true)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
