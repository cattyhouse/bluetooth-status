> macOS does not clearly show whether earbuds are connected; this app adds that status.

[Chinese](README.md) | [English](README.en.md)

# Bluetooth Status

A read-only macOS menu bar app that shows whether Bluetooth audio devices are connected.

## Features

- Enumerates paired Bluetooth audio devices without hard-coded addresses.
- Shows a high-resolution vector `B` when connected.
- Shows a crossed-out `B` when all audio devices are disconnected.
- Shows `?` when no audio device is found or the system cannot enumerate devices.
- Shows `?` and "Bluetooth is off" when the controller is powered off (public `IOBluetoothHostController.powerState`).
- Uses a vector icon with menu-bar contrast: white on dark bars, black on light bars.
- Updates from IOBluetooth connect/disconnect events, wake/activation events, device changes, and appearance changes.
- Bounds every blocking read with a 10-second deadline and recovers on later refreshes.
- Escapes line breaks and control characters in `--dump`, and strips them from menu text, so a device name cannot forge output lines or inject terminal sequences.
- Surfaces a degraded notice when connect notifications cannot be registered; the 30-second refresh still runs.
- Uses a 30-second recovery refresh and a manual Refresh command.
- Provides an accessible status label and value.
- Installs as a user LaunchAgent with crash recovery.

## State Sources

The app reads only:

```text
IOBluetoothDevice.pairedDevices()
device.nameOrAddress
device.addressString
device.isConnected()
IOBluetoothHostController.default().powerState
```

Controller power state distinguishes "Bluetooth is off" from the other states. If the paired list contains an element that cannot be interpreted as a device, the list is reported as unavailable instead of silently dropping it and claiming "disconnected".

A device is included when its Bluetooth Device Class Major is Audio, or when it reports Hands-Free or Hands-Free Audio Gateway. This favors broad headset detection, but some Bluetooth speakers may also appear.

The app does not read battery data, connect, disconnect, pair, unpair, or modify Bluetooth settings.

## Build

Command Line Tools are sufficient; a full Xcode installation is not required.

```sh
cd ~/make/bluetooth-status
make test
make
```

`make` targets `uname -m` by default (arm64 or x86_64); override with `make TARGET_ARCH=arm64`. `make test` runs the Swift unit tests, shell syntax checks, and an isolated install/rollback smoke test that uses temporary directories and a launchctl stub, so it never touches the real system.

Build output:

```text
build/BluetoothStatus.app
```

## Run

```sh
make run
```

Or:

```sh
open build/BluetoothStatus.app
```

The app is an `LSUIElement` and has no Dock icon.

## Command-line Check

```sh
make dump
```

Example:

```text
state=connected
status=Connected
connected=1
audio_devices=2
device=Redmi Buds 6 address=00:11:22:33:44:55 connected=true
device=Studio Headphones address=AA-BB-CC-DD-EE-FF connected=false
```

`--dump` escapes line breaks, backslashes, and control characters in device names and addresses (a newline prints as the literal `\n`, ESC as `\u{1B}`). The number of output lines is fixed by the fields, so a device name cannot forge a `state=` line or emit terminal control sequences.

## Login Installation

Install or update the app and LaunchAgent:

```sh
cd ~/make/bluetooth-status
make install
```

This overwrites:

```text
/Applications/BluetoothStatus.app
~/Library/LaunchAgents/com.justin.bluetoothstatus.plist
```

The installer stages and validates both files, reloads launchd, waits for `state=running`, and attempts to restore the previous files if installation fails. Repeating `make install` is supported.

Check the service:

```sh
make login-item-status
```

Remove the login item but keep the app:

```sh
make uninstall-login-item
```

Remove both the login item and the installed app:

```sh
make uninstall
```

The LaunchAgent uses `KeepAlive.SuccessfulExit=false`: abnormal exits restart the app, while a normal quit does not.

## Privacy

The app uses public read-only APIs only. It does not read battery data, use private APIs, run `sudo`, or modify Bluetooth system configuration.
