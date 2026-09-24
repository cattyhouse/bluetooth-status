#!/bin/sh

# Exercises scripts/install.sh and scripts/uninstall.sh in isolated temporary
# directories with a fake launchctl. It proves that a failure during staging
# leaves a previously running service untouched (red on the old rollback) and
# that the success/repeat/uninstall paths stay consistent.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bluetooth-status-install-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

REPO="$TMP/repo"
mkdir -p \
    "$REPO/build/BluetoothStatus.app/Contents/MacOS" \
    "$REPO/scripts" \
    "$REPO/LaunchAgent" \
    "$TMP/bin" \
    "$TMP/Applications" \
    "$TMP/LaunchAgents"
cp "$ROOT/scripts/install.sh" "$ROOT/scripts/uninstall.sh" "$REPO/scripts/"
cp "$ROOT/LaunchAgent/com.justin.bluetoothstatus.plist" "$REPO/LaunchAgent/"
cp "$ROOT/Info.plist" "$REPO/build/BluetoothStatus.app/Contents/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$REPO/build/BluetoothStatus.app/Contents/MacOS/BluetoothStatus"
chmod +x "$REPO/build/BluetoothStatus.app/Contents/MacOS/BluetoothStatus"

cat > "$TMP/bin/launchctl" <<'EOF'
#!/bin/sh
printf '%s\n' "launchctl $*" >> "$INSTALL_TEST_LOG"
case "${1:-}" in
    print)
        printf 'gui/501/com.justin.bluetoothstatus = {\n\tstate = running\n\tpid = 4242\n}\n'
        ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/launchctl"

REAL_DITTO=$(command -v ditto)
cat > "$TMP/bin/ditto" <<EOF
#!/bin/sh
if [ "\${INSTALL_TEST_FAIL_DITTO:-0}" = "1" ]; then
    echo "ditto: simulated failure" >&2
    exit 1
fi
exec "$REAL_DITTO" "\$@"
EOF
chmod +x "$TMP/bin/ditto"

PATH="$TMP/bin:$PATH"
export PATH
export BLUETOOTH_STATUS_INSTALL_APP="$TMP/Applications/BluetoothStatus.app"
export BLUETOOTH_STATUS_STAGE_PARENT="$TMP/Applications"
export BLUETOOTH_STATUS_LAUNCH_AGENT_DIR="$TMP/LaunchAgents"
export INSTALL_TEST_LOG="$TMP/launchctl.log"

# Scenario 1: a staging failure must not boot out a running service.
: > "$INSTALL_TEST_LOG"
if INSTALL_TEST_FAIL_DITTO=1 sh "$REPO/scripts/install.sh" >"$TMP/scenario1.out" 2>&1; then
    echo "FAIL: install succeeded although staging failed" >&2
    exit 1
fi
if grep -q "bootout" "$INSTALL_TEST_LOG"; then
    echo "FAIL: staging failure booted out the existing service" >&2
    cat "$INSTALL_TEST_LOG" >&2
    exit 1
fi
if [ -e "$BLUETOOTH_STATUS_INSTALL_APP" ]; then
    echo "FAIL: staging failure left a partial app" >&2
    exit 1
fi
if ls -A "$TMP/Applications" 2>/dev/null | grep -q '^\.bluetooth-status-install-'; then
    echo "FAIL: staging failure left a temporary directory" >&2
    exit 1
fi

# Scenario 2: the success path installs both files and reports readiness.
: > "$INSTALL_TEST_LOG"
sh "$REPO/scripts/install.sh" >"$TMP/scenario2.out" 2>&1 || {
    cat "$TMP/scenario2.out" >&2
    exit 1
}
grep -q "state=running" "$TMP/scenario2.out" || {
    echo "FAIL: success output missing state=running" >&2
    cat "$TMP/scenario2.out" >&2
    exit 1
}
test -x "$BLUETOOTH_STATUS_INSTALL_APP/Contents/MacOS/BluetoothStatus" || {
    echo "FAIL: installed app is not runnable" >&2
    exit 1
}
test -f "$BLUETOOTH_STATUS_LAUNCH_AGENT_DIR/com.justin.bluetoothstatus.plist" || {
    echo "FAIL: installed plist missing" >&2
    exit 1
}
grep -q "bootstrap" "$INSTALL_TEST_LOG" || {
    echo "FAIL: install never bootstrapped the service" >&2
    exit 1
}

# Scenario 3: repeating install must stay consistent.
sh "$REPO/scripts/install.sh" >"$TMP/scenario3.out" 2>&1 || {
    cat "$TMP/scenario3.out" >&2
    exit 1
}

# Scenario 4: uninstall removes both artifacts through the same overrides.
sh "$REPO/scripts/uninstall.sh" --remove-app >"$TMP/scenario4.out" 2>&1 || {
    cat "$TMP/scenario4.out" >&2
    exit 1
}
if [ -e "$BLUETOOTH_STATUS_INSTALL_APP" ]; then
    echo "FAIL: uninstall left the app" >&2
    exit 1
fi
if [ -e "$BLUETOOTH_STATUS_LAUNCH_AGENT_DIR/com.justin.bluetoothstatus.plist" ]; then
    echo "FAIL: uninstall left the LaunchAgent" >&2
    exit 1
fi

printf '%s\n' "InstallRollbackTests: PASS"
