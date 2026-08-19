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
case "$INSTALL_ROOT" in
    /*) ;;
    *) echo "INSTALL_ROOT must be absolute." >&2; exit 64 ;;
esac
case "$CONTEXT_LAUNCHER_HOME" in
    /*) ;;
    *) echo "CONTEXT_LAUNCHER_HOME must be absolute." >&2; exit 64 ;;
esac

if [ -d "$INSTALL_ROOT" ]; then
    INSTALL_ROOT=$(cd -P "$INSTALL_ROOT" && pwd)
fi
if [ -d "$CONTEXT_LAUNCHER_HOME" ]; then
    CONTEXT_LAUNCHER_HOME=$(cd -P "$CONTEXT_LAUNCHER_HOME" && pwd)
fi

is_owned_bundle() {
    bundle_path=$1
    bundle_id=$2
    plist_path="$bundle_path/Contents/Info.plist"
    [ -f "$plist_path" ] && command -v plutil >/dev/null 2>&1 && \
        [ "$(plutil -extract CFBundleIdentifier raw -o - "$plist_path" 2>/dev/null || true)" = "$bundle_id" ]
}

APPLICATION_PATH="$INSTALL_ROOT/Context Launcher.app"
if [ -d "$APPLICATION_PATH" ] && is_owned_bundle "$APPLICATION_PATH" "dev.contextlauncher.app"; then
    rm -R "$APPLICATION_PATH"
fi

if [ -d "$INSTALL_ROOT" ]; then
    find "$INSTALL_ROOT" -maxdepth 1 -type d -name '*.app' -print | while IFS= read -r bundle_path; do
        bundle_name=$(basename "$bundle_path")
        if [ "$bundle_name" = "New.app" ]; then
            bundle_id=new
        else
            bundle_id=${bundle_name%.app}
            case "$bundle_id" in
                *[!a-z0-9-]* | -* | *- | *--* | '') continue ;;
            esac
        fi
        if is_owned_bundle "$bundle_path" "dev.contextlauncher.context.$bundle_id"; then
            rm -R "$bundle_path"
        fi
    done
fi

CLI_PATH="$CONTEXT_LAUNCHER_HOME/bin/context"
if [ -f "$CLI_PATH" ]; then
    rm -f "$CLI_PATH"
fi

if [ "$PURGE_DATA" = true ]; then
    case "$CONTEXT_LAUNCHER_HOME" in
        /|.) echo "Refusing to purge an unsafe support directory." >&2; exit 1 ;;
    esac
    if [ -d "$CONTEXT_LAUNCHER_HOME" ]; then
        rm -R "$CONTEXT_LAUNCHER_HOME"
    fi
fi
