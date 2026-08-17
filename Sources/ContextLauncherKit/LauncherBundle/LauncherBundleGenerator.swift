import Foundation

public enum LauncherBundleError: Error {
    case invalidContextID(String)
    case invalidBundle
    case compilerFailed
}

public struct LauncherBundleGenerator {
    private let iconRenderer: IconRenderer

    public init(iconRenderer: IconRenderer = IconRenderer()) {
        self.iconRenderer = iconRenderer
    }

    @discardableResult
    public func generate(for context: LauncherContext, cliURL: URL, in destination: URL) throws -> URL {
        guard isValidID(context.id) else { throw LauncherBundleError.invalidContextID(context.id) }
        return try generate(
            name: context.name,
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
            id: "new",
            icon: .symbol("plus.circle"),
            arguments: ["new"],
            cliURL: cliURL,
            in: destination
        )
    }

    public func remove(id: String, from destination: URL) throws {
        guard isValidID(id) else { throw LauncherBundleError.invalidContextID(id) }
        let bundle = bundleURL(for: id, in: destination)
        guard FileManager.default.fileExists(atPath: bundle.path) else { return }
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        let plist = NSDictionary(contentsOf: plistURL)
        guard plist?["CFBundleIdentifier"] as? String == bundleIdentifier(for: id) else { return }
        try FileManager.default.removeItem(at: bundle)
    }

    private func generate(name: String, id: String, icon: ContextIcon, arguments: [String], cliURL: URL, in destination: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let bundle = bundleURL(for: id, in: destination)
        let staging = destination.appendingPathComponent(".\(id)-\(UUID().uuidString).app", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        let contents = staging.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": bundleIdentifier(for: id),
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try compileLauncher(cliURL: cliURL, arguments: arguments, destination: macOS.appendingPathComponent("launcher"))
        try iconRenderer.render(icon, destination: resources.appendingPathComponent("AppIcon.icns"))
        guard isValidBundle(at: staging, identifier: bundleIdentifier(for: id)) else { throw LauncherBundleError.invalidBundle }

        if fileManager.fileExists(atPath: bundle.path) {
            _ = try fileManager.replaceItemAt(bundle, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: bundle)
        }
        return bundle
    }

    private func compileLauncher(cliURL: URL, arguments: [String], destination: URL) throws {
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
            "CLANG_MODULE_CACHE_PATH": destination.deletingLastPathComponent().appendingPathComponent("module-cache").path
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

    private func bundleURL(for id: String, in destination: URL) -> URL {
        destination.appendingPathComponent("\(id).app", isDirectory: true)
    }

    private func bundleIdentifier(for id: String) -> String {
        "dev.contextlauncher.context.\(id)"
    }

    private func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
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
