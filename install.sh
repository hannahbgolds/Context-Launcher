#!/bin/sh
set -eu

SKIP_BUILD=false
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--skip-build]" >&2
    exit 64
fi
if [ "$#" -eq 1 ]; then
    if [ "$1" != "--skip-build" ]; then
        echo "Usage: $0 [--skip-build]" >&2
        exit 64
    fi
    SKIP_BUILD=true
fi

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Context Launcher requires macOS 13 or later." >&2
    exit 1
fi
MACOS_MAJOR=$(sw_vers -productVersion | awk -F. '{ print $1 }')
if [ "$MACOS_MAJOR" -lt 13 ] || ! command -v swift >/dev/null 2>&1 || ! command -v shasum >/dev/null 2>&1; then
    echo "Context Launcher requires macOS 13, Swift, and shasum." >&2
    exit 1
fi

SCRIPT_DIRECTORY=$(cd -P "$(dirname "$0")" && pwd)
INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/Applications"}
CONTEXT_LAUNCHER_HOME=${CONTEXT_LAUNCHER_HOME:-"$HOME/Library/Application Support/ContextLauncher"}
case "$INSTALL_ROOT" in /*) ;; *) echo "INSTALL_ROOT must be absolute." >&2; exit 64 ;; esac
case "$CONTEXT_LAUNCHER_HOME" in /*) ;; *) echo "CONTEXT_LAUNCHER_HOME must be absolute." >&2; exit 64 ;; esac
if [ -L "$CONTEXT_LAUNCHER_HOME" ]; then
    echo "CONTEXT_LAUNCHER_HOME must not be a symlink." >&2
    exit 1
fi
mkdir -p "$INSTALL_ROOT" "$CONTEXT_LAUNCHER_HOME"
INSTALL_ROOT=$(cd -P "$INSTALL_ROOT" && pwd)
CONTEXT_LAUNCHER_HOME=$(cd -P "$CONTEXT_LAUNCHER_HOME" && pwd)

LOCK_DIRECTORY="$CONTEXT_LAUNCHER_HOME/.context-launcher-install.lock"
if ! mkdir "$LOCK_DIRECTORY"; then
    echo "Another Context Launcher installation is already running." >&2
    exit 1
fi
INSTALL_LOCK_DIRECTORY="$INSTALL_ROOT/.context-launcher-install.lock"
if ! mkdir "$INSTALL_LOCK_DIRECTORY"; then
    rmdir "$LOCK_DIRECTORY" || :
    echo "Another Context Launcher installation is already running for $INSTALL_ROOT." >&2
    exit 1
fi

if ! WORK_DIRECTORY=$(mktemp -d "$CONTEXT_LAUNCHER_HOME/.context-launcher-transaction.XXXXXX"); then
    rmdir "$INSTALL_LOCK_DIRECTORY" || :
    rmdir "$LOCK_DIRECTORY" || :
    exit 1
fi
COMMITTED=false
APPLICATION_TOUCHED=false
CLI_TOUCHED=false
CLI_HASH_TOUCHED=false
LAUNCHERS_GENERATED=false

APPLICATION_PATH="$INSTALL_ROOT/Context Launcher.app"
CLI_DIRECTORY="$CONTEXT_LAUNCHER_HOME/bin"
CLI_PATH="$CLI_DIRECTORY/context"
CLI_HASH_PATH="$CLI_DIRECTORY/.context-launcher-context.sha256"
SUPPORT_MARKER="$CONTEXT_LAUNCHER_HOME/.context-launcher-install"
BACKUP_DIRECTORY="$WORK_DIRECTORY/backup"
IDS_PATH="$WORK_DIRECTORY/launcher-ids"

remove_file() {
    if [ -e "$1" ] || [ -L "$1" ]; then rm -f "$1" || :; fi
}

remove_bundle() {
    if [ -e "$1" ] || [ -L "$1" ]; then rm -R "$1" || :; fi
}

restore_file() {
    if [ -e "$1" ] || [ -L "$1" ]; then mv "$1" "$2" || :; fi
}

restore_bundle() {
    if [ -e "$1" ] || [ -L "$1" ]; then mv "$1" "$2" || :; fi
}

rollback() {
    if [ "$LAUNCHERS_GENERATED" = true ] && [ -f "$IDS_PATH" ]; then
        while IFS= read -r launcher_id; do
            remove_bundle "$INSTALL_ROOT/$launcher_id.app"
        done < "$IDS_PATH"
    fi
    if [ -f "$IDS_PATH" ]; then
        while IFS= read -r launcher_id; do
            restore_bundle "$BACKUP_DIRECTORY/launchers/$launcher_id.app" "$INSTALL_ROOT/$launcher_id.app"
        done < "$IDS_PATH"
    fi
    if [ "$CLI_HASH_TOUCHED" = true ]; then remove_file "$CLI_HASH_PATH"; fi
    if [ "$CLI_TOUCHED" = true ]; then remove_file "$CLI_PATH"; fi
    if [ "$APPLICATION_TOUCHED" = true ]; then remove_bundle "$APPLICATION_PATH"; fi
    restore_file "$BACKUP_DIRECTORY/cli-hash" "$CLI_HASH_PATH"
    restore_file "$BACKUP_DIRECTORY/cli" "$CLI_PATH"
    restore_bundle "$BACKUP_DIRECTORY/application" "$APPLICATION_PATH"
}

cleanup() {
    if [ "$COMMITTED" != true ]; then rollback; fi
    if [ -d "$WORK_DIRECTORY" ]; then rm -R "$WORK_DIRECTORY" || :; fi
    if [ -d "$INSTALL_LOCK_DIRECTORY" ]; then rmdir "$INSTALL_LOCK_DIRECTORY" || :; fi
    if [ -d "$LOCK_DIRECTORY" ]; then rmdir "$LOCK_DIRECTORY" || :; fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$BACKUP_DIRECTORY/launchers"
: > "$IDS_PATH"

if [ "${CONTEXT_LAUNCHER_TEST_FAIL_EARLY:-}" = 1 ]; then
    echo "Forced early installation failure." >&2
    exit 1
fi

if [ "$SKIP_BUILD" = false ]; then
    (cd "$SCRIPT_DIRECTORY" && swift build -c release)
fi

RELEASE_DIRECTORY="$SCRIPT_DIRECTORY/.build/release"
CLI_SOURCE="$RELEASE_DIRECTORY/context"
if [ ! -x "$CLI_SOURCE" ] || [ ! -x "$RELEASE_DIRECTORY/ContextLauncherApp" ]; then
    echo "Release binaries are missing from $RELEASE_DIRECTORY" >&2
    exit 1
fi
if [ -e "$CLI_DIRECTORY" ] && [ -L "$CLI_DIRECTORY" ]; then
    echo "Context Launcher bin directory must not be a symlink." >&2
    exit 1
fi
mkdir -p "$CLI_DIRECTORY"

CONTEXTS_PATH="$CONTEXT_LAUNCHER_HOME/contexts.json"
if [ ! -e "$CONTEXTS_PATH" ]; then
    CONFIGURATION_TEMPORARY=$(mktemp "$CONTEXT_LAUNCHER_HOME/.contexts.XXXXXX")
    trap 'rm -f "$CONFIGURATION_TEMPORARY"; cleanup' EXIT HUP INT TERM
    printf '%s\n' \
        '{' \
        '  "contexts" : [' \
        '    {"applications":[],"icon":{"symbol":{"_0":"graduationcap"}},"id":"uni","name":"Uni","subtitle":"University","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"chevron.left.forwardslash.chevron.right"}},"id":"leet","name":"Leet","subtitle":"Practice","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"briefcase"}},"id":"work","name":"Work","subtitle":"Work","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"person.3"}},"id":"org","name":"Org","subtitle":"Organization","urls":[],"vscodeProjects":[]}' \
        '  ],' \
        '  "version" : 1' \
        '}' > "$CONFIGURATION_TEMPORARY"
    if ln "$CONFIGURATION_TEMPORARY" "$CONTEXTS_PATH"; then
        rm -f "$CONFIGURATION_TEMPORARY"
    elif [ ! -e "$CONTEXTS_PATH" ]; then
        echo "Could not initialize contexts.json." >&2
        exit 1
    fi
fi

STAGED_APPLICATION="$WORK_DIRECTORY/Context Launcher.app"
STAGED_CLI="$WORK_DIRECTORY/context"
sh "$SCRIPT_DIRECTORY/scripts/assemble-app.sh" "$RELEASE_DIRECTORY" "$STAGED_APPLICATION"
cp "$CLI_SOURCE" "$STAGED_CLI"
chmod 755 "$STAGED_CLI"

CONTEXT_LAUNCHER_HOME="$CONTEXT_LAUNCHER_HOME" INSTALL_ROOT="$INSTALL_ROOT" "$STAGED_CLI" list > "$WORK_DIRECTORY/context-list"
TAB=$(printf '\t')
while IFS="$TAB" read -r launcher_id ignored; do
    case "$launcher_id" in
        *[!a-z0-9-]* | -* | *- | *--* | '') continue ;;
    esac
    printf '%s\n' "$launcher_id" >> "$IDS_PATH"
done < "$WORK_DIRECTORY/context-list"
printf '%s\n' new >> "$IDS_PATH"

if [ -e "$APPLICATION_PATH" ] || [ -L "$APPLICATION_PATH" ]; then mv "$APPLICATION_PATH" "$BACKUP_DIRECTORY/application"; fi
APPLICATION_TOUCHED=true
mv "$STAGED_APPLICATION" "$APPLICATION_PATH"
if [ -e "$CLI_PATH" ] || [ -L "$CLI_PATH" ]; then mv "$CLI_PATH" "$BACKUP_DIRECTORY/cli"; fi
CLI_TOUCHED=true
mv "$STAGED_CLI" "$CLI_PATH"
CLI_HASH=$(shasum -a 256 "$CLI_PATH" | awk '{ print $1 }')
printf '%s\n' "$CLI_HASH" > "$WORK_DIRECTORY/cli-hash"
if [ -e "$CLI_HASH_PATH" ] || [ -L "$CLI_HASH_PATH" ]; then mv "$CLI_HASH_PATH" "$BACKUP_DIRECTORY/cli-hash"; fi
CLI_HASH_TOUCHED=true
mv "$WORK_DIRECTORY/cli-hash" "$CLI_HASH_PATH"

while IFS= read -r launcher_id; do
    launcher_path="$INSTALL_ROOT/$launcher_id.app"
    if [ -e "$launcher_path" ] || [ -L "$launcher_path" ]; then
        mv "$launcher_path" "$BACKUP_DIRECTORY/launchers/$launcher_id.app"
    fi
done < "$IDS_PATH"

if [ "${CONTEXT_LAUNCHER_TEST_FAIL_AFTER_COPY:-}" = 1 ]; then
    echo "Forced installation failure after application and CLI copy." >&2
    exit 1
fi

LAUNCHERS_GENERATED=true
CONTEXT_LAUNCHER_HOME="$CONTEXT_LAUNCHER_HOME" INSTALL_ROOT="$INSTALL_ROOT" \
    sh "$SCRIPT_DIRECTORY/scripts/generate-apps.sh" "$CLI_PATH" "$INSTALL_ROOT"

if [ -e "$SUPPORT_MARKER" ] || [ -L "$SUPPORT_MARKER" ]; then
    if [ -L "$SUPPORT_MARKER" ] || [ ! -f "$SUPPORT_MARKER" ] || \
        [ "$(sed -n '1p' "$SUPPORT_MARKER")" != 'context-launcher-install-root-v1' ] || \
        [ "$(sed -n '2p' "$SUPPORT_MARKER")" != "$CONTEXT_LAUNCHER_HOME" ]; then
        echo "Context Launcher support marker is not owned by this install root." >&2
        exit 1
    fi
else
    printf '%s\n%s\n' 'context-launcher-install-root-v1' "$CONTEXT_LAUNCHER_HOME" > "$SUPPORT_MARKER"
fi

COMMITTED=true
