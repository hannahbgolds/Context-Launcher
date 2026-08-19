import Combine
import ContextLauncherKit
import Foundation

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

typealias LauncherSyncOperation = @Sendable ([LauncherContext], Bool) throws -> Void

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var contexts: [LauncherContext] = []
    @Published private(set) var chromeProfiles: [ChromeProfile] = []
    @Published private(set) var diagnostics: [Diagnostic] = []
    @Published private(set) var vscodeInstallation: VSCodeInstallation?
    @Published var selectedContextID: String?
    @Published var draft: LauncherContext?
    @Published var starterContexts = StarterContexts.all
    @Published var showsDiagnostics = false
    @Published var showsOnboardingCompletion = false
    @Published var alert: AppAlert?
    @Published private(set) var editorSessionID = UUID()
    @Published private(set) var configurationLoadError: String?
    @Published private(set) var isSynchronizingLaunchers = false

    private let supportDirectory: URL
    private let launcherDirectory: URL
    private let cliURL: URL
    private let setupPendingURL: URL
    private let store: ContextStore
    private let launcherSync: LauncherSyncOperation
    private var originalContextID: String?
    private var onboardingIsActive = false

    var needsOnboarding: Bool {
        allowsStorageMutations && onboardingIsActive
    }

    var allowsStorageMutations: Bool {
        configurationLoadError == nil
    }

    var canDeleteDraft: Bool {
        originalContextID != nil && allowsStorageMutations && !isSynchronizingLaunchers
    }

    init(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        launcherSync: LauncherSyncOperation? = nil
    ) {
        supportDirectory = environment["CONTEXT_LAUNCHER_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ContextLauncher", isDirectory: true)
        launcherDirectory = environment["INSTALL_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        cliURL = supportDirectory.appendingPathComponent("bin/context")
        setupPendingURL = supportDirectory.appendingPathComponent("setup-pending")
        store = ContextStore(fileURL: supportDirectory.appendingPathComponent("contexts.json"))
        let cliURL = self.cliURL
        let launcherDirectory = self.launcherDirectory
        self.launcherSync = launcherSync ?? { contexts, includingNew in
            let generator = LauncherBundleGenerator()
            for context in contexts {
                try generator.generate(for: context, cliURL: cliURL, in: launcherDirectory)
            }
            if includingNew {
                try generator.generateNewLauncher(cliURL: cliURL, in: launcherDirectory)
            }
        }

        load(arguments: arguments)
    }

    func beginNewContext() {
        let ids = Set(contexts.map(\.id))
        var id = "new-context"
        var suffix = 2
        while ids.contains(id) {
            id = "new-context-\(suffix)"
            suffix += 1
        }
        originalContextID = nil
        selectedContextID = nil
        showsDiagnostics = false
        draft = LauncherContext(id: id, name: "New Context", icon: .symbol("folder"))
        editorSessionID = UUID()
    }

    func beginEditing(id: String) {
        guard let context = contexts.first(where: { $0.id == id }) else {
            presentError("Context not found", message: "No context with ID '\(id)' is configured.")
            return
        }
        originalContextID = id
        selectedContextID = id
        showsDiagnostics = false
        draft = context
        editorSessionID = UUID()
    }

    func cancelEditing() {
        if let originalContextID, let stored = contexts.first(where: { $0.id == originalContextID }) {
            draft = stored
            editorSessionID = UUID()
        } else if let first = contexts.first {
            beginEditing(id: first.id)
        } else {
            draft = nil
        }
    }

    func showDiagnostics() {
        draft = nil
        selectedContextID = nil
        showsDiagnostics = true
        refreshDiagnostics()
    }

    func save(_ context: LauncherContext) async {
        guard requireStorageAccess(), requireIdleLauncherSync() else { return }
        var updated = contexts
        let previousID = originalContextID
        if let previousID {
            updated.removeAll { $0.id == previousID }
        }
        updated.append(context)

        do {
            try store.save(updated)
            contexts = try store.load()
            originalContextID = context.id
            selectedContextID = context.id
            draft = context
        } catch {
            reloadAfterPartialWrite()
            present(error, title: "Couldn’t save context")
            return
        }

        isSynchronizingLaunchers = true
        defer { isSynchronizingLaunchers = false }
        do {
            if let previousID, previousID != context.id {
                try LauncherBundleGenerator().remove(id: previousID, from: launcherDirectory)
            }
            try await runLauncherSync(for: [context], includingNew: true)
            refreshDiagnostics()
            alert = AppAlert(title: "Context saved", message: "The \(context.name) launcher is ready for Spotlight.")
        } catch {
            refreshDiagnostics()
            present(error, title: "Context saved, but its launcher needs attention")
        }
    }

    func deleteDraft() {
        guard requireStorageAccess(), requireIdleLauncherSync() else { return }
        guard let id = originalContextID else { return }
        do {
            try store.delete(id: id)
            contexts = try store.load()
            originalContextID = nil
            selectedContextID = nil
            draft = nil
            if let first = contexts.first {
                beginEditing(id: first.id)
            }
        } catch {
            reloadAfterPartialWrite()
            present(error, title: "Couldn’t delete context")
            return
        }

        do {
            try LauncherBundleGenerator().remove(id: id, from: launcherDirectory)
            refreshDiagnostics()
        } catch {
            refreshDiagnostics()
            present(error, title: "Context deleted, but its old launcher couldn’t be removed")
        }
    }

    func testLaunch(_ context: LauncherContext) {
        let existing = contexts.filter { $0.id != originalContextID }
        let issues = ContextValidator.validate(context, among: existing)
        guard issues.isEmpty else {
            presentValidation(issues)
            return
        }

        let result = ContextLauncher().launch(context)
        alert = AppAlert(
            title: result.warnings.isEmpty ? "Launch started" : "Launch completed with warnings",
            message: result.warnings.isEmpty ? "Opened the configured items for \(context.name)." : result.warnings.joined(separator: "\n")
        )
    }

    func completeOnboarding() async {
        guard requireStorageAccess(), requireIdleLauncherSync() else { return }
        do {
            try markSetupPending()
            try store.save(starterContexts)
            contexts = try store.load()
        } catch {
            reloadAfterPartialWrite()
            present(error, title: "Couldn’t finish setup")
            return
        }

        isSynchronizingLaunchers = true
        defer { isSynchronizingLaunchers = false }
        do {
            try await runLauncherSync(for: contexts, includingNew: true)
            try clearSetupPending()
            onboardingIsActive = false
            showsOnboardingCompletion = true
            refreshDiagnostics()
        } catch {
            refreshDiagnostics()
            present(error, title: "Setup is saved, but launcher creation failed")
        }
    }

    func dismissOnboardingCompletion() {
        showsOnboardingCompletion = false
        if let first = contexts.first {
            beginEditing(id: first.id)
        }
    }

    func synchronizeLaunchers() async {
        guard requireIdleLauncherSync() else { return }
        isSynchronizingLaunchers = true
        defer { isSynchronizingLaunchers = false }
        do {
            try await runLauncherSync(for: contexts, includingNew: true)
            refreshDiagnostics()
            alert = AppAlert(title: "Launchers synchronized", message: "Your Spotlight launchers are up to date.")
        } catch {
            present(error, title: "Couldn’t synchronize launchers")
        }
    }

    func refreshDiagnostics() {
        diagnostics = Doctor.run(
            environment: DoctorEnvironment(
                configurationDirectory: supportDirectory,
                launcherDirectory: launcherDirectory,
                launchEnvironment: .system
            ),
            contexts: contexts
        )
    }

    func retryConfigurationLoad() {
        do {
            contexts = try store.load()
            configurationLoadError = nil
            restoreOnboardingState()
            refreshDiagnostics()
            if let first = contexts.first {
                beginEditing(id: first.id)
            }
        } catch {
            configurationLoadError = error.localizedDescription
            present(error, title: "Configuration is still unreadable")
        }
    }

    func importIcon(from source: URL) -> String? {
        guard requireStorageAccess() else { return nil }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        do {
            let directory = supportDirectory.appendingPathComponent("icons", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let destination = directory.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            present(error, title: "Couldn’t import icon")
            return nil
        }
    }

    func presentError(_ title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private func load(arguments: [String]) {
        do {
            contexts = try store.load()
            restoreOnboardingState()
        } catch {
            configurationLoadError = error.localizedDescription
            present(error, title: "Couldn’t load contexts")
        }

        let localState = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        chromeProfiles = (try? ChromeProfileDiscovery.discover(localStateURL: localState)) ?? []
        vscodeInstallation = VSCodeDiscovery.discover()
        refreshDiagnostics()

        guard !needsOnboarding else { return }
        switch arguments {
        case ["--new"]:
            beginNewContext()
        case let values where values.count == 2 && values[0] == "--edit":
            beginEditing(id: values[1])
        case []:
            if let first = contexts.first { beginEditing(id: first.id) }
        default:
            presentError("Unknown startup option", message: "Use --new or --edit <id>.")
            if let first = contexts.first { beginEditing(id: first.id) }
        }
    }

    private func runLauncherSync(for contexts: [LauncherContext], includingNew: Bool) async throws {
        let launcherSync = launcherSync
        try await Task.detached(priority: .userInitiated) {
            try launcherSync(contexts, includingNew)
        }.value
    }

    private func reloadAfterPartialWrite() {
        do {
            contexts = try store.load()
        } catch {
            configurationLoadError = error.localizedDescription
        }
        refreshDiagnostics()
    }

    private func restoreOnboardingState() {
        let setupPending = FileManager.default.fileExists(atPath: setupPendingURL.path)
        onboardingIsActive = OnboardingState.needsOnboarding(contexts: contexts, setupPending: setupPending)
        if setupPending, !contexts.isEmpty {
            starterContexts = contexts
        }
    }

    private func markSetupPending() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Data().write(to: setupPendingURL, options: .atomic)
    }

    private func clearSetupPending() throws {
        if FileManager.default.fileExists(atPath: setupPendingURL.path) {
            try FileManager.default.removeItem(at: setupPendingURL)
        }
    }

    private func requireStorageAccess() -> Bool {
        guard allowsStorageMutations else {
            presentError(
                "Configuration is read-only",
                message: "Context Launcher could not load contexts.json. Fix or restore the file, then choose Retry Load before saving changes."
            )
            return false
        }
        return true
    }

    private func requireIdleLauncherSync() -> Bool {
        guard !isSynchronizingLaunchers else {
            presentError("Launcher update in progress", message: "Wait for the current launcher update to finish.")
            return false
        }
        return true
    }

    private func presentValidation(_ issues: [ValidationIssue]) {
        alert = AppAlert(title: "Check this context", message: issues.map(\.message).joined(separator: "\n"))
    }

    private func present(_ error: Error, title: String) {
        if case let ContextStoreError.validation(issues) = error {
            presentValidation(issues)
        } else {
            alert = AppAlert(title: title, message: error.localizedDescription)
        }
    }
}
