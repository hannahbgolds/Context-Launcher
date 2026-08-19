# Context Launcher Final Fix Report

Date: 2026-08-19
Branch: `context-launcher-implementation`

## Outcome

All two Critical findings, all six Important findings, and the five requested
Minor findings are addressed. The implementation remains native,
dependency-free, and macOS 13+. Automated verification used only temporary,
redirected install/configuration roots. It did not launch the GUI, Chrome, VS
Code, Spotlight workflows, or install into a real user location.

## Finding-to-code and test map

### Critical 1: unrelated application replacement

- `LauncherBundleGenerator.swift` now rejects symlinks and any existing bundle
  whose `CFBundleIdentifier` is not the exact expected
  `dev.contextlauncher.context.<id>`. Removal applies the same ownership rule.
  Renamed display-name launchers remove only other bundles carrying that same
  exact identifier.
- `install.sh` stages and validates the central application and all preview
  launchers before mutating install destinations. `Context Launcher.app`,
  `New.app`, and every context launcher are preflighted for non-symlink
  directory shape and exact identifier before backup/replacement. A collision
  exits with an actionable message and the transaction cleans its locks and
  temporary files without touching the decoy.
- Coverage: `LauncherBundleTests` exercises context/New decoys, symlinks,
  removal collisions, and successful owned replacement; `AppModelTests`
  exercises a GUI synchronization collision; `InstallerSmokeTests.sh`
  exercises central, New, normal-context, and exact-ID symlink decoys plus
  successful owned reinstall and rollback.

### Critical 2: human-output parsing and newline injection

- The CLI now has a private `internal-context-ids` command that prints only
  sorted IDs loaded from the validated `ContextStore`.
- `install.sh` and `uninstall.sh` consume that command and no longer parse
  `context list`. Public human output and private machine output remain
  separate.
- `ContextValidator` rejects every ASCII control character (0...31 and 127) in
  names and subtitles. `ContextStoreError` presents the underlying actionable
  validation message for malformed existing configuration.
- Coverage: CLI smoke verifies sorted ID-only output and malformed-input
  rejection; validation/store tests cover controls and actionable diagnostics;
  installer/uninstaller smoke proves a newline-bearing configuration cannot
  remove an unrelated `victim.app`.

### Important 1: installer-created data bypassed onboarding

- `install.sh` creates starter `contexts.json` and a zero-byte `setup-pending`
  through exclusive same-filesystem hard links only when no configuration
  exists. Both are transaction flags and are removed on rollback.
- Existing configurations are preserved and reinstall does not recreate a
  previously cleared `setup-pending` file.
- `AppModel` restores installer-created starter contexts as the editable
  onboarding draft while the marker exists.
- Coverage: redirected installer smoke checks zero-byte creation and reinstall
  preservation; `AppModelTests.testInstallerInitializedStarterDataKeepsOnboardingActive`
  covers the installed model state.

### Important 2: non-terminating signal traps

- `install.sh` and `scripts/assemble-app.sh` use `EXIT` as the sole cleanup trap
  and explicit terminating HUP/INT/TERM traps returning 129/130/143.
- `Tests/SignalSmokeTests.sh` uses a foreground `exec` controller and child
  watcher so SIGINT is not inherited as ignored by an asynchronous shell job.
  It runtime-tests all three signals for both scripts and checks destination
  cleanup plus install/support lock removal.
- Existing safe uninstaller traps remain and its smoke coverage also executes
  HUP/INT/TERM.

### Important 3: silent Chrome/URL states

- A selected profile with zero URLs now plans a Chrome action, allowing a
  safely identified window to be focused or the structured profile fallback to
  open.
- URLs without a selected Chrome profile are rejected by shared validation;
  editor Save/Test routes surface the model's actionable “Choose a Chrome
  profile” issue, the store rejects malformed existing data, and diagnostics
  now considers profile-only Chrome configuration relevant.
- Present resources are shape-checked; missing resources remain stored and
  become launch/doctor warnings.
- Coverage: `LaunchPlanTests`, `ContextValidationTests`, `ContextStoreTests`,
  and `AppModelTests` cover the valid profile-only state, invalid URL-only
  state, malformed stored data, and actionable model rejection.

