#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <release-build-directory> <application-path>" >&2
    exit 64
fi

BUILD_DIRECTORY=$1
APPLICATION_PATH=$2
APPLICATION_NAME=$(basename "$APPLICATION_PATH")

case "$BUILD_DIRECTORY" in
    /*) ;;
    *) echo "Release build directory must be absolute." >&2; exit 64 ;;
esac
case "$APPLICATION_PATH" in
    /*) ;;
    *) echo "Application path must be absolute." >&2; exit 64 ;;
esac

if [ "$APPLICATION_NAME" != "Context Launcher.app" ]; then
    echo "Application path must end in Context Launcher.app." >&2
    exit 64
fi

SOURCE_BINARY="$BUILD_DIRECTORY/ContextLauncherApp"
if [ ! -x "$SOURCE_BINARY" ]; then
    echo "Release application binary is missing: $SOURCE_BINARY" >&2
    exit 1
fi

APPLICATION_PARENT=$(dirname "$APPLICATION_PATH")
mkdir -p "$APPLICATION_PARENT"
STAGING_ROOT=$(mktemp -d "$APPLICATION_PARENT/.context-launcher-app.XXXXXX")
STAGING_APPLICATION="$STAGING_ROOT/$APPLICATION_NAME"

cleanup() {
    if [ -d "$STAGING_ROOT" ]; then
        rm -R "$STAGING_ROOT"
    fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$STAGING_APPLICATION/Contents/MacOS"
printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    '  <key>CFBundleDisplayName</key><string>Context Launcher</string>' \
    '  <key>CFBundleExecutable</key><string>ContextLauncherApp</string>' \
    '  <key>CFBundleIdentifier</key><string>dev.contextlauncher.app</string>' \
    '  <key>CFBundleName</key><string>Context Launcher</string>' \
    '  <key>CFBundlePackageType</key><string>APPL</string>' \
    '  <key>CFBundleShortVersionString</key><string>1.0</string>' \
    '  <key>CFBundleVersion</key><string>1</string>' \
    '</dict>' \
    '</plist>' > "$STAGING_APPLICATION/Contents/Info.plist"
cp "$SOURCE_BINARY" "$STAGING_APPLICATION/Contents/MacOS/ContextLauncherApp"

if [ -e "$APPLICATION_PATH" ] || [ -L "$APPLICATION_PATH" ]; then
    echo "Application destination already exists: $APPLICATION_PATH" >&2
    exit 1
fi

mv "$STAGING_APPLICATION" "$APPLICATION_PATH"
