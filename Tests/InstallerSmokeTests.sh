#!/bin/sh
set -eu

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

INSTALL_ROOT="$TEST_DIRECTORY/install" \
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/support" \
./install.sh --skip-build

test -x "$TEST_DIRECTORY/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
test -x "$TEST_DIRECTORY/support/bin/context"
test -f "$TEST_DIRECTORY/install/New.app/Contents/Info.plist"
for launcher in uni leet work org; do
    test -f "$TEST_DIRECTORY/install/$launcher.app/Contents/Info.plist"
done

INSTALL_ROOT="$TEST_DIRECTORY/install" \
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/support" \
./uninstall.sh

test ! -e "$TEST_DIRECTORY/install/Context Launcher.app"
test -f "$TEST_DIRECTORY/support/contexts.json"
