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

        if let profileID = context.chromeProfileID, !profileID.isEmpty {
            if let chromeURL = environment.chromeApplicationURL {
                plan.actions.append(.chrome(executable: chromeURL, profileID: profileID, urls: context.urls))
            } else {
                let work = context.urls.isEmpty ? "the selected profile" : "the selected profile and \(context.urls.count) URL(s)"
                plan.warnings.append("Google Chrome was not found; skipped \(work).")
            }
        }

        var existingProjects: [URL] = []
        for project in context.vscodeProjects {
            guard ResourceValidator.exists(project, fileManager: environment.fileManager) else {
                plan.warnings.append("VS Code project is missing: \(project.path)")
                continue
            }
            guard ResourceValidator.isValidExistingProject(project, fileManager: environment.fileManager) else {
                plan.warnings.append("VS Code project is not a folder or .code-workspace file: \(project.path)")
                continue
            }
            existingProjects.append(project)
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
            guard ResourceValidator.exists(standardizedApplication, fileManager: environment.fileManager) else {
                plan.warnings.append("Application is missing: \(standardizedApplication.path)")
                continue
            }
            guard ResourceValidator.isValidExistingApplication(standardizedApplication, fileManager: environment.fileManager) else {
                plan.warnings.append("Application is not an actual .app bundle directory: \(standardizedApplication.path)")
                continue
            }
            plan.actions.append(.application(standardizedApplication))
        }

        return plan
    }
}
