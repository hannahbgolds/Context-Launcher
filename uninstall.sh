#!/bin/sh
set -eu

PURGE_DATA=false
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--purge-data]" >&2
    exit 64
fi
if [ "$#" -eq 1 ]; then
    if [ "$1" != "--purge-data" ]; then
        echo "Usage: $0 [--purge-data]" >&2
        exit 64
    fi
    PURGE_DATA=true
fi

INSTALL_ROOT=${INSTALL_ROOT:-"$HOME/Applications"}
CONTEXT_LAUNCHER_HOME=${CONTEXT_LAUNCHER_HOME:-"$HOME/Library/Application Support/ContextLauncher"}
case "$INSTALL_ROOT" in /*) ;; *) echo "INSTALL_ROOT must be absolute." >&2; exit 64 ;; esac
case "$CONTEXT_LAUNCHER_HOME" in /*) ;; *) echo "CONTEXT_LAUNCHER_HOME must be absolute." >&2; exit 64 ;; esac

SUPPORT_WAS_SYMLINK=false
if [ -L "$CONTEXT_LAUNCHER_HOME" ]; then
    SUPPORT_WAS_SYMLINK=true
elif [ -d "$CONTEXT_LAUNCHER_HOME" ]; then
    CONTEXT_LAUNCHER_HOME=$(cd -P "$CONTEXT_LAUNCHER_HOME" && pwd)
fi
if [ -d "$INSTALL_ROOT" ]; then
    INSTALL_ROOT=$(cd -P "$INSTALL_ROOT" && pwd)
fi

SUPPORT_MARKER="$CONTEXT_LAUNCHER_HOME/.context-launcher-install"
CLI_DIRECTORY="$CONTEXT_LAUNCHER_HOME/bin"
CLI_PATH="$CLI_DIRECTORY/context"
CLI_HASH_PATH="$CLI_DIRECTORY/.context-launcher-context.sha256"
SETUP_PENDING_PATH="$CONTEXT_LAUNCHER_HOME/setup-pending"
CONTEXTS_PATH="$CONTEXT_LAUNCHER_HOME/contexts.json"
ICONS_DIRECTORY="$CONTEXT_LAUNCHER_HOME/icons"
LOCK_DIRECTORY="$CONTEXT_LAUNCHER_HOME/.context-launcher-install.lock"

is_owned_bundle() {
    bundle_path=$1
    bundle_id=$2
    plist_path="$bundle_path/Contents/Info.plist"
    [ -d "$bundle_path" ] && [ ! -L "$bundle_path" ] && [ -f "$plist_path" ] && \
        command -v plutil >/dev/null 2>&1 && \
        [ "$(plutil -extract CFBundleIdentifier raw -o - "$plist_path" 2>/dev/null || true)" = "$bundle_id" ]
}

is_owned_support_root() {
    [ "$SUPPORT_WAS_SYMLINK" = false ] && [ -d "$CONTEXT_LAUNCHER_HOME" ] && [ ! -L "$CONTEXT_LAUNCHER_HOME" ] || return 1
    case "$CONTEXT_LAUNCHER_HOME" in
        /|"$HOME"|"${TMPDIR:-/tmp}"|/tmp|/private/tmp) return 1 ;;
    esac
    [ "$(dirname "$CONTEXT_LAUNCHER_HOME")" != / ] || return 1
    [ -f "$SUPPORT_MARKER" ] && [ ! -L "$SUPPORT_MARKER" ] || return 1
    [ "$(sed -n '1p' "$SUPPORT_MARKER")" = 'context-launcher-install-root-v1' ] && \
        [ "$(sed -n '2p' "$SUPPORT_MARKER")" = "$CONTEXT_LAUNCHER_HOME" ]
}

is_owned_cli() {
    is_owned_support_root && command -v shasum >/dev/null 2>&1 && \
        [ -d "$CLI_DIRECTORY" ] && [ ! -L "$CLI_DIRECTORY" ] && \
        [ -f "$CLI_PATH" ] && [ ! -L "$CLI_PATH" ] && \
        [ -f "$CLI_HASH_PATH" ] && [ ! -L "$CLI_HASH_PATH" ] && \
        [ "$(shasum -a 256 "$CLI_PATH" | awk '{ print $1 }')" = "$(sed -n '1p' "$CLI_HASH_PATH")" ]
}

ROOT_OWNED=false
if is_owned_support_root; then ROOT_OWNED=true; fi
CLI_OWNED=false
if is_owned_cli; then CLI_OWNED=true; fi

APPLICATION_PATH="$INSTALL_ROOT/Context Launcher.app"
if [ -d "$APPLICATION_PATH" ] && is_owned_bundle "$APPLICATION_PATH" "dev.contextlauncher.app"; then
    rm -R "$APPLICATION_PATH"
fi

if is_owned_bundle "$INSTALL_ROOT/New.app" "dev.contextlauncher.context.new"; then
    rm -R "$INSTALL_ROOT/New.app"
fi

if [ "$CLI_OWNED" = true ]; then
    IDS_PATH=$(mktemp "${TMPDIR:-/tmp}/context-launcher-uninstall.XXXXXX")
    trap 'rm -f "$IDS_PATH"' EXIT HUP INT TERM
    if CONTEXT_LAUNCHER_HOME="$CONTEXT_LAUNCHER_HOME" INSTALL_ROOT="$INSTALL_ROOT" "$CLI_PATH" list > "$IDS_PATH"; then
        TAB=$(printf '\t')
        while IFS="$TAB" read -r launcher_id ignored; do
            case "$launcher_id" in
                *[!a-z0-9-]* | -* | *- | *--* | '') continue ;;
            esac
            launcher_path="$INSTALL_ROOT/$launcher_id.app"
            if is_owned_bundle "$launcher_path" "dev.contextlauncher.context.$launcher_id"; then
                rm -R "$launcher_path"
            fi
        done < "$IDS_PATH"
    fi
    rm -f "$CLI_PATH" "$CLI_HASH_PATH"
fi

if [ "$PURGE_DATA" = true ]; then
    if [ "$ROOT_OWNED" != true ]; then
        echo "Refusing to purge a non-owned or unsafe support directory." >&2
        exit 1
    fi
    if [ -d "$LOCK_DIRECTORY" ]; then
        echo "Refusing to purge while an installation is active." >&2
        exit 1
    fi
    if [ -f "$CONTEXTS_PATH" ] && [ ! -L "$CONTEXTS_PATH" ]; then rm -f "$CONTEXTS_PATH"; fi
    if [ -f "$SETUP_PENDING_PATH" ] && [ ! -L "$SETUP_PENDING_PATH" ]; then rm -f "$SETUP_PENDING_PATH"; fi
    if [ -d "$ICONS_DIRECTORY" ] && [ ! -L "$ICONS_DIRECTORY" ]; then rm -R "$ICONS_DIRECTORY"; fi
    if [ "$CLI_OWNED" = true ] && [ -d "$CLI_DIRECTORY" ] && [ ! -L "$CLI_DIRECTORY" ]; then rm -R "$CLI_DIRECTORY"; fi
    if [ -f "$SUPPORT_MARKER" ] && [ ! -L "$SUPPORT_MARKER" ]; then rm -f "$SUPPORT_MARKER"; fi
    rmdir "$CONTEXT_LAUNCHER_HOME" 2>/dev/null || :
fi
