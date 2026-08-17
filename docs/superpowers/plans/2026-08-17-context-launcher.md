# Context Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, local-only macOS utility that creates Spotlight-searchable context launchers and manages them through one SwiftUI app and shared CLI.

**Architecture:** A dependency-free Swift package exposes `ContextLauncherKit` to a SwiftUI executable and a CLI executable. The shared library validates and atomically stores contexts, discovers local applications and Chrome profiles, creates deterministic launch plans, executes structured process calls, generates application bundles, and reports diagnostics.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, AppKit, Foundation, XCTest, POSIX shell glue

**Spec:** `docs/ARCHITECTURE.md`

## Global Constraints

- Target macOS 13 Ventura and newer.
- Use only Apple platform APIs and the Swift standard library; add no third-party dependencies.
- Keep all user configuration under `~/Library/Application Support/ContextLauncher/` and out of Git.
- Store no personal email address, Chrome profile identifier, or project/application path in source defaults.
- Never evaluate shell text or interpolate configuration into command strings; use executable URLs and argument arrays.
- Read only Chrome's `Local State` metadata, never history, cookies, credentials, tokens, or browser databases.
- Keep Context Launcher local-only with no telemetry, analytics, accounts, tracking, cloud sync, or external APIs.
- A failed launch action must not prevent independent actions from running.
- Do not modify the real user installation during automated tests; redirect all paths to temporary directories.

---

### Task 1: Package, Domain Model, and Validation

**Files:**
- Create: `Package.swift`
- Create: `Sources/ContextLauncherKit/Model/Context.swift`
- Create: `Sources/ContextLauncherKit/Model/Validation.swift`
- Create: `Tests/ContextLauncherKitTests/ContextValidationTests.swift`

**Interfaces:**
- Produces: `LauncherContext`, `ContextIcon`, `ChromeProfile`, `ValidationIssue`, `ContextValidator.validate(_:among:)`, and `URL.validatedWebURL(_:)`.
- Consumes: Foundation only.

- [ ] **Step 1: Write failing model and validation tests**

```swift
func testRoundTripContext() throws {
    let original = LauncherContext(id: "leet", name: "Leet", subtitle: "Practice", icon: .symbol("chevron.left.forwardslash.chevron.right"), chromeProfileID: "Profile 1", urls: [URL(string: "https://leetcode.com/")!], vscodeProjects: [URL(fileURLWithPath: "/tmp/leetcode-solutions")], applications: [])
    XCTAssertEqual(try JSONDecoder().decode(LauncherContext.self, from: JSONEncoder().encode(original)), original)
}

func testValidationRejectsUnsafeIDInvalidURLAndDuplicateID() {
    var context = LauncherContext(id: "Leet; rm", name: "Leet")
    context.urls = [URL(string: "file:///etc/passwd")!]
    let issues = ContextValidator.validate(context, among: [LauncherContext(id: "leet", name: "Existing")])
    XCTAssertTrue(issues.contains { $0.field == .id })
    XCTAssertTrue(issues.contains { $0.field == .urls })
}
```

- [ ] **Step 2: Run tests and verify the package/test target is absent**

Run: `swift test --filter ContextValidationTests`
Expected: FAIL because `Package.swift` and the tested types do not exist.

- [ ] **Step 3: Create the package and minimal domain types**

```swift
public enum ContextIcon: Codable, Equatable, Sendable {
    case symbol(String)
    case custom(String)
}

public struct LauncherContext: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var icon: ContextIcon
    public var chromeProfileID: String?
    public var urls: [URL]
    public var vscodeProjects: [URL]
    public var applications: [URL]
}

public enum ValidationField: String, Sendable { case id, name, urls, vscodeProjects, applications }
public struct ValidationIssue: Error, Equatable, Sendable {
    public let field: ValidationField
    public let message: String
}
```

Implement `ContextValidator.validate(_:among:)` with `^[a-z0-9]+(?:-[a-z0-9]+)*$`, non-empty trimmed names, unique IDs, HTTP/HTTPS URL schemes, file URLs for projects, and `.app` file URLs for applications.

- [ ] **Step 4: Run the focused and full tests**

Run: `swift test --filter ContextValidationTests && swift test`
Expected: PASS.

- [ ] **Step 5: Commit the tested domain foundation**

