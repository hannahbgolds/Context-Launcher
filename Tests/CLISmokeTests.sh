#!/bin/sh
set -eu

BIN=$1
TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" list | grep 'No contexts configured'
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" doctor | grep 'Config directory'
test "$(CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" launch absent >/dev/null 2>&1; echo $?)" != 0

mkdir -p "$TEST_DIRECTORY/support/bin"
cp "$BIN" "$TEST_DIRECTORY/support/bin/context"
printf '%s\n' '{"contexts":[],"version":1}' > "$TEST_DIRECTORY/support/contexts.json"
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/support" INSTALL_ROOT="$TEST_DIRECTORY/Applications" "$TEST_DIRECTORY/support/bin/context" internal-generate-all
test -f "$TEST_DIRECTORY/Applications/new.app/Contents/Info.plist"
