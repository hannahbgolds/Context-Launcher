import Foundation
import XCTest
@testable import ContextLauncherKit

final class ContextStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testSaveLoadAndDuplicateRejection() throws {
        let file = temporaryDirectory.appendingPathComponent("contexts.json")
        let store = ContextStore(fileURL: file)

        try store.save([LauncherContext(id: "leet", name: "Leet")])

        XCTAssertEqual(try store.load().map(\.id), ["leet"])
        XCTAssertThrowsError(try store.save([
            LauncherContext(id: "leet", name: "One"),
            LauncherContext(id: "leet", name: "Two")
        ]))
    }

    func testMissingFileLoadsEmpty() throws {
        let store = ContextStore(fileURL: temporaryDirectory.appendingPathComponent("nested/contexts.json"))

        XCTAssertEqual(try store.load(), [])
    }

    func testUpsertReplacesByIDAndDeleteRemovesByID() throws {
        let store = ContextStore(fileURL: temporaryDirectory.appendingPathComponent("contexts.json"))
        try store.save([LauncherContext(id: "work", name: "Old")])

        try store.upsert(LauncherContext(id: "work", name: "New"))
        try store.upsert(LauncherContext(id: "leet", name: "Leet"))
        XCTAssertEqual(try store.load().map(\.id), ["leet", "work"])
        XCTAssertEqual(try store.load().first(where: { $0.id == "work" })?.name, "New")

        try store.delete(id: "work")
        XCTAssertEqual(try store.load().map(\.id), ["leet"])
    }

    func testLoadRejectsUnsupportedVersion() throws {
        let file = temporaryDirectory.appendingPathComponent("contexts.json")
        let data = Data(#"{"version":2,"contexts":[]}"#.utf8)
        try data.write(to: file)

        XCTAssertThrowsError(try ContextStore(fileURL: file).load())
    }

    func testStarterContextsContainNoPersonalValues() throws {
        let data = try JSONEncoder().encode(StarterContexts.all)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("@"))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertEqual(Set(StarterContexts.all.map(\.id)), ["uni", "leet", "work", "org"])
    }
}