### Important 4: new/edit delivery to an already-running application

- `ContextLauncherRoute.swift` defines and strictly parses
  `contextlauncher://new` and `contextlauncher://edit/<validated-id>`.
- CLI `new`/`edit` invoke `/usr/bin/open` with the application bundle ID and
  route URL, without `--args` or a concurrent-instance flag.
- `ContextLauncherApp` handles `.onOpenURL` and routes into the existing
  `AppModel`; onboarding cannot be bypassed by an incoming route.
- `assemble-app.sh` registers the scheme in the central app plist.
- Coverage: route round-trip/rejection tests, AppModel route state tests, and
  installer/plist verification of the assembled URL scheme.

### Important 5: production Chrome adapter

- `ChromeAppleScriptWindowTargeter` is supplied by the production
  `ContextLauncher` initializer. It resolves the configured directory ID to a
  unique discovered display name and uses JXA accessibility inspection only
  when exactly one Chrome window exposes an exact toolbar avatar/profile label.
- Missing permission, localization mismatch, duplicate profile names,
  ambiguous windows, and script errors return/behave as not targeted. The
  engine then intentionally uses structured `/usr/bin/open -na ... --args
  --profile-directory=<id>` fallback. It never guesses a window.
- The architecture and README describe this as best effort and document the
  unavoidable Chrome limitation accurately.
- Coverage: fake-runner tests check profile discovery mapping, structured URL
  arguments, and refusal of unknown/ambiguous profiles; real `osascript` tests
  execute the runner, parse the production script's no-argument safe path, and
  verify nonzero reporting. No real Chrome instance was contacted.

### Important 6: subprocess exit status

- `ProcessRunner` now waits for short-lived commands and throws an executable-
  and-status-specific error on nonzero termination. Production GUI applications
  still launch through `NSWorkspace`, so no GUI executable is waited on.
- `OsaScriptRunner` likewise waits and reports stderr/status.
- Coverage: real `/bin/sh` success/nonzero tests plus `osascript` success and
  failure tests; existing fake runners verify later independent actions still
  proceed after errors.

### Minors

- `ContextListView` hides New and Diagnostics while onboarding, completion,
  recovery, or synchronization makes them unavailable; AppModel state coverage
  asserts the onboarding case.
- Manual synchronization refreshes diagnostics in both success and catch
  paths; AppModel coverage simulates a partial sync failure and verifies the
  refreshed launcher diagnosis.
- `LauncherBundleNaming` derives filenames from sanitized display names,
  disambiguates duplicates/reserved central/New names with the exact ID, and
  prevents leading-dot launchers from becoming hidden. IDs and bundle IDs remain
  launch keys. Generator/Doctor/AppModel/CLI all use the shared naming rule.
- Existing projects must be directories or regular `.code-workspace` files;
  existing applications must be non-symlink `.app` directories. Missing paths
  remain valid at save time and produce plan/doctor warnings.
- Generated starter launchers and docs consistently use `Leet.app`; `New.app`
  remains exact.

## TDD evidence

The pre-fix baseline passed 35 tests. Focused tests were introduced before
their implementations and observed failing for the relevant missing behavior,
including bundle/display-path mismatch, decoy replacement, reserved `new`,
control characters, ID-only CLI absence, URL-only acceptance, profile-only
planning omission, route parsing, stale diagnostics, resource shape, and
nonzero process status. After implementation, the expanded suite passes 59
tests. A final self-review added the leading-dot display-name expectation before
the sanitizer change; the Documents-mounted worktree hit the environmental
Swift driver race before executing that focused test, while the final clean
isolated run executed and passed it.

## Verification commands and observed output

Commands below were run against the final exact source contents. Swift commands
used local module caches under `/private/tmp` and `--disable-sandbox` because
this managed environment cannot write SwiftPM's normal user caches.

1. Full test suite:

   `swift test --disable-sandbox`

   Final clean isolated-copy output: `Build complete!`; `Executed 59 tests,
   with 0 failures (0 unexpected)`; exit 0.

2. Release build:

   `swift build --disable-sandbox -c release`

   Output: `Build complete! (7.65s)`; exit 0.

