# Manual acceptance checklist

Run this checklist on a macOS machine after a normal installation. It verifies
real applications and Spotlight, so it is deliberately separate from the
automated temporary-directory smoke tests.

1. Configure `leet` with a detected personal Chrome profile.
2. Add https://leetcode.com/ and select a local leetcode-solutions folder.
3. Save and verify ~/Applications/Leet.app exists.
4. Launch Leet.app and verify the chosen Chrome profile and URL.
5. Verify the folder opens in a separate VS Code window.
6. Search Spotlight for `leet` and verify the custom launcher icon/result.
7. Repeat while Chrome and VS Code are already running and record duplicate-window behavior.

Record the macOS, Chrome, and VS Code versions, whether Chrome reused or
created a window, whether VS Code opened a distinct window, and any Spotlight
indexing delay. Do not include profile email addresses, personal paths, or
unredacted screenshots in issue reports.
