#!/bin/sh
set -eu

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -R "$TEST_DIRECTORY"' EXIT HUP INT TERM

# Keep smoke verification isolated from the user's real Spotlight index.
mkdir -p "$TEST_DIRECTORY/fake-bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$TEST_DIRECTORY/fake-bin/mdimport"
chmod +x "$TEST_DIRECTORY/fake-bin/mdimport"
PATH="$TEST_DIRECTORY/fake-bin:$PATH"
export PATH

install_redirected() {
    INSTALL_ROOT="$1/install" CONTEXT_LAUNCHER_HOME="$1/support" ./install.sh --skip-build
}

make_decoy() {
    mkdir -p "$1/Contents"
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<plist version="1.0"><dict>' \
        '<key>CFBundleIdentifier</key><string>'"${2:-dev.contextlauncher.context.decoy}"'</string>' \
        '</dict></plist>' > "$1/Contents/Info.plist"
    printf '%s\n' "${3:-decoy}" > "$1/marker"
}

assert_decoy() {
    test "$(cat "$1/marker")" = "$2"
}

CENTRAL_COLLISION="$TEST_DIRECTORY/central-collision"
mkdir -p "$CENTRAL_COLLISION/install"
make_decoy "$CENTRAL_COLLISION/install/Context Launcher.app" "com.example.central" "central decoy"
test "$(INSTALL_ROOT="$CENTRAL_COLLISION/install" CONTEXT_LAUNCHER_HOME="$CENTRAL_COLLISION/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
assert_decoy "$CENTRAL_COLLISION/install/Context Launcher.app" "central decoy"
test ! -e "$CENTRAL_COLLISION/support/contexts.json"

NEW_COLLISION="$TEST_DIRECTORY/new-collision"
mkdir -p "$NEW_COLLISION/install"
make_decoy "$NEW_COLLISION/install/New.app" "com.example.new" "new decoy"
test "$(INSTALL_ROOT="$NEW_COLLISION/install" CONTEXT_LAUNCHER_HOME="$NEW_COLLISION/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
assert_decoy "$NEW_COLLISION/install/New.app" "new decoy"
test ! -e "$NEW_COLLISION/support/contexts.json"

CONTEXT_COLLISION="$TEST_DIRECTORY/context-collision"
mkdir -p "$CONTEXT_COLLISION/install"
make_decoy "$CONTEXT_COLLISION/install/Uni.app" "com.example.uni" "context decoy"
test "$(INSTALL_ROOT="$CONTEXT_COLLISION/install" CONTEXT_LAUNCHER_HOME="$CONTEXT_COLLISION/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
assert_decoy "$CONTEXT_COLLISION/install/Uni.app" "context decoy"
test ! -e "$CONTEXT_COLLISION/support/contexts.json"

SYMLINK_COLLISION="$TEST_DIRECTORY/symlink-collision"
mkdir -p "$SYMLINK_COLLISION/install"
make_decoy "$SYMLINK_COLLISION/target.app" "dev.contextlauncher.context.new" "symlink target"
ln -s "$SYMLINK_COLLISION/target.app" "$SYMLINK_COLLISION/install/New.app"
test "$(INSTALL_ROOT="$SYMLINK_COLLISION/install" CONTEXT_LAUNCHER_HOME="$SYMLINK_COLLISION/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
assert_decoy "$SYMLINK_COLLISION/target.app" "symlink target"
test -L "$SYMLINK_COLLISION/install/New.app"
test ! -e "$SYMLINK_COLLISION/support/contexts.json"

PRIMARY="$TEST_DIRECTORY/primary"
mkdir -p "$PRIMARY"
install_redirected "$PRIMARY"