```bash
git add Package.swift Sources/ContextLauncherKit/Model Tests/ContextLauncherKitTests/ContextValidationTests.swift
git commit -m "Build context model and validation"
```

### Task 2: Versioned Atomic Context Storage and Starter Data

**Files:**
- Create: `Sources/ContextLauncherKit/Storage/ContextStore.swift`
- Create: `Sources/ContextLauncherKit/Storage/StarterContexts.swift`
- Create: `Tests/ContextLauncherKitTests/ContextStoreTests.swift`

**Interfaces:**
- Consumes: `LauncherContext`, `ContextValidator` from Task 1.
- Produces: `ContextDocument`, `ContextStore.init(fileURL:)`, `load()`, `save(_:)`, `upsert(_:)`, `delete(id:)`, and `StarterContexts.all`.

- [ ] **Step 1: Write failing persistence tests**

```swift
func testSaveLoadAndDuplicateRejection() throws {
    let file = temporaryDirectory.appendingPathComponent("contexts.json")
    let store = ContextStore(fileURL: file)
    try store.save([LauncherContext(id: "leet", name: "Leet")])
    XCTAssertEqual(try store.load().map(\.id), ["leet"])
    XCTAssertThrowsError(try store.save([LauncherContext(id: "leet", name: "One"), LauncherContext(id: "leet", name: "Two")]))
}

func testStarterContextsContainNoPersonalValues() throws {
    let data = try JSONEncoder().encode(StarterContexts.all)
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("@"))
    XCTAssertFalse(text.contains("/Users/"))
    XCTAssertEqual(Set(StarterContexts.all.map(\.id)), ["uni", "leet", "work", "org"])
}
```

- [ ] **Step 2: Run tests and confirm missing storage symbols**

Run: `swift test --filter ContextStoreTests`
Expected: FAIL because `ContextStore` and `StarterContexts` do not exist.

- [ ] **Step 3: Implement validated atomic persistence**

```swift
public struct ContextDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var contexts: [LauncherContext]
}

public final class ContextStore: @unchecked Sendable {
    public let fileURL: URL
    public func load() throws -> [LauncherContext]
    public func save(_ contexts: [LauncherContext]) throws
    public func upsert(_ context: LauncherContext) throws
    public func delete(id: String) throws
}
```

Create the parent directory, encode sorted/pretty JSON, write to a sibling temporary file with `.atomic`, then replace/move it into place. Validate every context and reject duplicate IDs before writing. `load()` returns an empty array for a missing file and rejects unsupported versions.

- [ ] **Step 4: Run storage and full tests**

Run: `swift test --filter ContextStoreTests && swift test`
Expected: PASS.

- [ ] **Step 5: Commit storage**

```bash
git add Sources/ContextLauncherKit/Storage Tests/ContextLauncherKitTests/ContextStoreTests.swift
git commit -m "Add atomic local context storage"
```

### Task 3: Chrome and VS Code Discovery

**Files:**
- Create: `Sources/ContextLauncherKit/Discovery/ChromeProfileDiscovery.swift`
- Create: `Sources/ContextLauncherKit/Discovery/VSCodeDiscovery.swift`
- Create: `Tests/ContextLauncherKitTests/DiscoveryTests.swift`

**Interfaces:**
- Consumes: `ChromeProfile` from Task 1.
- Produces: `ChromeProfileDiscovery.parse(localStateData:)`, `discover(localStateURL:)`, `VSCodeInstallation`, and `VSCodeDiscovery.discover(fileManager:environment:)`.

- [ ] **Step 1: Write failing metadata parsing and tool discovery tests**

```swift
func testParsesHumanReadableChromeProfiles() throws {
    let json = #"{"profile":{"info_cache":{"Default":{"name":"Hannah Personal","user_name":"person@example.test"},"Profile 2":{"name":"Vertalis"}}}}"#.data(using: .utf8)!
    let profiles = try ChromeProfileDiscovery.parse(localStateData: json)
    XCTAssertEqual(profiles.map(\.directoryID), ["Default", "Profile 2"])
    XCTAssertEqual(profiles.first?.email, "person@example.test")
    XCTAssertNil(profiles.last?.email)
}

func testMalformedChromeMetadataReturnsTypedError() {
    XCTAssertThrowsError(try ChromeProfileDiscovery.parse(localStateData: Data("{".utf8)))
}
```

