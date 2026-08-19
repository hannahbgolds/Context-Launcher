# Contributing to Context Launcher

Thanks for improving Context Launcher.

## Before opening a change

- Keep the project compatible with macOS 13 and Swift 6.
- Prefer Apple frameworks and the Swift standard library; avoid unnecessary
  dependencies.
- Keep user data local. Do not add telemetry, accounts, cloud services, or
  personal data to fixtures, documentation, screenshots, or commits.
- Preserve the separation between `ContextLauncherKit` business logic and the
  SwiftUI app or CLI front ends.

## Verify locally

Run these from the repository root before proposing a change:

```sh
swift test
swift build -c release
sh Tests/CLISmokeTests.sh .build/release/context
sh Tests/InstallerSmokeTests.sh
```

The installer smoke test uses temporary redirected paths. Do not run install or
uninstall tests against a personal Applications or Application Support
directory.

For changes involving Chrome, VS Code, Spotlight, generated icons, or app
focus behavior, follow the relevant items in [docs/MANUAL_QA.md](docs/MANUAL_QA.md)
and state what you observed.

## Submitting

Describe the user-visible behavior, include focused tests, and update public
documentation when a command, prerequisite, privacy behavior, installation
path, or limitation changes. Keep commits small and avoid unrelated reformatting.
