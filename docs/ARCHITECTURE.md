# Context Launcher Architecture

## Goals

Context Launcher is a local-only macOS 13+ utility that turns short context IDs
into Spotlight-searchable applications. Launching one context opens its chosen
Chrome profile and URLs, Visual Studio Code projects, and macOS applications.
Users manage contexts through a native SwiftUI application or a small CLI; they
never need to edit configuration files by hand.

The project uses only Apple platform APIs and the Swift standard library. It
does not require Raycast, Electron, a browser extension, a background process,
or third-party dependencies.

## Package Structure

The repository is a Swift Package Manager project with three products:

- `ContextLauncherKit`: models, validation, persistence, discovery, launch
  planning and execution, launcher generation, diagnostics, and starter data.
- `ContextLauncherApp`: the SwiftUI configuration and first-run application.
- `context`: the command-line interface.

Business logic belongs in `ContextLauncherKit`. The GUI and CLI translate user
intent into library calls and present structured results. Operating-system side
effects sit behind small protocols so core logic can be tested without opening
applications.

The deployment target is macOS 13 Ventura. Installation requires the Xcode
Command Line Tools or Xcode with Swift 6-compatible tooling.

## Local Storage

User data lives outside the repository at:

```text
~/Library/Application Support/ContextLauncher/
├── contexts.json
├── icons/
└── bin/context
```

`contexts.json` is a versioned JSON document written atomically. Reads validate
the whole document and report malformed entries rather than executing them.
Names and subtitles reject ASCII control characters so human-readable CLI
output can never become a machine control channel.
The repository contains only generic starter templates and never commits local
profile identifiers, email addresses, project paths, or application choices.

A context contains:

- a unique lowercase ID made of ASCII letters, digits, and hyphens;
- display name and optional subtitle;
- a built-in SF Symbol or copied local custom icon;
- an optional Chrome profile directory identifier;
- zero or more HTTP or HTTPS URLs;
- zero or more folder or `.code-workspace` paths;
- zero or more `.app` paths.

Display names may repeat. IDs may not. Generated launcher display names are
disambiguated when necessary while the Spotlight launch term remains the ID.

## Spotlight Launcher Architecture

The installer places the main application and generated launchers in the
user's Applications directory:

```text
~/Applications/
├── Context Launcher.app
├── Uni.app
├── Leet.app
├── Work.app
├── Org.app
└── New.app
```

Each generated launcher is a small, valid application bundle containing:

- `Contents/Info.plist` with a unique bundle identifier and display name;
- `Contents/MacOS/launcher`, a tiny executable shim;
- `Contents/Resources/AppIcon.icns`.

The shim invokes the installed CLI with one fixed, validated context ID. It
does not duplicate engine or configuration logic. `New.app` invokes
`context new`, which opens `contextlauncher://new` through Launch Services.
The main application registers that URL scheme and handles new/edit routes in
the existing process when it is already running.

Launcher generation builds in a temporary sibling directory, validates the
result, and atomically replaces the previous bundle. Saving a context creates
or updates its launcher. Deleting a context removes only its known generated
bundle. The installer may ask Spotlight to refresh `~/Applications`, but normal
macOS indexing remains the primary discovery mechanism.

## Chrome Discovery and Launching

Discovery reads only Chrome's `Local State` file under its Application Support
directory. It parses the profile information cache and exposes the directory
identifier, human-readable name, and email when present. It does not read
history, cookies, credentials, tokens, or browser databases, and sends no data
over the network.

Launch execution follows this order:

1. If accessibility exposes exactly one Chrome toolbar avatar whose label
   unambiguously matches the configured profile, focus that window and open
   configured URLs in it through narrowly scoped JXA UI scripting.
2. Otherwise run `/usr/bin/open -na "Google Chrome" --args` with a structured
   `--profile-directory` argument and the validated URLs.
3. If Chrome is absent, return an actionable warning and continue launching
   the remaining context items.

Chrome does not expose a stable public API for mapping every running window to
an on-disk profile. The production adapter therefore declines missing,
localized, inaccessible, duplicate, or otherwise ambiguous profile labels.
The structured `open` command is the intentional supported fallback, and some
Chrome versions or profiles may create another window.

## Visual Studio Code Launching

Each configured folder or `.code-workspace` opens in a separate window. The
engine prefers the `code` command found in standard locations and invokes it
with argument arrays and `--new-window`. If that command is unavailable, it
uses the executable inside `Visual Studio Code.app`. Diagnostics explain how
to install the shell command when neither path works. Missing projects produce
warnings and do not prevent other launch actions.

