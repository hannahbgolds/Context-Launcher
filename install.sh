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
if [ "$MACOS_MAJOR" -lt 13 ]; then
    echo "Context Launcher requires macOS 13 or later." >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "Swift is required to install Context Launcher." >&2
    exit 1
fi

SCRIPT_DIRECTORY=$(cd -P "$(dirname "$0")" && pwd)
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
mkdir -p "$INSTALL_ROOT" "$CONTEXT_LAUNCHER_HOME"
INSTALL_ROOT=$(cd -P "$INSTALL_ROOT" && pwd)
CONTEXT_LAUNCHER_HOME=$(cd -P "$CONTEXT_LAUNCHER_HOME" && pwd)

WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/context-launcher-install.XXXXXX")
CONFIGURATION_TEMPORARY=
cleanup() {
    if [ -n "$CONFIGURATION_TEMPORARY" ] && [ -e "$CONFIGURATION_TEMPORARY" ]; then
        rm -f "$CONFIGURATION_TEMPORARY"
    fi
    if [ -d "$WORK_DIRECTORY" ]; then
        rm -R "$WORK_DIRECTORY"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "$SKIP_BUILD" = false ]; then
    (cd "$SCRIPT_DIRECTORY" && swift build -c release)
fi

RELEASE_DIRECTORY="$SCRIPT_DIRECTORY/.build/release"
CLI_SOURCE="$RELEASE_DIRECTORY/context"
if [ ! -x "$CLI_SOURCE" ]; then
    echo "Release CLI binary is missing: $CLI_SOURCE" >&2
    exit 1
fi

sh "$SCRIPT_DIRECTORY/scripts/assemble-app.sh" "$RELEASE_DIRECTORY" "$INSTALL_ROOT/Context Launcher.app"
mkdir -p "$CONTEXT_LAUNCHER_HOME/bin"
cp "$CLI_SOURCE" "$CONTEXT_LAUNCHER_HOME/bin/context"
chmod 755 "$CONTEXT_LAUNCHER_HOME/bin/context"

CONTEXTS_PATH="$CONTEXT_LAUNCHER_HOME/contexts.json"
if [ ! -e "$CONTEXTS_PATH" ]; then
    CONFIGURATION_TEMPORARY=$(mktemp "$CONTEXT_LAUNCHER_HOME/.contexts.XXXXXX")
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
        CONFIGURATION_TEMPORARY=
    fi
fi

CONTEXT_LAUNCHER_HOME="$CONTEXT_LAUNCHER_HOME" \
INSTALL_ROOT="$INSTALL_ROOT" \
sh "$SCRIPT_DIRECTORY/scripts/generate-apps.sh" "$CONTEXT_LAUNCHER_HOME/bin/context" "$INSTALL_ROOT"