test -x "$PRIMARY/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
test "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw -o - "$PRIMARY/install/Context Launcher.app/Contents/Info.plist")" = 'contextlauncher'
test -x "$PRIMARY/support/bin/context"
test -f "$PRIMARY/install/New.app/Contents/Info.plist"
test -f "$PRIMARY/support/setup-pending"
test ! -s "$PRIMARY/support/setup-pending"
for launcher in Uni Leet Work Org; do
    test -f "$PRIMARY/install/$launcher.app/Contents/Info.plist"
done

rm "$PRIMARY/support/setup-pending"
install_redirected "$PRIMARY"
test ! -e "$PRIMARY/support/setup-pending"

make_decoy "$PRIMARY/install/decoy.app"
printf '%s\n' 'user replacement' > "$PRIMARY/support/bin/context"

INSTALL_ROOT="$PRIMARY/install" CONTEXT_LAUNCHER_HOME="$PRIMARY/support" ./uninstall.sh

test ! -e "$PRIMARY/install/Context Launcher.app"
test ! -e "$PRIMARY/install/New.app"
test -f "$PRIMARY/install/Uni.app/Contents/Info.plist"
test -f "$PRIMARY/install/decoy.app/Contents/Info.plist"
test -f "$PRIMARY/support/contexts.json"
test "$(cat "$PRIMARY/support/bin/context")" = 'user replacement'

OWNED="$TEST_DIRECTORY/owned"
mkdir -p "$OWNED"
install_redirected "$OWNED"
install_redirected "$OWNED"
INSTALL_ROOT="$OWNED/install" CONTEXT_LAUNCHER_HOME="$OWNED/support" ./uninstall.sh
test ! -e "$OWNED/install/New.app"
test ! -e "$OWNED/install/Uni.app"
test ! -e "$OWNED/support/bin/context"
test -f "$OWNED/support/contexts.json"

PURGE="$TEST_DIRECTORY/purge"
mkdir -p "$PURGE"
install_redirected "$PURGE"
printf '%s\n' 'unknown sibling' > "$PURGE/support/keep.txt"
mkdir -p "$PURGE/support/icons"
printf '%s\n' 'owned icon' > "$PURGE/support/icons/owned-icon.png"
printf '%s\n' 'icon keep' > "$PURGE/support/icons/keep.txt"
printf '%s\n' 'bin keep' > "$PURGE/support/bin/keep.txt"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"custom":{"_0":"'"$PURGE/support/icons/owned-icon.png"'"}},"id":"owned","name":"Owned","subtitle":"","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$PURGE/support/contexts.json"
INSTALL_ROOT="$PURGE/install" CONTEXT_LAUNCHER_HOME="$PURGE/support" ./uninstall.sh --purge-data
test -d "$PURGE/support"
test "$(cat "$PURGE/support/keep.txt")" = 'unknown sibling'
test ! -e "$PURGE/support/contexts.json"
test ! -e "$PURGE/support/icons/owned-icon.png"
test "$(cat "$PURGE/support/icons/keep.txt")" = 'icon keep'
test ! -e "$PURGE/support/bin/context"
test "$(cat "$PURGE/support/bin/keep.txt")" = 'bin keep'
test ! -e "$PURGE/support/.context-launcher-install"

EMPTY_PURGE="$TEST_DIRECTORY/empty-purge"
mkdir -p "$EMPTY_PURGE"
install_redirected "$EMPTY_PURGE"
INSTALL_ROOT="$EMPTY_PURGE/install" CONTEXT_LAUNCHER_HOME="$EMPTY_PURGE/support" ./uninstall.sh --purge-data
test ! -e "$EMPTY_PURGE/support"

BROAD_HOME="$TEST_DIRECTORY/home-like"
mkdir -p "$BROAD_HOME"
test "$(HOME="$BROAD_HOME" INSTALL_ROOT="$BROAD_HOME/install" CONTEXT_LAUNCHER_HOME="$BROAD_HOME" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$BROAD_HOME"
BROAD_PARENT="$TEST_DIRECTORY/broad-parent"
mkdir -p "$BROAD_PARENT"
test "$(INSTALL_ROOT="$BROAD_PARENT/install" CONTEXT_LAUNCHER_HOME="$BROAD_PARENT" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$BROAD_PARENT"

