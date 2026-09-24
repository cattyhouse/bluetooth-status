#!/bin/sh

set -eu
umask 022

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_APP="$PROJECT_ROOT/build/BluetoothStatus.app"
# Paths are overridable so install/rollback can be exercised in isolated
# temporary directories; production defaults are unchanged.
INSTALL_APP="${BLUETOOTH_STATUS_INSTALL_APP:-/Applications/BluetoothStatus.app}"
STAGE_PARENT="${BLUETOOTH_STATUS_STAGE_PARENT:-/Applications}"
TARGET_DIR="${BLUETOOTH_STATUS_LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
LABEL="com.justin.bluetoothstatus"
SOURCE_PLIST="$PROJECT_ROOT/LaunchAgent/$LABEL.plist"
TARGET_PLIST="$TARGET_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"
INSTALLED_EXECUTABLE="$INSTALL_APP/Contents/MacOS/BluetoothStatus"
DEVELOPMENT_EXECUTABLE="$PROJECT_ROOT/build/BluetoothStatus.app/Contents/MacOS/BluetoothStatus"

[ -d "$SOURCE_APP" ] || { echo "Missing build app: $SOURCE_APP" >&2; exit 1; }
[ -f "$SOURCE_PLIST" ] || { echo "Missing LaunchAgent template: $SOURCE_PLIST" >&2; exit 1; }
[ -x "$SOURCE_APP/Contents/MacOS/BluetoothStatus" ] || { echo "Source executable is not runnable" >&2; exit 1; }
[ -d "$STAGE_PARENT" ] || { echo "Stage directory is unavailable: $STAGE_PARENT" >&2; exit 1; }
mkdir -p "$TARGET_DIR"

stage_root=
plist_tmp=
old_app=
old_plist=
had_old_app=0
had_old_plist=0
app_replaced=0
plist_replaced=0
service_was_booted_out=0

rollback() {
    status=$?
    trap - EXIT INT TERM HUP
    if [ "$status" -ne 0 ]; then
        echo "Install failed; rolling back" >&2
        if [ "$plist_replaced" -eq 1 ]; then
            if [ "$had_old_plist" -eq 1 ]; then
                cp "$old_plist" "$TARGET_PLIST" 2>/dev/null || true
            else
                rm -f "$TARGET_PLIST" 2>/dev/null || true
            fi
        fi
        if [ "$app_replaced" -eq 1 ]; then
            rm -rf "$INSTALL_APP" 2>/dev/null || true
        fi
        if [ "$had_old_app" -eq 1 ] && [ -e "$old_app" ]; then
            mv "$old_app" "$INSTALL_APP" 2>/dev/null || true
        fi
        # Restore the previous service state only if this run stopped it.
        # A failure before step 2 must leave a running service untouched.
        if [ "$service_was_booted_out" -eq 1 ]; then
            launchctl bootout "$SERVICE" 2>/dev/null || true
            if [ -f "$TARGET_PLIST" ]; then
                launchctl bootstrap "$DOMAIN" "$TARGET_PLIST" >/dev/null 2>&1 || true
            fi
        fi
    fi
    [ -z "$stage_root" ] || rm -rf "$stage_root"
    [ -z "$plist_tmp" ] || rm -f "$plist_tmp"
    exit "$status"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

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

printf '%s\n' '[1/5] Prepare and validate app and LaunchAgent'
stage_root=$(mktemp -d "$STAGE_PARENT/.bluetooth-status-install-XXXXXX")
plist_tmp=$(mktemp "$TARGET_DIR/.$LABEL.XXXXXX")
ditto "$SOURCE_APP" "$stage_root/BluetoothStatus.app"
test -x "$stage_root/BluetoothStatus.app/Contents/MacOS/BluetoothStatus"
cp "$SOURCE_PLIST" "$plist_tmp"
chmod 644 "$plist_tmp"
plutil -lint "$plist_tmp" >/dev/null

printf '%s\n' '[2/5] Stop existing LaunchAgent and app processes'
launchctl bootout "$SERVICE" 2>/dev/null || true
service_was_booted_out=1
stop_app_processes

printf '%s\n' '[3/5] Back up and replace app'
if [ -e "$INSTALL_APP" ] || [ -L "$INSTALL_APP" ]; then
    old_app="$stage_root/previous-BluetoothStatus.app"
    mv "$INSTALL_APP" "$old_app"
    had_old_app=1
fi
if [ -e "$TARGET_PLIST" ]; then
    old_plist="$stage_root/previous-$LABEL.plist"
    cp "$TARGET_PLIST" "$old_plist"
    had_old_plist=1
fi
mv "$stage_root/BluetoothStatus.app" "$INSTALL_APP"
app_replaced=1

printf '%s\n' '[4/5] Install LaunchAgent and load service'
mv "$plist_tmp" "$TARGET_PLIST"
plist_replaced=1
chmod 644 "$TARGET_PLIST"
launchctl enable "$SERVICE" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$TARGET_PLIST"

printf '%s\n' '[5/5] Wait for launchd'
state=
pid=
for attempt in 1 2 3 4 5; do
    if launchctl print "$SERVICE" 2>/dev/null | grep -Eq '^[[:space:]]*state = running$'; then
        state=running
        pid=$(launchctl print "$SERVICE" 2>/dev/null | awk -F'= ' '/^[[:space:]]*pid =/ {print $2; exit}')
        break
    fi
    sleep 1
done
[ "$state" = running ] || { echo "LaunchAgent did not reach running (state=${state:-unknown})" >&2; exit 1; }

printf 'Done: App=%s\n' "$INSTALL_APP"
printf '     LaunchAgent=%s\n' "$TARGET_PLIST"
printf '     launchd state=%s pid=%s\n' "$state" "${pid:-none}"
