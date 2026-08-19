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

        XCTAssertEqual(bundle.lastPathComponent, "Leet.app")
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
        XCTAssertThrowsError(try generator.generate(
            for: LauncherContext(id: "new", name: "Anything"),
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

    func testGenerationRejectsUnownedContextAndNewBundlesWithoutMutation() throws {
        let cliURL = try makeCLI(named: "context", argumentsFile: temporaryDirectory.appendingPathComponent("arguments.txt"))
        let contextDecoy = temporaryDirectory.appendingPathComponent("Leet.app", isDirectory: true)
        let newDecoy = temporaryDirectory.appendingPathComponent("New.app", isDirectory: true)
        try makeBundle(at: contextDecoy, identifier: "com.example.unrelated", marker: "context decoy")
        try makeBundle(at: newDecoy, identifier: "com.example.new", marker: "new decoy")

        XCTAssertThrowsError(try generator.generate(
            for: LauncherContext(id: "leet", name: "Leet"),
            cliURL: cliURL,
            in: temporaryDirectory
        ))
        XCTAssertThrowsError(try generator.generateNewLauncher(cliURL: cliURL, in: temporaryDirectory))
        XCTAssertEqual(try marker(in: contextDecoy), "context decoy")
        XCTAssertEqual(try marker(in: newDecoy), "new decoy")
    }

    func testGenerationAndRemovalRejectSymlinkDestinationsWithoutTouchingTargets() throws {
        let cliURL = try makeCLI(named: "context", argumentsFile: temporaryDirectory.appendingPathComponent("arguments.txt"))
        let target = temporaryDirectory.appendingPathComponent("target", isDirectory: true)
        try makeBundle(at: target, identifier: "dev.contextlauncher.context.leet", marker: "target")
        let link = temporaryDirectory.appendingPathComponent("Leet.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try generator.generate(
            for: LauncherContext(id: "leet", name: "Leet"),
            cliURL: cliURL,
            in: temporaryDirectory
        ))
        XCTAssertThrowsError(try generator.remove(LauncherContext(id: "leet", name: "Leet"), from: temporaryDirectory))
        XCTAssertEqual(try marker(in: target), "target")
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    func testRemovalReportsUnownedBundleCollisionWithoutMutation() throws {
        let decoy = temporaryDirectory.appendingPathComponent("Leet.app", isDirectory: true)
        try makeBundle(at: decoy, identifier: "com.example.unrelated", marker: "keep")

        XCTAssertThrowsError(try generator.remove(LauncherContext(id: "leet", name: "Leet"), from: temporaryDirectory))
        XCTAssertThrowsError(try generator.remove(id: "leet", from: temporaryDirectory))

        XCTAssertEqual(try marker(in: decoy), "keep")
    }

    func testRemovalFromMissingLauncherDirectoryIsANoop() throws {
        try generator.remove(id: "leet", from: temporaryDirectory.appendingPathComponent("missing"))
    }

    func testDuplicateAndReservedDisplayNamesAreSafelyDisambiguated() throws {
        let cliURL = try makeCLI(named: "context", argumentsFile: temporaryDirectory.appendingPathComponent("arguments.txt"))
        let contexts = [
            LauncherContext(id: "first", name: "Work"),
            LauncherContext(id: "second", name: "Work"),
            LauncherContext(id: "fresh", name: "New"),
            LauncherContext(id: "hidden", name: ".Hidden")
        ]

        let bundles = try contexts.map {
            try generator.generate(for: $0, among: contexts, cliURL: cliURL, in: temporaryDirectory)
        }

        XCTAssertEqual(Set(bundles.map(\.lastPathComponent)), ["Work (first).app", "Work (second).app", "New (fresh).app", "-Hidden.app"])
        for context in contexts {
            let bundle = try XCTUnwrap(bundles.first { bundle in
                let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
                return plist?["CFBundleIdentifier"] as? String == "dev.contextlauncher.context.\(context.id)"
            })
            XCTAssertEqual(
                NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleDisplayName"] as? String,
                context.name
            )
        }
    }

    private func makeCLI(named name: String, argumentsFile: URL) throws -> URL {
        let cliURL = temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(argumentsFile.path)'\n"
        try Data(script.utf8).write(to: cliURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
        return cliURL
    }

    private func makeBundle(at url: URL, identifier: String, marker: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": identifier]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
    }

    private func marker(in bundle: URL) throws -> String {
        try String(contentsOf: bundle.appendingPathComponent("marker"), encoding: .utf8)
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