- [ ] **Step 2: Run tests and verify discovery APIs are absent**

Run: `swift test --filter DiscoveryTests`
Expected: FAIL because the discovery types do not exist.

- [ ] **Step 3: Implement minimal local discovery**

Decode only `profile.info_cache` into private `Decodable` structs, sort by directory ID, and tolerate absent `name`/`user_name` values. Detect Chrome at `/Applications/Google Chrome.app` and `~/Applications/Google Chrome.app`. Detect `code` from `PATH`, `/usr/local/bin/code`, `/opt/homebrew/bin/code`, or the executable inside Visual Studio Code.app.

```swift
public struct VSCodeInstallation: Equatable, Sendable {
    public let executableURL: URL
    public let usesShellCommand: Bool
}
```

- [ ] **Step 4: Run discovery and full tests**

Run: `swift test --filter DiscoveryTests && swift test`
Expected: PASS.

- [ ] **Step 5: Commit discovery**

```bash
git add Sources/ContextLauncherKit/Discovery Tests/ContextLauncherKitTests/DiscoveryTests.swift
git commit -m "Discover Chrome profiles and VS Code"
```

### Task 4: Deterministic Launch Planning and Execution

**Files:**
- Create: `Sources/ContextLauncherKit/Launch/LaunchPlan.swift`
- Create: `Sources/ContextLauncherKit/Launch/ProcessRunning.swift`
- Create: `Sources/ContextLauncherKit/Launch/ContextLauncher.swift`
- Create: `Tests/ContextLauncherKitTests/LaunchPlanTests.swift`

**Interfaces:**
- Consumes: validated `LauncherContext`, `VSCodeInstallation`.
- Produces: `LaunchAction`, `LaunchPlan`, `LaunchPlanner.plan(for:environment:)`, `ProcessRunning.run(executable:arguments:)`, `LaunchResult`, and `ContextLauncher.launch(_:)`.

- [ ] **Step 1: Write failing launch-plan tests with spaces and missing paths**

```swift
func testPlanKeepsArgumentsStructuredAndProjectsSeparate() throws {
    let context = LauncherContext(id: "work", name: "Work", chromeProfileID: "Profile 2", urls: [URL(string: "https://example.test/a?b=c")!], vscodeProjects: [URL(fileURLWithPath: "/tmp/backend one"), URL(fileURLWithPath: "/tmp/frontend")])
    let plan = LaunchPlanner.plan(for: context, environment: fixtureEnvironment)
    XCTAssertEqual(plan.actions.filter { if case .vscode = $0 { true } else { false } }.count, 2)
    XCTAssertTrue(plan.actions.contains(.vscode(executable: fixtureCodeURL, arguments: ["--new-window", "/tmp/backend one"])))
}

func testMissingItemsBecomeWarningsWithoutRemovingValidActions() {
    let plan = LaunchPlanner.plan(for: contextWithOneMissingAndOneExistingProject, environment: fixtureEnvironment)
    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(plan.warnings.count, 1)
}
```

- [ ] **Step 2: Run tests and verify planning symbols are absent**

Run: `swift test --filter LaunchPlanTests`
Expected: FAIL because launch planning is not implemented.

- [ ] **Step 3: Implement planning and structured execution**

```swift
public enum LaunchAction: Equatable, Sendable {
    case chrome(executable: URL, profileID: String, urls: [URL])
    case vscode(executable: URL, arguments: [String])
    case application(URL)
}

public struct LaunchPlan: Equatable, Sendable {
    public var actions: [LaunchAction]
    public var warnings: [String]
}
```

Use `Process.executableURL` and `Process.arguments` for Chrome and VS Code. Use `NSWorkspace.openApplication(at:configuration:)` for applications. Continue after each error and append it to `LaunchResult.warnings`. Start Chrome with `/usr/bin/open -na <Chrome.app> --args --profile-directory=<id> <urls>`; isolate the optional running-window AppleScript adapter so failure falls back to the structured open command.

- [ ] **Step 4: Run launch and full tests**

Run: `swift test --filter LaunchPlanTests && swift test`
Expected: PASS.

- [ ] **Step 5: Commit the core launcher**

