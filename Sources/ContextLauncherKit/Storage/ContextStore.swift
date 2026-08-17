import Foundation

public struct ContextDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var contexts: [LauncherContext]

    public init(version: Int = 1, contexts: [LauncherContext]) {
        self.version = version
        self.contexts = contexts
    }
}

public enum ContextStoreError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case validation([ValidationIssue])
}

public final class ContextStore: @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [LauncherContext] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(ContextDocument.self, from: data)
        guard document.version == 1 else {
            throw ContextStoreError.unsupportedVersion(document.version)
        }
        try validate(document.contexts)
        return document.contexts
    }

    public func save(_ contexts: [LauncherContext]) throws {
        let sortedContexts = contexts.sorted { $0.id < $1.id }
        try validate(sortedContexts)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ContextDocument(contexts: sortedContexts))

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    public func upsert(_ context: LauncherContext) throws {
        var contexts = try load()
        if let index = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts[index] = context
        } else {
            contexts.append(context)
        }
        try save(contexts)
    }

    public func delete(id: String) throws {
        var contexts = try load()
        contexts.removeAll { $0.id == id }
        try save(contexts)
    }

    private func validate(_ contexts: [LauncherContext]) throws {
        var validated: [LauncherContext] = []
        for context in contexts {
            let issues = ContextValidator.validate(context, among: validated)
            guard issues.isEmpty else {
                throw ContextStoreError.validation(issues)
            }
            validated.append(context)
        }
    }
}
