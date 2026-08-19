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
INSTALL_ROOT_CREATED=false
SUPPORT_DIRECTORY_CREATED=false
if [ ! -e "$INSTALL_ROOT" ] && [ ! -L "$INSTALL_ROOT" ]; then INSTALL_ROOT_CREATED=true; fi
if [ ! -e "$CONTEXT_LAUNCHER_HOME" ] && [ ! -L "$CONTEXT_LAUNCHER_HOME" ]; then SUPPORT_DIRECTORY_CREATED=true; fi
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
CONFIGURATION_INITIALIZED=false
SETUP_PENDING_CREATED=false
CLI_DIRECTORY_CREATED=false

APPLICATION_PATH="$INSTALL_ROOT/Context Launcher.app"
CLI_DIRECTORY="$CONTEXT_LAUNCHER_HOME/bin"
CLI_PATH="$CLI_DIRECTORY/context"
CLI_HASH_PATH="$CLI_DIRECTORY/.context-launcher-context.sha256"
SUPPORT_MARKER="$CONTEXT_LAUNCHER_HOME/.context-launcher-install"
CONTEXTS_PATH="$CONTEXT_LAUNCHER_HOME/contexts.json"
SETUP_PENDING_PATH="$CONTEXT_LAUNCHER_HOME/setup-pending"
BACKUP_DIRECTORY="$WORK_DIRECTORY/backup"
IDS_PATH="$WORK_DIRECTORY/launcher-ids"
LAUNCHER_PATHS_PATH="$WORK_DIRECTORY/launcher-paths"

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
    if [ "$LAUNCHERS_GENERATED" = true ] && [ -f "$LAUNCHER_PATHS_PATH" ]; then
        while IFS="$(printf '\t')" read -r launcher_name launcher_id; do
            launcher_path="$INSTALL_ROOT/$launcher_name"
            if is_owned_bundle "$launcher_path" "dev.contextlauncher.context.$launcher_id"; then
                remove_bundle "$launcher_path"
            fi
        done < "$LAUNCHER_PATHS_PATH"
    fi
    if [ -f "$LAUNCHER_PATHS_PATH" ]; then
        while IFS="$(printf '\t')" read -r launcher_name launcher_id; do
            restore_bundle "$BACKUP_DIRECTORY/launchers/$launcher_name" "$INSTALL_ROOT/$launcher_name"
        done < "$LAUNCHER_PATHS_PATH"
    fi
    if [ "$CLI_HASH_TOUCHED" = true ]; then remove_file "$CLI_HASH_PATH"; fi
    if [ "$CLI_TOUCHED" = true ]; then remove_file "$CLI_PATH"; fi
    if [ "$APPLICATION_TOUCHED" = true ]; then remove_bundle "$APPLICATION_PATH"; fi
    restore_file "$BACKUP_DIRECTORY/cli-hash" "$CLI_HASH_PATH"
    restore_file "$BACKUP_DIRECTORY/cli" "$CLI_PATH"
    restore_bundle "$BACKUP_DIRECTORY/application" "$APPLICATION_PATH"
    if [ "$SETUP_PENDING_CREATED" = true ]; then remove_file "$SETUP_PENDING_PATH"; fi
    if [ "$CONFIGURATION_INITIALIZED" = true ]; then remove_file "$CONTEXTS_PATH"; fi
}

