#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <context-cli-path> <install-root>" >&2
    exit 64
fi

CLI_PATH=$1
INSTALL_ROOT=$2

case "$CLI_PATH" in
    /*) ;;
    *) echo "Context CLI path must be absolute." >&2; exit 64 ;;
esac
case "$INSTALL_ROOT" in
    /*) ;;
    *) echo "Install root must be absolute." >&2; exit 64 ;;
esac

"$CLI_PATH" internal-generate-all

if command -v mdimport >/dev/null 2>&1; then
    find "$INSTALL_ROOT" -maxdepth 1 -type d -name '*.app' -exec mdimport {} \; || true
fi