```bash
git add Sources/ContextLauncherKit/Launch Tests/ContextLauncherKitTests/LaunchPlanTests.swift
git commit -m "Plan and execute context launches"
```

### Task 5: Spotlight Application Bundle and Icon Generation

**Files:**
- Create: `Sources/ContextLauncherKit/LauncherBundle/LauncherBundleGenerator.swift`
- Create: `Sources/ContextLauncherKit/LauncherBundle/IconRenderer.swift`
- Create: `Tests/ContextLauncherKitTests/LauncherBundleTests.swift`

**Interfaces:**
- Consumes: `LauncherContext`, installed CLI URL, launcher destination URL.
- Produces: `LauncherBundleGenerator.generate(for:cliURL:in:)`, `generateNewLauncher(cliURL:in:)`, `remove(id:from:)`, and `IconRenderer.render(_:destination:)`.

- [ ] **Step 1: Write failing bundle metadata and escaping tests**

```swift
func testGeneratedBundleHasValidMetadataAndLiteralArguments() throws {
    let context = LauncherContext(id: "leet", name: "Leet")
    let bundle = try generator.generate(for: context, cliURL: URL(fileURLWithPath: "/tmp/bin with space/context"), in: temporaryDirectory)
    let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))!
    XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Leet")
    XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.contextlauncher.context.leet")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/launcher").path))
}

func testInvalidIDCannotGenerateBundle() {
    XCTAssertThrowsError(try generator.generate(for: LauncherContext(id: "../bad", name: "Bad"), cliURL: cliURL, in: temporaryDirectory))
}
```

- [ ] **Step 2: Run tests and verify generator is absent**

Run: `swift test --filter LauncherBundleTests`
Expected: FAIL because launcher generation types do not exist.

- [ ] **Step 3: Implement atomic bundles and local icon rendering**

Generate a temporary `.app`, serialize `Info.plist` using `PropertyListSerialization`, and compile a tiny Swift shim with `swiftc` whose CLI path and context ID are emitted as escaped Swift string literals. Render SF Symbols into PNG representations with AppKit and create `.icns` with `/usr/bin/iconutil`; copy custom images into the same local conversion pipeline. Validate the completed bundle before atomically replacing a previous generated bundle.

- [ ] **Step 4: Run bundle and full tests**

Run: `swift test --filter LauncherBundleTests && swift test`
Expected: PASS and no files outside the test temporary directory.

- [ ] **Step 5: Commit Spotlight bundle generation**

```bash
git add Sources/ContextLauncherKit/LauncherBundle Tests/ContextLauncherKitTests/LauncherBundleTests.swift
git commit -m "Generate Spotlight launcher bundles"
```

### Task 6: CLI and Diagnostics

**Files:**
- Create: `Sources/context/main.swift`
- Create: `Sources/ContextLauncherKit/Diagnostics/Doctor.swift`
- Create: `Tests/ContextLauncherKitTests/DoctorTests.swift`
- Create: `Tests/CLISmokeTests.sh`

**Interfaces:**
- Consumes: store, launcher, discovery, and bundle generator from Tasks 2-5.
- Produces: `Doctor.run(environment:contexts:) -> [Diagnostic]` and CLI commands `list`, `launch`, `new`, `edit`, `doctor`.

- [ ] **Step 1: Write failing doctor and CLI smoke tests**

```swift
func testDoctorReportsMissingConfiguredPaths() {
    let diagnostics = Doctor.run(environment: fixtureEnvironment, contexts: [contextWithMissingProjectAndApplication])
    XCTAssertTrue(diagnostics.contains { $0.code == "project.missing" })
    XCTAssertTrue(diagnostics.contains { $0.code == "application.missing" })
}
```

```sh
CONTEXT_LAUNCHER_HOME="$TMPDIR/config" "$BIN" list | grep 'No contexts configured'
CONTEXT_LAUNCHER_HOME="$TMPDIR/config" "$BIN" doctor | grep 'Config directory'
test "$(CONTEXT_LAUNCHER_HOME="$TMPDIR/config" "$BIN" launch absent; echo $?)" != 0
```

- [ ] **Step 2: Run tests and verify CLI target is absent**

