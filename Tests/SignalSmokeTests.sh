#!/bin/sh
set -eu

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -R "$TEST_DIRECTORY"' EXIT

mkdir -p "$TEST_DIRECTORY/fake-bin"
printf '%s\n' \
    '#!/bin/sh' \
    ': > "$SIGNAL_TEST_MARKER"' \
    'while [ ! -e "$SIGNAL_TEST_RELEASE" ]; do sleep 0.05; done' \
    'exec /bin/cp "$@"' \
    > "$TEST_DIRECTORY/fake-bin/cp"
chmod +x "$TEST_DIRECTORY/fake-bin/cp"

run_signalled() {
    signal_name=$1
    expected_status=$2
    marker=$3
    release=$4
    shift 4

    set +e
    SIGNAL_TEST_SIGNAL="$signal_name" SIGNAL_TEST_MARKER="$marker" \
        SIGNAL_TEST_RELEASE="$release" \
        /bin/sh -c '
            target_pid=$$
            (
                attempts=0
                while [ ! -e "$SIGNAL_TEST_MARKER" ] && [ "$attempts" -lt 100 ]; do
                    sleep 0.05
                    attempts=$((attempts + 1))
                done
                test -e "$SIGNAL_TEST_MARKER" || exit 99
                kill "-$SIGNAL_TEST_SIGNAL" "$target_pid"
                : > "$SIGNAL_TEST_RELEASE"
            ) &
            exec "$@"
        ' signal-controller "$@"
    status=$?
    set -e

    test -e "$marker"
    test "$status" -eq "$expected_status"
}

run_assemble_signal() {
    signal_name=$1
    expected_status=$2
    root="$TEST_DIRECTORY/assemble-$signal_name"
    marker="$root-marker"
    release="$root-release"
    application="$root/Context Launcher.app"
    PATH="$TEST_DIRECTORY/fake-bin:$PATH" \
        run_signalled "$signal_name" "$expected_status" "$marker" "$release" \
        sh scripts/assemble-app.sh "$PWD/.build/release" "$application"
    test ! -e "$application"
}

run_install_signal() {
    signal_name=$1
    expected_status=$2
    root="$TEST_DIRECTORY/install-$signal_name"
    marker="$root-marker"
    release="$root-release"
    PATH="$TEST_DIRECTORY/fake-bin:$PATH" \
        INSTALL_ROOT="$root/install" CONTEXT_LAUNCHER_HOME="$root/support" \
        run_signalled "$signal_name" "$expected_status" "$marker" "$release" \
        ./install.sh --skip-build
    test ! -e "$root/install/Context Launcher.app"
    test ! -e "$root/install/.context-launcher-install.lock"
    test ! -e "$root/support/.context-launcher-install.lock"
}

for signal_status in HUP:129 INT:130 TERM:143; do
    signal_name=${signal_status%:*}
    expected_status=${signal_status#*:}
    run_assemble_signal "$signal_name" "$expected_status"
    run_install_signal "$signal_name" "$expected_status"
done
