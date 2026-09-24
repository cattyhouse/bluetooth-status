> macOS does not clearly show whether earbuds are connected; this app adds that status.

[Chinese](README.md) | [English](README.en.md)

# Bluetooth Status

A read-only macOS menu bar app that shows whether Bluetooth audio devices are connected.

## Features

- Enumerates paired Bluetooth audio devices without hard-coded addresses.
- Shows a high-resolution vector `B` when connected.
- Shows a crossed-out `B` when all audio devices are disconnected.
- Shows `?` when no audio device is found or the system cannot enumerate devices.
- Uses a vector icon with menu-bar contrast: white on dark bars, black on light bars.
- Updates from IOBluetooth connect/disconnect events, wake/activation events, device changes, and appearance changes.
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
```

A device is included when its Bluetooth Device Class Major is Audio, or when it reports Hands-Free or Hands-Free Audio Gateway. This favors broad headset detection, but some Bluetooth speakers may also appear.

The app does not read battery data, connect, disconnect, pair, unpair, or modify Bluetooth settings.

## Build

Command Line Tools are sufficient; a full Xcode installation is not required.

```sh
cd ~/make/bluetooth-status
make test
make
```

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
