import Foundation

public enum LaunchAction: Equatable, Sendable {
    case chrome(executable: URL, profileID: String, urls: [URL])
    case vscode(executable: URL, arguments: [String])
    case application(URL)
}

public struct LaunchPlan: Equatable, Sendable {
    public var actions: [LaunchAction]
    public var warnings: [String]

    public init(actions: [LaunchAction] = [], warnings: [String] = []) {
        self.actions = actions
        self.warnings = warnings
    }
}

public struct LaunchEnvironment: @unchecked Sendable {
    public var chromeApplicationURL: URL?
    public var vscodeInstallation: VSCodeInstallation?
    public var fileManager: FileManager

    public init(
        chromeApplicationURL: URL? = nil,
        vscodeInstallation: VSCodeInstallation? = nil,
        fileManager: FileManager = .default
    ) {
        self.chromeApplicationURL = chromeApplicationURL
        self.vscodeInstallation = vscodeInstallation
        self.fileManager = fileManager
    }

    public static var system: LaunchEnvironment {
        LaunchEnvironment(
            chromeApplicationURL: ChromeProfileDiscovery.discoverApplicationURL(),
            vscodeInstallation: VSCodeDiscovery.discover()
        )
    }
}

public enum LaunchPlanner {
    public static func plan(for context: LauncherContext, environment: LaunchEnvironment) -> LaunchPlan {
        var plan = LaunchPlan()

        if let profileID = context.chromeProfileID, !profileID.isEmpty, !context.urls.isEmpty {
            if let chromeURL = environment.chromeApplicationURL {
                plan.actions.append(.chrome(executable: chromeURL, profileID: profileID, urls: context.urls))
            } else {
                plan.warnings.append("Google Chrome was not found; skipped \(context.urls.count) URL(s).")
            }
        }

        let existingProjects = context.vscodeProjects.filter { environment.fileManager.fileExists(atPath: $0.path) }
        for project in context.vscodeProjects where !environment.fileManager.fileExists(atPath: project.path) {
            plan.warnings.append("VS Code project is missing: \(project.path)")
        }
        if !existingProjects.isEmpty {
            if let vscode = environment.vscodeInstallation {
                for project in existingProjects {
                    plan.actions.append(.vscode(executable: vscode.executableURL, arguments: ["--new-window", project.path]))
                }
            } else {
                plan.warnings.append("Visual Studio Code was not found; skipped \(existingProjects.count) project(s).")
            }
        }

        for application in context.applications {
            let standardizedApplication = application.standardizedFileURL
            guard environment.fileManager.fileExists(atPath: standardizedApplication.path) else {
                plan.warnings.append("Application is missing: \(standardizedApplication.path)")
                continue
            }
            plan.actions.append(.application(standardizedApplication))
        }

        return plan
    }
}
