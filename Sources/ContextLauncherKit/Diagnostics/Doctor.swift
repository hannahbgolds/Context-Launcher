import Foundation

public struct Diagnostic: Equatable, Sendable {
    public enum Status: String, Sendable {
        case pass
        case warning
        case failure
    }

    public let code: String
    public let status: Status
    public let message: String

    public init(code: String, status: Status, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }
}

public struct DoctorEnvironment: @unchecked Sendable {
    public var configurationDirectory: URL
    public var launcherDirectory: URL
    public var launchEnvironment: LaunchEnvironment

    public init(configurationDirectory: URL, launcherDirectory: URL, launchEnvironment: LaunchEnvironment = .system) {
        self.configurationDirectory = configurationDirectory
        self.launcherDirectory = launcherDirectory
        self.launchEnvironment = launchEnvironment
    }
}

public enum Doctor {
    public static func run(environment: DoctorEnvironment, contexts: [LauncherContext]) -> [Diagnostic] {
        let fileManager = environment.launchEnvironment.fileManager
        var diagnostics = [
            directoryDiagnostic(
                code: "config.directory",
                label: "Config directory",
                url: environment.configurationDirectory,
                fileManager: fileManager
            ),
            directoryDiagnostic(
                code: "launcher.directory",
                label: "Launcher directory",
                url: environment.launcherDirectory,
                fileManager: fileManager
            ),
            applicationDiagnostic(
                code: "chrome.available",
                label: "Google Chrome",
                url: environment.launchEnvironment.chromeApplicationURL,
                required: contexts.contains { $0.chromeProfileID?.isEmpty == false && !$0.urls.isEmpty }
            ),
            applicationDiagnostic(
                code: "vscode.available",
                label: "Visual Studio Code",
                url: environment.launchEnvironment.vscodeInstallation?.executableURL,
                required: contexts.contains { !$0.vscodeProjects.isEmpty }
            )
        ]

        for context in contexts {
            diagnostics.append(launcherDiagnostic(for: context, in: environment.launcherDirectory, fileManager: fileManager))

            for project in context.vscodeProjects where !fileManager.fileExists(atPath: project.path) {
                diagnostics.append(Diagnostic(
                    code: "project.missing",
                    status: .failure,
                    message: "VS Code project is missing: \(project.path)"
                ))
            }

            for application in context.applications {
                let standardApplication = application.standardizedFileURL
                guard !fileManager.fileExists(atPath: standardApplication.path) else { continue }
                diagnostics.append(Diagnostic(
                    code: "application.missing",
                    status: .failure,
                    message: "Application is missing: \(standardApplication.path)"
                ))
            }
        }

        return diagnostics
    }

    private static func directoryDiagnostic(code: String, label: String, url: URL, fileManager: FileManager) -> Diagnostic {
        let exists = fileManager.fileExists(atPath: url.path)
        return Diagnostic(
            code: code,
            status: exists ? .pass : .warning,
            message: exists ? "\(label): \(url.path)" : "\(label) is missing: \(url.path)"
        )
    }

    private static func applicationDiagnostic(code: String, label: String, url: URL?, required: Bool) -> Diagnostic {
        guard let url else {
            return Diagnostic(
                code: code,
                status: required ? .warning : .pass,
                message: required ? "\(label) was not found." : "\(label) is not configured."
            )
        }
        return Diagnostic(code: code, status: .pass, message: "\(label): \(url.path)")
    }

    private static func launcherDiagnostic(for context: LauncherContext, in directory: URL, fileManager: FileManager) -> Diagnostic {
        let bundle = directory.appendingPathComponent("\(context.id).app")
        guard fileManager.fileExists(atPath: bundle.path) else {
            return Diagnostic(code: "launcher.missing", status: .warning, message: "Launcher bundle is missing: \(bundle.path)")
        }

        let contents = bundle.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/launcher")
        let icon = contents.appendingPathComponent("Resources/AppIcon.icns")
        let plist = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))
        guard fileManager.isExecutableFile(atPath: executable.path),
              fileManager.fileExists(atPath: icon.path),
              plist?["CFBundleIdentifier"] as? String == "dev.contextlauncher.context.\(context.id)" else {
            return Diagnostic(code: "launcher.invalid", status: .failure, message: "Launcher bundle is invalid: \(bundle.path)")
        }
        return Diagnostic(code: "launcher.valid", status: .pass, message: "Launcher bundle is valid: \(bundle.path)")
    }
}
