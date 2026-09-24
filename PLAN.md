# Bluetooth Status Plan

## Goal

Show Bluetooth audio connection state in the macOS menu bar. Read `IOBluetoothDevice.isConnected()` only; do not read battery data or change Bluetooth state.

## Completed

- Pure Swift state and sorting logic
- AppKit menu bar app with event-driven updates
- IOBluetooth connect callback and disconnect notifications
- Wake, activation, device-change, and appearance refresh handling
- 30-second recovery refresh
- High-resolution vector status icons
- Accessibility label and value
- User-level LaunchAgent with crash recovery
- Atomic install and uninstall scripts
- Unit tests, shell syntax checks, and install smoke tests
- English runtime strings and configuration

## Acceptance

- Detect connected, disconnected, missing, and unavailable states
- Enumerate paired Bluetooth audio devices without hard-coded addresses
- Never call connection, pairing, or battery APIs
- Build with warnings treated as errors
- Install and run from `/Applications/BluetoothStatus.app`
- Start at login through `com.justin.bluetoothstatus`

## Verification

- `make test`: `StatusLogicTests: PASS`
- `make install`: overwrites the app and LaunchAgent, then reports `state=running`
- `make dump`: reports the current `isConnected()` state
- Installed footprint: approximately 12 MB
- Build and installed binaries have matching SHA-256 hashes
- No connection, pairing, battery, log, or `sudo` calls in `Sources/`
