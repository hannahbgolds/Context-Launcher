import Foundation
import XCTest
@testable import ContextLauncherKit

final class DoctorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testDoctorReportsMissingConfiguredPaths() {
        let diagnostics = Doctor.run(
            environment: fixtureEnvironment,
            contexts: [
                LauncherContext(
                    id: "work",
                    name: "Work",
                    vscodeProjects: [temporaryDirectory.appendingPathComponent("missing-project")],
                    applications: [temporaryDirectory.appendingPathComponent("Missing.app")]
                )
            ]
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "project.missing" && $0.status == .failure })
        XCTAssertTrue(diagnostics.contains { $0.code == "application.missing" && $0.status == .failure })
    }

    func testDoctorReportsConfiguredDirectories() throws {
        let configuration = temporaryDirectory.appendingPathComponent("config")
        let launchers = temporaryDirectory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchers, withIntermediateDirectories: true)

        let diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: configuration,
                launcherDirectory: launchers,
                launchEnvironment: LaunchEnvironment()
            ),
            contexts: []
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "config.directory" && $0.status == .pass })
        XCTAssertTrue(diagnostics.contains { $0.code == "launcher.directory" && $0.status == .pass })
    }

    func testDoctorReportsInvalidLauncherBundle() throws {
        let launchers = temporaryDirectory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: launchers.appendingPathComponent("Work.app"), withIntermediateDirectories: true)

        let diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: temporaryDirectory.appendingPathComponent("config"),
                launcherDirectory: launchers,
                launchEnvironment: LaunchEnvironment()
            ),
            contexts: [LauncherContext(id: "work", name: "Work")]
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "launcher.invalid" && $0.status == .failure })
    }

    func testDoctorReportsChromeProfilesAndMissingConfiguredProfile() throws {
        let localStateURL = temporaryDirectory.appendingPathComponent("Local State")
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"}}}}"#.utf8).write(to: localStateURL)
        let diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: temporaryDirectory.appendingPathComponent("config"),
                launcherDirectory: temporaryDirectory.appendingPathComponent("Applications"),
                launchEnvironment: LaunchEnvironment(),
                chromeLocalStateURL: localStateURL
            ),
            contexts: [LauncherContext(id: "work", name: "Work", chromeProfileID: "Missing")]
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "chrome.profiles" && $0.status == .pass && $0.message.contains("Personal (Default)") })
        XCTAssertTrue(diagnostics.contains { $0.code == "chrome.profile.missing" && $0.status == .warning && $0.message.contains("Missing") })
    }

    func testDoctorWarnsWhenConfiguredChromeProfileMetadataIsUnavailable() {
        let diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: temporaryDirectory.appendingPathComponent("config"),
                launcherDirectory: temporaryDirectory.appendingPathComponent("Applications"),
                launchEnvironment: LaunchEnvironment(),
                chromeLocalStateURL: temporaryDirectory.appendingPathComponent("missing-local-state")
            ),
            contexts: [LauncherContext(id: "work", name: "Work", chromeProfileID: "Default")]
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "chrome.profile.unavailable" && $0.status == .warning && $0.message.contains("Default") })
    }

    func testDoctorDoesNotTreatFilesAsDirectories() throws {
        let configuration = temporaryDirectory.appendingPathComponent("config")
        let launchers = temporaryDirectory.appendingPathComponent("Applications")
        try Data().write(to: configuration)
        try Data().write(to: launchers)

        let diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: configuration,
                launcherDirectory: launchers,
                launchEnvironment: LaunchEnvironment()
            ),
            contexts: []
        )

        XCTAssertTrue(diagnostics.contains { $0.code == "config.directory" && $0.status == .warning })
        XCTAssertTrue(diagnostics.contains { $0.code == "launcher.directory" && $0.status == .warning })
    }

    private var fixtureEnvironment: DoctorEnvironment {
        DoctorEnvironment(
            configurationDirectory: temporaryDirectory.appendingPathComponent("config"),
            launcherDirectory: temporaryDirectory.appendingPathComponent("Applications"),
            launchEnvironment: LaunchEnvironment()
        )
    }
}