Run: `swift test --filter DoctorTests && sh Tests/CLISmokeTests.sh .build/debug/context`
Expected: FAIL because `Doctor` and the CLI binary do not exist.

- [ ] **Step 3: Implement diagnostics and explicit CLI parsing**

Use a small `switch Array(CommandLine.arguments.dropFirst())` parser. `new` opens the installed app with `--new`; `edit <id>` uses `--edit <id>`. Unknown commands and missing IDs print usage to stderr and exit nonzero. `CONTEXT_LAUNCHER_HOME` may redirect storage only for testing and development.

```swift
public struct Diagnostic: Equatable, Sendable {
    public enum Status: String, Sendable { case pass, warning, failure }
    public let code: String
    public let status: Status
    public let message: String
}
```

- [ ] **Step 4: Run unit and CLI smoke tests**

Run: `swift build && swift test && sh Tests/CLISmokeTests.sh .build/debug/context`
Expected: PASS.

- [ ] **Step 5: Commit CLI and doctor**

```bash
git add Sources/context Sources/ContextLauncherKit/Diagnostics Tests/ContextLauncherKitTests/DoctorTests.swift Tests/CLISmokeTests.sh
git commit -m "Add context CLI and doctor diagnostics"
```

### Task 7: Native Configuration UI and First-Run Setup

**Files:**
- Create: `Sources/ContextLauncherApp/ContextLauncherApp.swift`
- Create: `Sources/ContextLauncherApp/AppModel.swift`
- Create: `Sources/ContextLauncherApp/Views/ContextListView.swift`
- Create: `Sources/ContextLauncherApp/Views/ContextEditorView.swift`
- Create: `Sources/ContextLauncherApp/Views/OnboardingView.swift`
- Create: `Sources/ContextLauncherApp/Views/DiagnosticsView.swift`
- Create: `Tests/ContextLauncherKitTests/StarterContextTests.swift`

**Interfaces:**
- Consumes: all shared-library APIs from Tasks 1-6.
- Produces: `ContextLauncherApp` executable supporting default, `--new`, and `--edit <id>` modes.

- [ ] **Step 1: Add failing starter/onboarding state tests**

```swift
func testFirstRunNeedsOnboardingOnlyWithoutStoredContexts() throws {
    let empty = try ContextStore(fileURL: missingFile).load()
    XCTAssertTrue(OnboardingState.needsOnboarding(contexts: empty))
    XCTAssertFalse(OnboardingState.needsOnboarding(contexts: StarterContexts.all))
}
```

- [ ] **Step 2: Run tests and verify onboarding API is absent**

Run: `swift test --filter StarterContextTests`
Expected: FAIL because onboarding state is not implemented.

- [ ] **Step 3: Implement the minimal native UI**

Create an `@MainActor ObservableObject AppModel` that loads contexts/profiles/diagnostics and owns save, delete, test-launch, and launcher-sync operations. Use `NavigationSplitView`, `List`, `Form`, `Table`/rows, `fileImporter`, native alerts, and SF Symbols. The editor includes name/ID/subtitle/icon, Chrome toggle/profile picker, URL add/remove/reorder/multi-line paste, project picker, application picker, and Save/Cancel/Test Launch/Delete. On empty storage, present onboarding, discovery results, editable starter templates, and completion instructions. Parse `--new` and `--edit` at startup.

- [ ] **Step 4: Build all targets and run tests**

Run: `swift build && swift test`
Expected: PASS with both `ContextLauncherApp` and `context` executables built.

- [ ] **Step 5: Commit the configuration app**

```bash
git add Sources/ContextLauncherApp Sources/ContextLauncherKit/Storage/StarterContexts.swift Tests/ContextLauncherKitTests/StarterContextTests.swift
git commit -m "Build native context configuration app"
```

### Task 8: Installer, Uninstaller, and App Assembly

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`
- Create: `scripts/assemble-app.sh`
- Create: `scripts/generate-apps.sh`
- Create: `Tests/InstallerSmokeTests.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: release `ContextLauncherApp`, `context`, starter storage, and launcher generation.
- Produces: installable `Context Launcher.app`, CLI, starter launchers, and reversible uninstaller.

- [ ] **Step 1: Write a failing redirected installation smoke test**

