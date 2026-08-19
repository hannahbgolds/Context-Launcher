#!/bin/sh
set -eu

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -R "$TEST_DIRECTORY"' EXIT HUP INT TERM

install_redirected() {
    INSTALL_ROOT="$1/install" CONTEXT_LAUNCHER_HOME="$1/support" ./install.sh --skip-build
}

make_decoy() {
    mkdir -p "$1/Contents"
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<plist version="1.0"><dict>' \
        '<key>CFBundleIdentifier</key><string>dev.contextlauncher.context.decoy</string>' \
        '</dict></plist>' > "$1/Contents/Info.plist"
}

PRIMARY="$TEST_DIRECTORY/primary"
mkdir -p "$PRIMARY"
install_redirected "$PRIMARY"

test -x "$PRIMARY/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
test -x "$PRIMARY/support/bin/context"
test -f "$PRIMARY/install/New.app/Contents/Info.plist"
for launcher in uni leet work org; do
    test -f "$PRIMARY/install/$launcher.app/Contents/Info.plist"
done

make_decoy "$PRIMARY/install/decoy.app"
printf '%s\n' 'user replacement' > "$PRIMARY/support/bin/context"

INSTALL_ROOT="$PRIMARY/install" CONTEXT_LAUNCHER_HOME="$PRIMARY/support" ./uninstall.sh

test ! -e "$PRIMARY/install/Context Launcher.app"
test ! -e "$PRIMARY/install/New.app"
test -f "$PRIMARY/install/uni.app/Contents/Info.plist"
test -f "$PRIMARY/install/decoy.app/Contents/Info.plist"
test -f "$PRIMARY/support/contexts.json"
test "$(cat "$PRIMARY/support/bin/context")" = 'user replacement'

OWNED="$TEST_DIRECTORY/owned"
mkdir -p "$OWNED"
install_redirected "$OWNED"
INSTALL_ROOT="$OWNED/install" CONTEXT_LAUNCHER_HOME="$OWNED/support" ./uninstall.sh
test ! -e "$OWNED/install/New.app"
test ! -e "$OWNED/install/uni.app"
test ! -e "$OWNED/support/bin/context"
test -f "$OWNED/support/contexts.json"

PURGE="$TEST_DIRECTORY/purge"
mkdir -p "$PURGE"
install_redirected "$PURGE"
printf '%s\n' 'unknown sibling' > "$PURGE/support/keep.txt"
mkdir -p "$PURGE/support/icons"
printf '%s\n' 'product icon' > "$PURGE/support/icons/product-icon.txt"
INSTALL_ROOT="$PURGE/install" CONTEXT_LAUNCHER_HOME="$PURGE/support" ./uninstall.sh --purge-data
test -d "$PURGE/support"
test "$(cat "$PURGE/support/keep.txt")" = 'unknown sibling'
test ! -e "$PURGE/support/contexts.json"
test ! -e "$PURGE/support/icons"
test ! -e "$PURGE/support/bin"
test ! -e "$PURGE/support/.context-launcher-install"

EMPTY_PURGE="$TEST_DIRECTORY/empty-purge"
mkdir -p "$EMPTY_PURGE"
install_redirected "$EMPTY_PURGE"
INSTALL_ROOT="$EMPTY_PURGE/install" CONTEXT_LAUNCHER_HOME="$EMPTY_PURGE/support" ./uninstall.sh --purge-data
test ! -e "$EMPTY_PURGE/support"

BROAD_HOME="$TEST_DIRECTORY/home-like"
mkdir -p "$BROAD_HOME"
test "$(HOME="$BROAD_HOME" INSTALL_ROOT="$BROAD_HOME/install" CONTEXT_LAUNCHER_HOME="$BROAD_HOME" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$BROAD_HOME"
BROAD_PARENT="$TEST_DIRECTORY/broad-parent"
mkdir -p "$BROAD_PARENT"
test "$(INSTALL_ROOT="$BROAD_PARENT/install" CONTEXT_LAUNCHER_HOME="$BROAD_PARENT" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$BROAD_PARENT"

SYMLINK_TARGET="$TEST_DIRECTORY/symlink-target"
mkdir -p "$SYMLINK_TARGET"
install_redirected "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET/support" "$TEST_DIRECTORY/symlink-support"
test "$(INSTALL_ROOT="$SYMLINK_TARGET/install" CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/symlink-support" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$SYMLINK_TARGET/support"

LOCKED="$TEST_DIRECTORY/locked"
mkdir -p "$LOCKED/support/.context-launcher-install.lock"
test "$(INSTALL_ROOT="$LOCKED/install" CONTEXT_LAUNCHER_HOME="$LOCKED/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test ! -e "$LOCKED/install/Context Launcher.app"

INSTALL_LOCKED="$TEST_DIRECTORY/install-locked"
mkdir -p "$INSTALL_LOCKED/install/.context-launcher-install.lock"
test "$(INSTALL_ROOT="$INSTALL_LOCKED/install" CONTEXT_LAUNCHER_HOME="$INSTALL_LOCKED/other-support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test ! -e "$INSTALL_LOCKED/install/Context Launcher.app"

EARLY_FAILURE="$TEST_DIRECTORY/early-failure"
mkdir -p "$EARLY_FAILURE"
test "$(CONTEXT_LAUNCHER_TEST_FAIL_EARLY=1 INSTALL_ROOT="$EARLY_FAILURE/install" CONTEXT_LAUNCHER_HOME="$EARLY_FAILURE/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
install_redirected "$EARLY_FAILURE"
test -e "$EARLY_FAILURE/install/Context Launcher.app"

ROLLBACK="$TEST_DIRECTORY/rollback"
mkdir -p "$ROLLBACK"
install_redirected "$ROLLBACK"
printf '%s\n' 'old application' > "$ROLLBACK/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
printf '%s\n' 'old cli' > "$ROLLBACK/support/bin/context"
printf '%s\n' 'old launcher' > "$ROLLBACK/install/uni.app/Contents/Info.plist"
test "$(CONTEXT_LAUNCHER_TEST_FAIL_AFTER_COPY=1 INSTALL_ROOT="$ROLLBACK/install" CONTEXT_LAUNCHER_HOME="$ROLLBACK/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test "$(cat "$ROLLBACK/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp")" = 'old application'
test "$(cat "$ROLLBACK/support/bin/context")" = 'old cli'
test "$(cat "$ROLLBACK/install/uni.app/Contents/Info.plist")" = 'old launcher'
