#!/bin/sh

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Paths are overridable so uninstall can be exercised in isolated temporary
# directories; production defaults are unchanged.
INSTALL_APP="${BLUETOOTH_STATUS_INSTALL_APP:-/Applications/BluetoothStatus.app}"
LABEL="com.justin.bluetoothstatus"
TARGET_DIR="${BLUETOOTH_STATUS_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
TARGET_PLIST="$TARGET_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"
INSTALLED_EXECUTABLE="$INSTALL_APP/Contents/MacOS/BluetoothStatus"
DEVELOPMENT_EXECUTABLE="$PROJECT_ROOT/build/BluetoothStatus.app/Contents/MacOS/BluetoothStatus"

stop_app_processes() {
    pids=$(ps -axo pid=,comm= | awk -v installed="$INSTALLED_EXECUTABLE" -v development="$DEVELOPMENT_EXECUTABLE" \
        '$2 == installed || $2 == development {print $1}')
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    for attempt in 1 2 3 4 5; do
        alive=0
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=1
                break
            fi
        done
        [ "$alive" -eq 0 ] && return 0
        sleep 1
    done
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "BluetoothStatus process did not exit: $pid" >&2
            return 1
        fi
    done
}

launchctl bootout "$SERVICE" 2>/dev/null || true
stop_app_processes
rm -f "$TARGET_PLIST"
printf '%s\n' "Removed $TARGET_PLIST"

if [ "${1:-}" = "--remove-app" ]; then
    rm -rf "$INSTALL_APP"
    printf '%s\n' "Removed $INSTALL_APP"
fi