3. CLI smoke:

   `sh Tests/CLISmokeTests.sh .build/release/context`

   Output included `No contexts configured. Run 'context new' to create one.`
   and the expected temporary config-directory diagnostic; exit 0.

4. Installer/assembler signal smoke:

   `sh Tests/SignalSmokeTests.sh`

   No stdout/stderr; exit 0. Runtime assertions covered HUP=129, INT=130,
   TERM=143 for both scripts, cleanup, and lock removal.

5. Redirected installer/uninstaller matrix:

   `sh -x Tests/InstallerSmokeTests.sh`

   Exit 0. The final trace showed every decoy/ownership assertion, fresh and
   owned reinstall, setup marker, URL scheme, rollback, lock, signal, purge,
   and injection case succeeding. Expected malformed-config stderr at the end:
   `Name must not contain ASCII control characters.`; the victim marker was
   then asserted unchanged. The suite prepended a no-op temporary `mdimport`,
   so it did not touch the real Spotlight index.

6. Central and generated launcher plist lint:

   A temporary redirected assembly plus `internal-generate-all`, followed by
   `find <temporary-install> -name Info.plist -exec plutil -lint {} +`.

   Output: `Context Launcher.app/Contents/Info.plist: OK`,
   `Sample.app/Contents/Info.plist: OK`, and
   `New.app/Contents/Info.plist: OK`; exit 0.

7. Static hygiene:

   `git diff --check` — no output, exit 0.
   `sh -n install.sh uninstall.sh scripts/assemble-app.sh Tests/CLISmokeTests.sh Tests/InstallerSmokeTests.sh Tests/SignalSmokeTests.sh`
   — no output, exit 0.
   Privacy grep for personal-name/email/home-path patterns, excluding historical
   plan/report material — no matches, exit 0.

## Environmental caveat

The Documents-mounted worktree's standard Swift build twice reported unrelated,
unchanged source inputs as “modified during the build” (`IconRenderer.swift`,
then `DiagnosticsView.swift`) even after cleaning only `.build`; a non-batch
attempt later reported the same race on `AppModelTests.swift`, and an incremental
link reported an object file modified. Git status/diff and source timestamps
remained stable. A serialized non-batch worktree run passed 59/59. To obtain a
clean standard-command result, the exact source tree (excluding only `.git` and
`.build`) was copied to a fresh directory under `/private/tmp`; the unmodified
standard `swift test --disable-sandbox` and release build both passed there.
No source or user data was cleaned to work around the driver issue.

An initial silent installer matrix was manually interrupted after six minutes
because its progress was not observable. The traced rerun demonstrated that it
was spending roughly 30 seconds per scenario compiling five real temporary
launcher shims, not hanging, and completed with exit 0.

## Manual limitations

- No real user installation, Launch Services application opening, Spotlight
  discovery, GUI interaction, Chrome window/profile targeting, VS Code launch,
  or other application launch was performed, as required.
- URL scheme registration and routing are covered by plist lint, parser/model
  tests, and the CLI's structured implementation, but delivery by a live macOS
  Launch Services session remains manual acceptance.
- Chrome's accessibility surface varies with Chrome version, localization, and
  permission state. Production deliberately falls back unless it sees one exact,
  unambiguous match; a live Chrome acceptance check remains manual.

## Self-review

- Re-read the architecture and final review against the final diff.
- Verified every destructive bundle path has an exact-identifier/non-symlink
  preflight before backup, replacement, or removal.
- Verified installer manifests originate from validated private ID output and
  generated plist identifiers, never human text.
- Verified rollback flags are set before each mutation and the corrected smoke
  fixture reaches the forced post-copy failure while preserving owned plist
  metadata.
- Verified process arguments remain arrays, URL routes validate IDs, the Chrome
  adapter declines ambiguity, and independent launch actions retain warning
  behavior.
- Verified generated filenames cannot collide with exact `New.app`/central
  names, duplicates are deterministic, and missing resources remain warnings.
- No unresolved Critical, Important, or requested straightforward Minor finding
  remains. Remaining risk is limited to the explicitly manual macOS/Chrome
  acceptance surfaces above.