```sh
INSTALL_ROOT="$TMPDIR/install" CONTEXT_LAUNCHER_HOME="$TMPDIR/support" ./install.sh --skip-build
test -x "$TMPDIR/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
test -x "$TMPDIR/support/bin/context"
test -f "$TMPDIR/install/New.app/Contents/Info.plist"
INSTALL_ROOT="$TMPDIR/install" CONTEXT_LAUNCHER_HOME="$TMPDIR/support" ./uninstall.sh
test ! -e "$TMPDIR/install/Context Launcher.app"
test -f "$TMPDIR/support/contexts.json"
```

- [ ] **Step 2: Run the smoke test and verify scripts are absent**

Run: `sh Tests/InstallerSmokeTests.sh`
Expected: FAIL because `install.sh` does not exist.

- [ ] **Step 3: Implement safe installation scripts**

Use `set -eu`, quoted absolute paths, `mktemp -d`, and `trap` cleanup. Detect macOS 13+ and `swift`; build release unless `--skip-build`; assemble `Info.plist` without external template tools; copy binaries; initialize contexts only when absent; run `context internal-generate-all`; and optionally run `mdimport` on generated bundles. `uninstall.sh` removes only Context Launcher binaries and bundles recorded/generated from validated context IDs. Preserve support data unless `--purge-data` is explicitly passed.

- [ ] **Step 4: Run installer tests and release build**

Run: `swift build -c release && sh Tests/InstallerSmokeTests.sh`
Expected: PASS and the temporary configuration remains after default uninstall.

- [ ] **Step 5: Commit packaging**

```bash
git add install.sh uninstall.sh scripts Tests/InstallerSmokeTests.sh .gitignore
git commit -m "Package Context Launcher for user installation"
```

### Task 9: Public Documentation, Assets, and Final QA

**Files:**
- Modify: `README.md`
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `assets/default-icons/README.md`
- Create: `docs/MANUAL_QA.md`

**Interfaces:**
- Consumes: completed application and commands.
- Produces: public GitHub documentation and a repeatable release checklist.

- [ ] **Step 1: Replace the placeholder README and add project policies**

Document the opening `⌘ Space → work → ↵` example, screenshot placeholder, prerequisites, one-command install, first-run setup, context editing, Chrome discovery and limitation, VS Code behavior, CLI commands, troubleshooting, privacy, architecture link, development commands, uninstall behavior, and no-personal-data policy. Add the unmodified MIT license text and concise contribution instructions.

- [ ] **Step 2: Add the exact manual acceptance checklist**

```text
1. Configure `leet` with a detected personal Chrome profile.
2. Add https://leetcode.com/ and select a local leetcode-solutions folder.
3. Save and verify ~/Applications/Leet.app exists.
4. Launch Leet.app and verify the chosen Chrome profile and URL.
5. Verify the folder opens in a separate VS Code window.
6. Search Spotlight for `leet` and verify the custom launcher icon/result.
7. Repeat while Chrome and VS Code are already running and record duplicate-window behavior.
```

- [ ] **Step 3: Run static privacy and repository checks**

Run: `git grep -nE 'hannah|@gmail|@vertalis|/Users/' -- ':!docs/superpowers/plans/*' ':!docs/ARCHITECTURE.md' || true`
Expected: no personal values or hard-coded user paths in product source, tests, scripts, or public docs.

Run: `git diff --check && swift package describe >/dev/null`
Expected: PASS.

- [ ] **Step 4: Run complete debug/release verification**

Run: `swift test && swift build -c release && sh Tests/CLISmokeTests.sh .build/release/context && sh Tests/InstallerSmokeTests.sh`
Expected: every command exits 0.

- [ ] **Step 5: Inspect built bundle metadata and tree**

Run: `find . -path ./.git -prune -o -type f -print | sort && plutil -lint "$TMPDIR/context-launcher-qa/Context Launcher.app/Contents/Info.plist"`
Expected: all documented source files are present and the generated plist is valid.

- [ ] **Step 6: Commit documentation and QA artifacts**

```bash
git add README.md LICENSE CONTRIBUTING.md assets docs/MANUAL_QA.md
git commit -m "Document and verify Context Launcher"
```

- [ ] **Step 7: Record final status**

Run: `git status --short --branch && git log --oneline --decorate -10`
Expected: clean working tree with the implementation commits on the current branch.
