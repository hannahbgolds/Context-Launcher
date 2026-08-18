import AppKit
import Foundation
import XCTest
@testable import ContextLauncherKit

final class LauncherBundleTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var generator: LauncherBundleGenerator!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LauncherBundleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        generator = LauncherBundleGenerator()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testGeneratedBundleHasValidMetadataAndLiteralArguments() throws {
        let argumentsFile = temporaryDirectory.appendingPathComponent("arguments.txt")
        let cliURL = try makeCLI(named: "bin with space/quote\"back\\slash context", argumentsFile: argumentsFile)
        let context = LauncherContext(id: "leet", name: "Leet")

        let bundle = try generator.generate(for: context, cliURL: cliURL, in: temporaryDirectory)

        let plist = try XCTUnwrap(NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Leet")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.contextlauncher.context.leet")
        let launcher = bundle.appendingPathComponent("Contents/MacOS/launcher")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: launcher.path))
        XCTAssertNotNil(NSImage(contentsOf: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns")))
        XCTAssertEqual(try runtimeFiles(in: bundle), [
            "Contents/Info.plist",
            "Contents/MacOS/launcher",
            "Contents/Resources/AppIcon.icns"
        ])

        let process = Process()
        process.executableURL = launcher
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: argumentsFile, encoding: .utf8), "launch\nleet\n")
    }

    func testInvalidIDCannotGenerateBundle() {
        XCTAssertThrowsError(try generator.generate(
            for: LauncherContext(id: "../bad", name: "Bad"),
            cliURL: temporaryDirectory.appendingPathComponent("context"),
            in: temporaryDirectory
        ))
    }

    func testFailedReplacementPreservesExistingBundle() throws {
        let argumentsFile = temporaryDirectory.appendingPathComponent("arguments.txt")
        let cliURL = try makeCLI(named: "context", argumentsFile: argumentsFile)
        let existing = try generator.generate(for: LauncherContext(id: "leet", name: "Original"), cliURL: cliURL, in: temporaryDirectory)

        XCTAssertThrowsError(try generator.generate(
            for: LauncherContext(id: "leet", name: "Broken", icon: .custom(temporaryDirectory.appendingPathComponent("missing.png").path)),
            cliURL: cliURL,
            in: temporaryDirectory
        ))

        let plist = try XCTUnwrap(NSDictionary(contentsOf: existing.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Original")
    }

    func testNewLauncherCallsNewCommandAndRemoveOnlyRemovesValidatedLauncher() throws {
        let argumentsFile = temporaryDirectory.appendingPathComponent("arguments.txt")
        let cliURL = try makeCLI(named: "context", argumentsFile: argumentsFile)
        let bundle = try generator.generateNewLauncher(cliURL: cliURL, in: temporaryDirectory)
        let launcher = bundle.appendingPathComponent("Contents/MacOS/launcher")

        XCTAssertEqual(bundle.lastPathComponent, "New.app")

        let process = Process()
        process.executableURL = launcher
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: argumentsFile, encoding: .utf8), "new\n")
        try generator.remove(id: "new", from: temporaryDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.path))
        XCTAssertThrowsError(try generator.remove(id: "../bad", from: temporaryDirectory))
    }

    private func makeCLI(named name: String, argumentsFile: URL) throws -> URL {
        let cliURL = temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(argumentsFile.path)'\n"
        try Data(script.utf8).write(to: cliURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
        return cliURL
    }

    private func runtimeFiles(in bundle: URL) throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isDirectoryKey])!
        return try enumerator.compactMap { element in
            let url = element as! URL
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true,
                  let bundleIndex = url.pathComponents.lastIndex(of: bundle.lastPathComponent) else { return nil }
            return url.pathComponents.dropFirst(bundleIndex + 1).joined(separator: "/")
        }.sorted()
    }
}
