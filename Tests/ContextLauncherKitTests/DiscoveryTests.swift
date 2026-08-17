import Foundation
import XCTest
@testable import ContextLauncherKit

final class DiscoveryTests: XCTestCase {
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
}
