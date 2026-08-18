import Foundation
import ContextLauncherKit

private enum CLIError: LocalizedError {
    case contextNotFound(String)
    case installedApplicationMissing(URL)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .contextNotFound(id): return "No context with ID '\(id)' is configured."
        case let .installedApplicationMissing(url): return "Context Launcher is not installed at \(url.path)."
        case let .commandFailed(command): return "Command failed: \(command)"
        }
    }
}

private struct Runtime {
    let supportDirectory: URL
    let installRoot: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        supportDirectory = environment["CONTEXT_LAUNCHER_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ContextLauncher", isDirectory: true)
        installRoot = environment["INSTALL_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    var store: ContextStore {
        ContextStore(fileURL: supportDirectory.appendingPathComponent("contexts.json"))
    }

    var applicationURL: URL {
        installRoot.appendingPathComponent("Context Launcher.app", isDirectory: true)
    }

    var cliURL: URL {
        supportDirectory.appendingPathComponent("bin/context")
    }
}

private func usage() {
    FileHandle.standardError.write(Data("Usage: context list | launch <id> | new | edit <id> | doctor\n".utf8))
}

private func openApplication(_ applicationURL: URL, arguments: [String]) throws {
    guard FileManager.default.fileExists(atPath: applicationURL.path) else {
        throw CLIError.installedApplicationMissing(applicationURL)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [applicationURL.path, "--args"] + arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CLIError.commandFailed("open \(applicationURL.path)")
    }
}

private func printDiagnostics(_ diagnostics: [Diagnostic]) {
    for diagnostic in diagnostics {
        print("[\(diagnostic.status.rawValue.uppercased())] \(diagnostic.message)")
    }
}

private func run(_ arguments: [String], runtime: Runtime) throws -> Int32 {
    switch arguments {
    case ["list"]:
        let contexts = try runtime.store.load()
        if contexts.isEmpty {
            print("No contexts configured. Run 'context new' to create one.")
        } else {
            for context in contexts {
                print("\(context.id)\t\(context.name)\(context.subtitle.isEmpty ? "" : " — \(context.subtitle)")")
            }
        }
    case let command where command.count == 2 && command[0] == "launch":
        let id = command[1]
        guard let context = try runtime.store.load().first(where: { $0.id == id }) else {
            throw CLIError.contextNotFound(id)
        }
        for warning in ContextLauncher().launch(context).warnings {
            FileHandle.standardError.write(Data("Warning: \(warning)\n".utf8))
        }
    case ["new"]:
        try openApplication(runtime.applicationURL, arguments: ["--new"])
    case let command where command.count == 2 && command[0] == "edit":
        let id = command[1]
        try openApplication(runtime.applicationURL, arguments: ["--edit", id])
    case ["doctor"]:
        let contexts = try runtime.store.load()
        printDiagnostics(Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: runtime.supportDirectory,
                launcherDirectory: runtime.installRoot,
                launchEnvironment: .system
            ),
            contexts: contexts
        ))
    case ["internal-generate-all"]:
        let generator = LauncherBundleGenerator()
        for context in try runtime.store.load() {
            try generator.generate(for: context, cliURL: runtime.cliURL, in: runtime.installRoot)
        }
        try generator.generateNewLauncher(cliURL: runtime.cliURL, in: runtime.installRoot)
    default:
        usage()
        return 1
    }
    return 0
}

do {
    exit(try run(Array(CommandLine.arguments.dropFirst()), runtime: Runtime()))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
