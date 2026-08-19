import Foundation

public enum LauncherBundleNaming {
    public static func bundleName(for context: LauncherContext, among contexts: [LauncherContext]) -> String {
        let base = safeDisplayName(context.name, fallback: context.id)
        let duplicate = contexts.filter {
            safeDisplayName($0.name, fallback: $0.id).caseInsensitiveCompare(base) == .orderedSame
        }.count > 1
        let reserved = ["New", "Context Launcher"].contains {
            $0.caseInsensitiveCompare(base) == .orderedSame
        }
        return duplicate || reserved ? "\(base) (\(context.id))" : base
    }

    private static func safeDisplayName(_ name: String, fallback: String) -> String {
        let replaced = name.unicodeScalars.map { scalar -> String in
            scalar == "/" || scalar == ":" || scalar.value < 32 || scalar.value == 127 ? "-" : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replaced.isEmpty, replaced != ".", replaced != ".." else { return fallback }
        return replaced.hasPrefix(".") ? "-" + replaced.dropFirst() : replaced
    }
}

public enum LauncherBundleError: LocalizedError {
    case invalidContextID(String)
    case invalidBundle
    case compilerFailed
    case destinationCollision(URL, expectedIdentifier: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidContextID(id):
            return "Invalid context ID: \(id)"
        case .invalidBundle:
            return "The generated launcher bundle is invalid."
        case .compilerFailed:
            return "The launcher executable could not be compiled."
        case let .destinationCollision(url, identifier):
            return "Refusing to replace \(url.path): it is a symlink or is not owned by Context Launcher as \(identifier). Move or rename the existing item, then try again."
        }
    }
}

public struct LauncherBundleGenerator {
    private let iconRenderer: IconRenderer

    public init(iconRenderer: IconRenderer = IconRenderer()) {
        self.iconRenderer = iconRenderer
    }

    @discardableResult
    public func generate(for context: LauncherContext, cliURL: URL, in destination: URL) throws -> URL {
        try generate(for: context, among: [context], cliURL: cliURL, in: destination)
    }

    @discardableResult
    public func generate(for context: LauncherContext, among contexts: [LauncherContext], cliURL: URL, in destination: URL) throws -> URL {
        guard isValidID(context.id), context.id != "new" else { throw LauncherBundleError.invalidContextID(context.id) }
        return try generate(
            name: context.name,
            bundleName: LauncherBundleNaming.bundleName(for: context, among: contexts),
            id: context.id,
            icon: context.icon,
            arguments: ["launch", context.id],
            cliURL: cliURL,
            in: destination
        )
    }

    @discardableResult
    public func generateNewLauncher(cliURL: URL, in destination: URL) throws -> URL {
        try generate(
            name: "New",
            bundleName: "New",
            id: "new",
            icon: .symbol("plus.circle"),
            arguments: ["new"],
            cliURL: cliURL,
            in: destination
        )
    }

