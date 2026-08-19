#!/bin/sh
set -eu

BIN=$1
TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" list | grep 'No contexts configured'
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" doctor | grep 'Config directory'
test "$(CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/config" "$BIN" launch absent >/dev/null 2>&1; echo $?)" != 0

mkdir -p "$TEST_DIRECTORY/ids"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"symbol":{"_0":"folder"}},"id":"second","name":"Second","subtitle":"Human output only","urls":[],"vscodeProjects":[]},{"applications":[],"icon":{"symbol":{"_0":"folder"}},"id":"first","name":"First","subtitle":"Human output only","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$TEST_DIRECTORY/ids/contexts.json"
test "$(CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/ids" "$BIN" internal-context-ids)" = "first
second"

mkdir -p "$TEST_DIRECTORY/invalid"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"symbol":{"_0":"folder"}},"id":"safe","name":"Safe\nvictim","subtitle":"","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$TEST_DIRECTORY/invalid/contexts.json"
test "$(CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/invalid" "$BIN" internal-context-ids >/dev/null 2>&1; echo $?)" != 0

mkdir -p "$TEST_DIRECTORY/support/bin"
cp "$BIN" "$TEST_DIRECTORY/support/bin/context"
printf '%s\n' '{"contexts":[],"version":1}' > "$TEST_DIRECTORY/support/contexts.json"
CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/support" INSTALL_ROOT="$TEST_DIRECTORY/Applications" "$TEST_DIRECTORY/support/bin/context" internal-generate-all
test -f "$TEST_DIRECTORY/Applications/New.app/Contents/Info.plist"
test "$(find "$TEST_DIRECTORY/Applications" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)" = 'New.app'

mkdir -p "$TEST_DIRECTORY/support/icons"
OWNED_ICON="$TEST_DIRECTORY/support/icons/owned-icon.png"
printf '%s\n' 'icon' > "$OWNED_ICON"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"custom":{"_0":"'"$OWNED_ICON"'"}},"id":"owned","name":"Owned","subtitle":"","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$TEST_DIRECTORY/support/contexts.json"
test "$(CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/support" "$TEST_DIRECTORY/support/bin/context" internal-owned-icons)" = 'owned-icon.png'