SYMLINK_TARGET="$TEST_DIRECTORY/symlink-target"
mkdir -p "$SYMLINK_TARGET"
install_redirected "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET/support" "$TEST_DIRECTORY/symlink-support"
test "$(INSTALL_ROOT="$SYMLINK_TARGET/install" CONTEXT_LAUNCHER_HOME="$TEST_DIRECTORY/symlink-support" ./uninstall.sh --purge-data >/dev/null 2>&1; echo $?)" != 0
test -d "$SYMLINK_TARGET/support"

LOCKED="$TEST_DIRECTORY/locked"
mkdir -p "$LOCKED/support/.context-launcher-install.lock"
test "$(INSTALL_ROOT="$LOCKED/install" CONTEXT_LAUNCHER_HOME="$LOCKED/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test ! -e "$LOCKED/install/Context Launcher.app"

INSTALL_LOCKED="$TEST_DIRECTORY/install-locked"
mkdir -p "$INSTALL_LOCKED/install/.context-launcher-install.lock"
test "$(INSTALL_ROOT="$INSTALL_LOCKED/install" CONTEXT_LAUNCHER_HOME="$INSTALL_LOCKED/other-support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test ! -e "$INSTALL_LOCKED/install/Context Launcher.app"

UNINSTALL_LOCKED="$TEST_DIRECTORY/uninstall-locked"
mkdir -p "$UNINSTALL_LOCKED"
install_redirected "$UNINSTALL_LOCKED"
mkdir "$UNINSTALL_LOCKED/install/.context-launcher-install.lock"
test "$(INSTALL_ROOT="$UNINSTALL_LOCKED/install" CONTEXT_LAUNCHER_HOME="$UNINSTALL_LOCKED/support" ./uninstall.sh >/dev/null 2>&1; echo $?)" != 0
test -e "$UNINSTALL_LOCKED/install/Context Launcher.app"
rmdir "$UNINSTALL_LOCKED/install/.context-launcher-install.lock"
INSTALL_ROOT="$UNINSTALL_LOCKED/install" CONTEXT_LAUNCHER_HOME="$UNINSTALL_LOCKED/support" ./uninstall.sh
test ! -e "$UNINSTALL_LOCKED/install/Context Launcher.app"

SIGNALLED_UNINSTALL="$TEST_DIRECTORY/signalled-uninstall"
mkdir -p "$SIGNALLED_UNINSTALL/fake-bin"
install_redirected "$SIGNALLED_UNINSTALL"
cat > "$SIGNALLED_UNINSTALL/fake-bin/rm" <<'EOF'
#!/bin/sh
case "$*" in
    *'Context Launcher.app'*)
        kill "-$UNINSTALL_TEST_SIGNAL" "$PPID"
        exit 0
        ;;
esac
exec /bin/rm "$@"
EOF
chmod +x "$SIGNALLED_UNINSTALL/fake-bin/rm"
for signal_name in HUP INT TERM; do
    test "$(UNINSTALL_TEST_SIGNAL="$signal_name" PATH="$SIGNALLED_UNINSTALL/fake-bin:$PATH" INSTALL_ROOT="$SIGNALLED_UNINSTALL/install" CONTEXT_LAUNCHER_HOME="$SIGNALLED_UNINSTALL/support" ./uninstall.sh >/dev/null 2>&1; echo $?)" != 0
    test -e "$SIGNALLED_UNINSTALL/install/Context Launcher.app"
    test -e "$SIGNALLED_UNINSTALL/install/New.app"
    test -x "$SIGNALLED_UNINSTALL/support/bin/context"
    test ! -e "$SIGNALLED_UNINSTALL/install/.context-launcher-install.lock"
done

