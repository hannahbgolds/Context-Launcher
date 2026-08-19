# Context Launcher

Context Launcher turns short context IDs into Spotlight-searchable macOS apps.

```
⌘ Space → work → ↵
```

That can open the Chrome profile, URLs, Visual Studio Code projects, and macOS
applications you saved in the `work` context.

<!-- Screenshot placeholder: add a redacted Context Launcher configuration screenshot here. -->

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools or Xcode with a Swift 6-compatible toolchain
- Google Chrome, if you want Chrome-profile launches
- Visual Studio Code, if you want project launches

Chrome and VS Code are optional. Context Launcher can still launch the other
items in a context when either one is unavailable.

## Install

From a clone of this repository, run:

```sh
./install.sh
```

The installer builds a release binary and installs:

- `~/Applications/Context Launcher.app`
- generated launcher apps such as `~/Applications/work.app` and `~/Applications/New.app`
- configuration and the CLI under `~/Library/Application Support/ContextLauncher/`

It creates generic `uni`, `leet`, `work`, and `org` starter contexts only when
no configuration exists. Existing configuration is left in place.

## First run and context editing

Open **Context Launcher** from `~/Applications`. On first run, the setup screen
shows Chrome-profile and VS Code discovery, then lets you tailor the generic
starter contexts before creating their launchers.

To create or edit a context, choose its name in the sidebar or open **New**.
Set a display name, a lowercase launch ID, optional subtitle, and either an SF
Symbol or a local custom image. A launch ID uses lowercase letters, numbers,
and single hyphens; it must be unique. Saving a context creates or updates its
matching Spotlight launcher. Deleting a context removes its matching launcher.

Add HTTP or HTTPS URLs, folders or `.code-workspace` files, and existing
`.app` bundles. The editor's **Test Launch** button runs the pending setup
without saving it first. **Diagnostics** reports unavailable profiles,
applications, projects, and launcher bundles.

## Chrome and VS Code

Chrome profile discovery reads Chrome's local `Local State` metadata and lists
the profile directory name, display name, and email when Chrome provides it.
It does not read browsing history, cookies, credentials, tokens, or browser
databases.

Chrome has no stable public API for routing every launch to an existing window
for a particular profile. Context Launcher starts Chrome with the selected
profile directory and configured URLs; Chrome or macOS may reuse a window or
create another one, especially when Chrome is already running. Treat
duplicate-window behavior as a Chrome-version-and-profile-dependent
limitation.

Every saved folder or `.code-workspace` is opened in a separate VS Code window
using `code --new-window`. Context Launcher looks for the `code` command in
your `PATH`, common shell-command locations, and the Visual Studio Code app
bundle. If none is found, it reports a warning and continues with the other
items.

## CLI

The installed CLI is at:

```text
~/Library/Application Support/ContextLauncher/bin/context
```

Use its full path, or add that `bin` directory to your shell `PATH`:

```sh
context list
context launch <id>
context new
context edit <id>
context doctor
```

`list` shows configured IDs, `launch` opens a saved context, `new` opens the
configuration app ready to create one, `edit` opens an existing context, and
`doctor` prints human-readable diagnostics. The CLI does not promise a
machine-readable output format. `internal-generate-all` and
`internal-owned-icons` are installer internals, not public commands.

## Troubleshooting

- Run `context doctor` after moving a project, an application, or an installed
  launcher.
- If no Chrome profile appears, make sure Chrome has been opened at least once
  and select a discovered profile in the editor.
- If VS Code is unavailable, install Visual Studio Code or its `code` shell
  command, then open Diagnostics again.
- If Spotlight does not find a launcher right away, verify it exists in
  `~/Applications` and allow normal macOS indexing time.
- If a launcher fails, reopen Context Launcher, save its context again, and
  review Diagnostics.

## Privacy

Context Launcher is local-only: it has no analytics, telemetry, accounts,
cloud sync, tracking, or external API integration. The app itself does not
send your configuration anywhere. Launching a URL still asks your chosen
browser to visit that URL.

Your contexts, copied custom icons, and installed CLI live in your local
Application Support directory. This repository contains only generic starter
templates: it does not include personal profile identifiers, email addresses,
filesystem paths, project names, or application selections.

## Architecture and development

See [the architecture overview](docs/ARCHITECTURE.md) for storage, validation,
launcher generation, and platform-integration details.

Common development checks:

```sh
swift test
swift build -c release
sh Tests/CLISmokeTests.sh .build/release/context
sh Tests/InstallerSmokeTests.sh
```

The automated smoke tests redirect their install and data paths to temporary
directories; they do not open personal apps or install into your real
`~/Applications` directory. See [the manual acceptance checklist](docs/MANUAL_QA.md)
for the macOS interactions that need hands-on verification.

## Uninstall

Run this from the repository clone:

```sh
./uninstall.sh
```

By default, it removes the installed main app, `New.app`, matching generated
launcher bundles, and the installed CLI when its recorded install hash still
matches. It preserves contexts and copied icons. To request deletion of owned
configuration data as well, use:

```sh
./uninstall.sh --purge-data
```

The purge mode is intentionally limited to a recognized Context Launcher
support directory and leaves unknown support files intact. Check the target
paths before running either command; neither command removes original projects,
applications, Chrome data, or other files chosen by your contexts.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). This project is released under the
[MIT License](LICENSE).