    public func remove(id: String, from destination: URL) throws {
        guard isValidID(id) else { throw LauncherBundleError.invalidContextID(id) }
        let identifier = bundleIdentifier(for: id)
        guard let destinationAttributes = try? FileManager.default.attributesOfItem(atPath: destination.path) else { return }
        guard destinationAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw LauncherBundleError.destinationCollision(destination, expectedIdentifier: identifier)
        }
        let candidates = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
        for bundle in candidates {
            if isOwnedBundle(at: bundle, identifier: identifier) {
                try FileManager.default.removeItem(at: bundle)
            } else if bundle.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(id) == .orderedSame {
                throw LauncherBundleError.destinationCollision(bundle, expectedIdentifier: identifier)
            }
        }
    }

    public func remove(_ context: LauncherContext, from destination: URL) throws {
        guard isValidID(context.id) else { throw LauncherBundleError.invalidContextID(context.id) }
        let bundle = bundleURL(named: LauncherBundleNaming.bundleName(for: context, among: [context]), in: destination)
        guard itemExists(at: bundle) else { return }
        let identifier = bundleIdentifier(for: context.id)
        guard isOwnedBundle(at: bundle, identifier: identifier) else {
            throw LauncherBundleError.destinationCollision(bundle, expectedIdentifier: identifier)
        }
        try FileManager.default.removeItem(at: bundle)
    }

    private func generate(name: String, bundleName: String, id: String, icon: ContextIcon, arguments: [String], cliURL: URL, in destination: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let bundle = bundleURL(named: bundleName, in: destination)
        let identifier = bundleIdentifier(for: id)
        if itemExists(at: bundle), !isOwnedBundle(at: bundle, identifier: identifier) {
            throw LauncherBundleError.destinationCollision(bundle, expectedIdentifier: identifier)
        }
        let staging = destination.appendingPathComponent(".\(id)-\(UUID().uuidString).app", isDirectory: true)
        let compilerCache = destination.appendingPathComponent(".\(id)-\(UUID().uuidString).module-cache", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        defer { try? fileManager.removeItem(at: compilerCache) }

        let contents = staging.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try compileLauncher(cliURL: cliURL, arguments: arguments, destination: macOS.appendingPathComponent("launcher"), moduleCacheURL: compilerCache)
        if fileManager.fileExists(atPath: compilerCache.path) {
            try fileManager.removeItem(at: compilerCache)
        }
        try iconRenderer.render(icon, destination: resources.appendingPathComponent("AppIcon.icns"))
        guard isValidBundle(at: staging, identifier: identifier) else { throw LauncherBundleError.invalidBundle }

        if fileManager.fileExists(atPath: bundle.path) {
            _ = try fileManager.replaceItemAt(bundle, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: bundle)
        }
        try removeOtherOwnedBundles(identifier: identifier, keeping: bundle, from: destination)
        return bundle
    }

    private func compileLauncher(cliURL: URL, arguments: [String], destination: URL, moduleCacheURL: URL) throws {
        let source = destination.deletingLastPathComponent().appendingPathComponent("launcher.swift")
        defer { try? FileManager.default.removeItem(at: source) }
        let literals = ([cliURL.path] + arguments).map(swiftStringLiteral).joined(separator: ", ")
        let program = """
        import Foundation
        let values = [\(literals)]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: values[0])
        process.arguments = Array(values.dropFirst())
        do {
            try process.run()
            process.waitUntilExit()
            exit(process.terminationStatus)
        } catch {
            FileHandle.standardError.write(Data("\\(error.localizedDescription)\\n".utf8))
            exit(1)
        }
        """
        try Data(program.utf8).write(to: source)

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compiler.arguments = [source.path, "-o", destination.path]
        compiler.environment = ProcessInfo.processInfo.environment.merging([
            "CLANG_MODULE_CACHE_PATH": moduleCacheURL.path
        ]) { _, replacement in replacement }
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else { throw LauncherBundleError.compilerFailed }
    }

    private func isValidBundle(at bundle: URL, identifier: String) -> Bool {
        let contents = bundle.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/launcher")
        let icon = contents.appendingPathComponent("Resources/AppIcon.icns")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: icon.path),
              let plist = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) else { return false }
        return plist["CFBundleIdentifier"] as? String == identifier
    }

    private func bundleURL(named name: String, in destination: URL) -> URL {
        destination.appendingPathComponent("\(name).app", isDirectory: true)
    }

    private func bundleIdentifier(for id: String) -> String {
        "dev.contextlauncher.context.\(id)"
    }

    private func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }

    private func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private func isOwnedBundle(at bundle: URL, identifier: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: bundle.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else {
            return false
        }
        return plist["CFBundleIdentifier"] as? String == identifier
    }

    private func removeOtherOwnedBundles(identifier: String, keeping bundle: URL, from destination: URL) throws {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        for candidate in candidates
        where candidate.standardizedFileURL.path != bundle.standardizedFileURL.path
            && isOwnedBundle(at: candidate, identifier: identifier) {
            try FileManager.default.removeItem(at: candidate)
        }
    }

    private func swiftStringLiteral(_ value: String) -> String {
        let escaped = value.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0: return "\\0"
            case 9: return "\\t"
            case 10: return "\\n"
            case 13: return "\\r"
            case 34: return "\\\""
            case 92: return "\\\\"
            case 0..<32: return "\\u{\(String(scalar.value, radix: 16))}"
            default: return String(scalar)
            }
        }.joined()
        return "\"\(escaped)\""
    }
}