## Other Applications

The editor uses a native file picker restricted to application bundles.
Applications launch via `NSWorkspace` using standardized file URLs. Present
paths must be actual `.app` bundle directories; missing saved `.app` paths are
retained as actionable warnings. Arbitrary shell strings are never stored or
executed. Present VS Code paths must be directories or `.code-workspace` files;
missing saved paths likewise remain warnings.

## Launch Planning, Validation, and Errors

The engine first converts a validated context into a launch plan, then executes
the plan. Planning is deterministic and side-effect free. This boundary makes
validation, ordering, missing-path behavior, and escaping testable.

All subprocesses use structured executable URLs and argument arrays. Context
IDs, URLs, project paths, application paths, and decoded configuration are
validated at trust boundaries. One failed action does not cancel independent
actions: execution returns a collection of successes and actionable warnings
for the GUI or CLI to present.

Configured URLs require a selected Chrome profile and are otherwise rejected
with an actionable validation issue. A selected profile with zero URLs remains
a valid launch action that focuses the safely identified window or uses the
structured profile fallback.

## Configuration Application

The native SwiftUI application uses a macOS sidebar and detail layout. Its main
view lists contexts with icon, name, subtitle, Chrome profile summary, URL
count, project count, and application count.

The context editor provides:

- name, launch ID, subtitle, and built-in or custom icon controls;
- Chrome enablement and a picker populated from local profile discovery;
- editable, removable, and reorderable URLs, including multi-line paste;
- native folder and `.code-workspace` pickers with reorder and removal;
- a native application picker with removal;
- Save, Cancel, Test Launch, and Delete actions.

First run welcomes the user, reports Chrome and VS Code detection, and creates
generic Uni, Leet, Work, and Org templates. The user assigns profiles and local
project paths during setup. Generic public service URLs may be included, but
personal email addresses and filesystem paths are never source defaults. Setup
ends by generating launchers and showing the Spotlight workflow.

## CLI

The `context` executable and GUI share `ContextLauncherKit`. It supports:

```text
context list
context launch <id>
context new
context edit <id>
context doctor
```

`doctor` reports Chrome and profile discovery, VS Code availability, config and
launcher directories, launcher validity, missing project paths, and broken
application paths. Human-readable output is the public interface; no unstable
machine-readable public output is promised. The installer and uninstaller use
a private `internal-context-ids` command sourced directly from validated
storage and never parse `context list`.

## Installation and Uninstallation

`install.sh` checks the macOS version and Swift toolchain, builds a release
configuration, creates required user directories, assembles the main app
bundle, installs the CLI, initializes starter configuration only when none
exists, atomically marks that starter setup as pending, and generates
launchers. It does not overwrite existing user data or any application bundle
whose exact Context Launcher bundle identifier cannot be verified.

`uninstall.sh` removes installed executables and generated application bundles.
It preserves user configuration and copied icons by default and deletes them
only through an explicit option.

## Testing and QA

Unit and integration tests cover:

- context encoding, decoding, schema versioning, and atomic persistence;
- ID, URL, project, application, and duplicate-ID validation;
- malformed and incomplete Chrome profile metadata;
- deterministic launch plans and missing-path warnings;
- launcher bundle layout, metadata, identifiers, and path handling;
- starter contexts and diagnostic results.

Release verification consists of debug and release builds, the Swift test
suite, CLI smoke tests against temporary storage, launcher bundle inspection,
and installer/uninstaller tests with redirected temporary destinations.

Real Chrome, VS Code, Spotlight indexing, icon rendering, and focus behavior
require a documented manual macOS smoke test. Automated QA will not open the
user's applications or modify their real `~/Applications` directory.

## Privacy and Security

Context Launcher is local-only. It includes no analytics, telemetry, accounts,
cloud sync, tracking, or external API integration. It reads only the minimum
Chrome profile metadata needed for selection. It never reads Chrome history,
cookies, credentials, tokens, or browsing databases.

Configuration is treated as untrusted input. The engine never evaluates shell
text and never interpolates configuration into a command string. Paths and URLs
are validated and passed to platform APIs as structured values.

## Deliberate Scope Limits

The first release omits automatic discovery of likely coding folders, a
menu-bar resident process, cloud synchronization, deep browser-window
deduplication, code signing/notarization automation, and a machine-readable CLI
format. These can be added when demonstrated user needs justify their ongoing
complexity.