cleanup() {
    if [ "$COMMITTED" != true ]; then rollback; fi
    if [ -d "$WORK_DIRECTORY" ]; then rm -R "$WORK_DIRECTORY" || :; fi
    if [ -d "$INSTALL_LOCK_DIRECTORY" ]; then rmdir "$INSTALL_LOCK_DIRECTORY" || :; fi
    if [ -d "$LOCK_DIRECTORY" ]; then rmdir "$LOCK_DIRECTORY" || :; fi
    if [ "$COMMITTED" != true ]; then
        if [ "$CLI_DIRECTORY_CREATED" = true ] && [ -d "$CLI_DIRECTORY" ]; then rmdir "$CLI_DIRECTORY" 2>/dev/null || :; fi
        if [ "$SUPPORT_DIRECTORY_CREATED" = true ] && [ -d "$CONTEXT_LAUNCHER_HOME" ]; then rmdir "$CONTEXT_LAUNCHER_HOME" 2>/dev/null || :; fi
        if [ "$INSTALL_ROOT_CREATED" = true ] && [ -d "$INSTALL_ROOT" ]; then rmdir "$INSTALL_ROOT" 2>/dev/null || :; fi
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

is_owned_bundle() {
    bundle_path=$1
    bundle_id=$2
    plist_path="$bundle_path/Contents/Info.plist"
    [ -d "$bundle_path" ] && [ ! -L "$bundle_path" ] && [ -f "$plist_path" ] && \
        [ "$(plutil -extract CFBundleIdentifier raw -o - "$plist_path" 2>/dev/null || true)" = "$bundle_id" ]
}

preflight_bundle() {
    bundle_path=$1
    bundle_id=$2
    if [ -e "$bundle_path" ] || [ -L "$bundle_path" ]; then
        if ! is_owned_bundle "$bundle_path" "$bundle_id"; then
            echo "Refusing to replace $bundle_path: it is a symlink or is not owned by Context Launcher as $bundle_id. Move or rename it, then try again." >&2
            exit 1
        fi
    fi
}

write_starter_configuration() {
    destination=$1
    printf '%s\n' \
        '{' \
        '  "contexts" : [' \
        '    {"applications":[],"icon":{"symbol":{"_0":"graduationcap"}},"id":"uni","name":"Uni","subtitle":"University","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"chevron.left.forwardslash.chevron.right"}},"id":"leet","name":"Leet","subtitle":"Practice","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"briefcase"}},"id":"work","name":"Work","subtitle":"Work","urls":[],"vscodeProjects":[]},' \
        '    {"applications":[],"icon":{"symbol":{"_0":"person.3"}},"id":"org","name":"Org","subtitle":"Organization","urls":[],"vscodeProjects":[]}' \
        '  ],' \
        '  "version" : 1' \
        '}' > "$destination"
}

mkdir -p "$BACKUP_DIRECTORY/launchers"
: > "$IDS_PATH"
: > "$LAUNCHER_PATHS_PATH"

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

STAGED_APPLICATION="$WORK_DIRECTORY/Context Launcher.app"
STAGED_CLI="$WORK_DIRECTORY/context"
sh "$SCRIPT_DIRECTORY/scripts/assemble-app.sh" "$RELEASE_DIRECTORY" "$STAGED_APPLICATION"
cp "$CLI_SOURCE" "$STAGED_CLI"
chmod 755 "$STAGED_CLI"

preflight_bundle "$APPLICATION_PATH" "dev.contextlauncher.app"

STARTER_INITIALIZATION_NEEDED=false
CONFIGURATION_HOME="$CONTEXT_LAUNCHER_HOME"
if [ ! -e "$CONTEXTS_PATH" ] && [ ! -L "$CONTEXTS_PATH" ]; then
    STARTER_INITIALIZATION_NEEDED=true
    CONFIGURATION_HOME="$WORK_DIRECTORY/support"
    mkdir -p "$CONFIGURATION_HOME"
    write_starter_configuration "$CONFIGURATION_HOME/contexts.json"
fi

CONTEXT_LAUNCHER_HOME="$CONFIGURATION_HOME" "$STAGED_CLI" internal-context-ids > "$IDS_PATH"
printf '%s\n' new >> "$IDS_PATH"

PREVIEW_LAUNCHERS="$WORK_DIRECTORY/preview-launchers"
CONTEXT_LAUNCHER_HOME="$CONFIGURATION_HOME" CONTEXT_LAUNCHER_CLI_PATH="$CLI_PATH" \
    INSTALL_ROOT="$PREVIEW_LAUNCHERS" "$STAGED_CLI" internal-generate-all
for preview_bundle in "$PREVIEW_LAUNCHERS"/*.app; do
    launcher_name=$(basename "$preview_bundle")
    bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$preview_bundle/Contents/Info.plist")
    case "$bundle_id" in
        dev.contextlauncher.context.*) launcher_id=${bundle_id#dev.contextlauncher.context.} ;;
        *) echo "Generated launcher has an unexpected bundle identifier: $bundle_id" >&2; exit 1 ;;
    esac
    if ! grep -F -x "$launcher_id" "$IDS_PATH" >/dev/null; then
        echo "Generated launcher has an unexpected context ID: $launcher_id" >&2
        exit 1
    fi
    printf '%s\t%s\n' "$launcher_name" "$launcher_id" >> "$LAUNCHER_PATHS_PATH"
    preflight_bundle "$INSTALL_ROOT/$launcher_name" "$bundle_id"
done

if [ "$STARTER_INITIALIZATION_NEEDED" = true ]; then
    if [ -e "$SETUP_PENDING_PATH" ] || [ -L "$SETUP_PENDING_PATH" ]; then
        echo "Refusing to initialize starter data because setup-pending already exists." >&2
        exit 1
    fi
    if ! ln "$CONFIGURATION_HOME/contexts.json" "$CONTEXTS_PATH"; then
        echo "Could not initialize contexts.json." >&2
        exit 1
    fi
    CONFIGURATION_INITIALIZED=true
    SETUP_PENDING_TEMPORARY="$WORK_DIRECTORY/setup-pending"
    : > "$SETUP_PENDING_TEMPORARY"
    if ! ln "$SETUP_PENDING_TEMPORARY" "$SETUP_PENDING_PATH"; then
        echo "Could not initialize setup-pending." >&2
        exit 1
    fi
    SETUP_PENDING_CREATED=true
fi

if [ ! -d "$CLI_DIRECTORY" ]; then
    mkdir -p "$CLI_DIRECTORY"
    CLI_DIRECTORY_CREATED=true
fi

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

while IFS="$(printf '\t')" read -r launcher_name launcher_id; do
    launcher_path="$INSTALL_ROOT/$launcher_name"
    if [ -e "$launcher_path" ] || [ -L "$launcher_path" ]; then
        mv "$launcher_path" "$BACKUP_DIRECTORY/launchers/$launcher_name"
    fi
done < "$LAUNCHER_PATHS_PATH"

if [ "${CONTEXT_LAUNCHER_TEST_FAIL_AFTER_COPY:-}" = 1 ]; then
    echo "Forced installation failure after application and CLI copy." >&2
    exit 1
fi

LAUNCHERS_GENERATED=true
while IFS="$(printf '\t')" read -r launcher_name launcher_id; do
    mv "$PREVIEW_LAUNCHERS/$launcher_name" "$INSTALL_ROOT/$launcher_name"
    if command -v mdimport >/dev/null 2>&1; then
        mdimport "$INSTALL_ROOT/$launcher_name" || true
    fi
done < "$LAUNCHER_PATHS_PATH"

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