ABSENT_INSTALL_ROOT="$TEST_DIRECTORY/absent-install-root"
mkdir -p "$ABSENT_INSTALL_ROOT"
install_redirected "$ABSENT_INSTALL_ROOT"
mv "$ABSENT_INSTALL_ROOT/install" "$ABSENT_INSTALL_ROOT/former-install"
test "$(INSTALL_ROOT="$ABSENT_INSTALL_ROOT/install" CONTEXT_LAUNCHER_HOME="$ABSENT_INSTALL_ROOT/support" ./uninstall.sh >/dev/null 2>&1; echo $?)" != 0
test ! -e "$ABSENT_INSTALL_ROOT/install"
test -e "$ABSENT_INSTALL_ROOT/former-install/Context Launcher.app"
test -x "$ABSENT_INSTALL_ROOT/support/bin/context"

EARLY_FAILURE="$TEST_DIRECTORY/early-failure"
mkdir -p "$EARLY_FAILURE"
test "$(CONTEXT_LAUNCHER_TEST_FAIL_EARLY=1 INSTALL_ROOT="$EARLY_FAILURE/install" CONTEXT_LAUNCHER_HOME="$EARLY_FAILURE/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
install_redirected "$EARLY_FAILURE"
test -e "$EARLY_FAILURE/install/Context Launcher.app"

ROLLBACK="$TEST_DIRECTORY/rollback"
mkdir -p "$ROLLBACK"
install_redirected "$ROLLBACK"
printf '%s\n' 'old application' > "$ROLLBACK/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp"
printf '%s\n' 'old cli' > "$ROLLBACK/support/bin/context"
printf '%s\n' 'old launcher' > "$ROLLBACK/install/Uni.app/marker"
test "$(CONTEXT_LAUNCHER_TEST_FAIL_AFTER_COPY=1 INSTALL_ROOT="$ROLLBACK/install" CONTEXT_LAUNCHER_HOME="$ROLLBACK/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
test "$(cat "$ROLLBACK/install/Context Launcher.app/Contents/MacOS/ContextLauncherApp")" = 'old application'
test "$(cat "$ROLLBACK/support/bin/context")" = 'old cli'
test "$(cat "$ROLLBACK/install/Uni.app/marker")" = 'old launcher'

NEWLINE_INJECTION="$TEST_DIRECTORY/newline-injection"
mkdir -p "$NEWLINE_INJECTION/install" "$NEWLINE_INJECTION/support"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"symbol":{"_0":"folder"}},"id":"safe","name":"Safe\nvictim","subtitle":"","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$NEWLINE_INJECTION/support/contexts.json"
make_decoy "$NEWLINE_INJECTION/install/victim.app" "dev.contextlauncher.context.victim" "newline victim"
test "$(INSTALL_ROOT="$NEWLINE_INJECTION/install" CONTEXT_LAUNCHER_HOME="$NEWLINE_INJECTION/support" ./install.sh --skip-build >/dev/null 2>&1; echo $?)" != 0
assert_decoy "$NEWLINE_INJECTION/install/victim.app" "newline victim"

UNINSTALL_INJECTION="$TEST_DIRECTORY/uninstall-injection"
mkdir -p "$UNINSTALL_INJECTION"
install_redirected "$UNINSTALL_INJECTION"
printf '%s\n' \
    '{"contexts":[{"applications":[],"icon":{"symbol":{"_0":"folder"}},"id":"safe","name":"Safe\nvictim","subtitle":"","urls":[],"vscodeProjects":[]}],"version":1}' \
    > "$UNINSTALL_INJECTION/support/contexts.json"
make_decoy "$UNINSTALL_INJECTION/install/victim.app" "dev.contextlauncher.context.victim" "uninstall victim"
INSTALL_ROOT="$UNINSTALL_INJECTION/install" CONTEXT_LAUNCHER_HOME="$UNINSTALL_INJECTION/support" ./uninstall.sh
assert_decoy "$UNINSTALL_INJECTION/install/victim.app" "uninstall victim"
