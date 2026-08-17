import Foundation

public struct VSCodeInstallation: Equatable, Sendable {
    public let executableURL: URL
    public let usesShellCommand: Bool

    public init(executableURL: URL, usesShellCommand: Bool) {
        self.executableURL = executableURL
        self.usesShellCommand = usesShellCommand
    }
}

public enum VSCodeDiscovery {
    public static func discover(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) -> VSCodeInstallation? {
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent("code")
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return VSCodeInstallation(executableURL: candidate, usesShellCommand: true)
                }
            }
        }

        let home = environment["HOME"] ?? NSHomeDirectory()
        let candidates: [(URL, Bool)] = [
            (URL(fileURLWithPath: "/usr/local/bin/code"), true),
            (URL(fileURLWithPath: "/opt/homebrew/bin/code"), true),
            (URL(fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"), false),
            (URL(fileURLWithPath: home).appendingPathComponent("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"), false)
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.0.path) }
            .map { VSCodeInstallation(executableURL: $0.0, usesShellCommand: $0.1) }
    }
}
