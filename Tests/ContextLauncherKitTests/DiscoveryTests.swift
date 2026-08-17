import Foundation
import XCTest
@testable import ContextLauncherKit

final class DiscoveryTests: XCTestCase {
    private final class StubFileManager: FileManager {
        var existingPaths = Set<String>()

        override func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }

        override func isExecutableFile(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }
    }

    func testParsesHumanReadableChromeProfiles() throws {
        let json = #"{"profile":{"info_cache":{"Default":{"name":"Hannah Personal","user_name":"person@example.test"},"Profile 2":{"name":"Vertalis"}}}}"#.data(using: .utf8)!

        let profiles = try ChromeProfileDiscovery.parse(localStateData: json)

        XCTAssertEqual(profiles.map(\.directoryID), ["Default", "Profile 2"])
        XCTAssertEqual(profiles.first?.email, "person@example.test")
        XCTAssertNil(profiles.last?.email)
    }

    func testMalformedChromeMetadataReturnsTypedError() {
        XCTAssertThrowsError(try ChromeProfileDiscovery.parse(localStateData: Data("{".utf8))) { error in
            XCTAssertTrue(error is ChromeProfileDiscovery.Error)
        }
    }

    func testChromeDiscoveryReadsLocalStateURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localStateURL = directory.appendingPathComponent("Local State")
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"}}}}"#.utf8).write(to: localStateURL)

        XCTAssertEqual(try ChromeProfileDiscovery.discover(localStateURL: localStateURL).first?.name, "Personal")
    }

    func testChromeApplicationDiscoveryChecksSystemAndUserLocations() {
        let fileManager = StubFileManager()
        let home = "/tmp/chrome-home"
        fileManager.existingPaths.insert("/Applications/Google Chrome.app")

        XCTAssertEqual(
            ChromeProfileDiscovery.discoverApplicationURL(fileManager: fileManager, environment: ["HOME": home]),
            URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )

        fileManager.existingPaths = [URL(fileURLWithPath: home).appendingPathComponent("Applications/Google Chrome.app").path]
        XCTAssertEqual(
            ChromeProfileDiscovery.discoverApplicationURL(fileManager: fileManager, environment: ["HOME": home]),
            URL(fileURLWithPath: home).appendingPathComponent("Applications/Google Chrome.app")
        )
    }

    func testVSCodeDiscoveryFindsCodeOnPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let codeURL = directory.appendingPathComponent("code")
        FileManager.default.createFile(atPath: codeURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codeURL.path)

        let installation = VSCodeDiscovery.discover(fileManager: .default, environment: ["PATH": directory.path])

        XCTAssertEqual(installation, VSCodeInstallation(executableURL: codeURL, usesShellCommand: true))
    }

    func testVSCodeDiscoveryFindsBundledExecutableUnderHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codeURL = home.appendingPathComponent("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
        try FileManager.default.createDirectory(at: codeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        FileManager.default.createFile(atPath: codeURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codeURL.path)

        let installation = VSCodeDiscovery.discover(fileManager: .default, environment: ["PATH": "", "HOME": home.path])

        XCTAssertEqual(installation, VSCodeInstallation(executableURL: codeURL, usesShellCommand: false))
    }

    func testVSCodeDiscoveryFindsSystemBundledExecutable() {
        let fileManager = StubFileManager()
        let codeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
        fileManager.existingPaths = [codeURL.path]

        XCTAssertEqual(
            VSCodeDiscovery.discover(fileManager: fileManager, environment: ["PATH": "", "HOME": "/tmp/no-home"]),
            VSCodeInstallation(executableURL: codeURL, usesShellCommand: false)
        )
    }
}
