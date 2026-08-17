import AppKit
import Foundation

public protocol ApplicationOpening: AnyObject {
    func openApplication(at url: URL) throws
}

public final class WorkspaceApplicationOpener: ApplicationOpening {
    public init() {}

    public func openApplication(at url: URL) throws {
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

/// An optional adapter for the best-effort Chrome window targeting path.
/// Returning `false` or throwing always falls back to a new structured launch.
public protocol ChromeWindowTargeting: AnyObject {
    func open(urls: [URL], inProfile profileID: String) throws -> Bool
}

public struct LaunchResult: Equatable, Sendable {
    public var warnings: [String]

    public init(warnings: [String] = []) {
        self.warnings = warnings
    }
}

public final class ContextLauncher {
    private let environment: LaunchEnvironment
    private let processRunner: ProcessRunning
    private let applicationOpener: ApplicationOpening
    private let chromeWindowTargeter: ChromeWindowTargeting?

    public init(
        environment: LaunchEnvironment = .system,
        processRunner: ProcessRunning = ProcessRunner(),
        applicationOpener: ApplicationOpening = WorkspaceApplicationOpener(),
        chromeWindowTargeter: ChromeWindowTargeting? = nil
    ) {
        self.environment = environment
        self.processRunner = processRunner
        self.applicationOpener = applicationOpener
        self.chromeWindowTargeter = chromeWindowTargeter
    }

    public func launch(_ context: LauncherContext) -> LaunchResult {
        let plan = LaunchPlanner.plan(for: context, environment: environment)
        var result = LaunchResult(warnings: plan.warnings)

        for action in plan.actions {
            do {
                try execute(action)
            } catch {
                result.warnings.append(error.localizedDescription)
            }
        }
        return result
    }

    private func execute(_ action: LaunchAction) throws {
        switch action {
        case let .chrome(executable, profileID, urls):
            if (try? chromeWindowTargeter?.open(urls: urls, inProfile: profileID)) == true {
                return
            }
            try processRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-na", executable.path, "--args", "--profile-directory=\(profileID)"] + urls.map(\.absoluteString)
            )
        case let .vscode(executable, arguments):
            try processRunner.run(executable: executable, arguments: arguments)
        case let .application(url):
            try applicationOpener.openApplication(at: url)
        }
    }
}
