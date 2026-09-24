# Bluetooth Status Plan

## Goal

Show Bluetooth audio connection state in the macOS menu bar. Read `IOBluetoothDevice.isConnected()` only; do not read battery data or change Bluetooth state.

## Completed

- Pure Swift state and sorting logic
- AppKit menu bar app with event-driven updates
- IOBluetooth connect callback and disconnect notifications
- Wake, activation, device-change, and appearance refresh handling
- 30-second recovery refresh and a 10-second deadline for each blocking read
- High-resolution vector status icons
- Accessibility label and value
- User-level LaunchAgent with crash recovery
- Atomic install and uninstall scripts with service-state-preserving rollback
- Unit tests, shell syntax checks, and an isolated install rollback/smoke test
- English runtime strings and configuration
- Escaped `--dump` fields and control-character-free menu names
- Bluetooth-off state from the public controller power state
- Visible degraded mode when connect notifications cannot be registered

## Acceptance

- Detect connected, disconnected, missing, unavailable, and Bluetooth-off states
- Enumerate paired Bluetooth audio devices without hard-coded addresses
- Never call connection, pairing, or battery APIs
- Build with warnings treated as errors
- Install and run from `/Applications/BluetoothStatus.app`
- Start at login through `com.justin.bluetoothstatus`

## Verification

- `make test`: `StatusLogicTests: PASS` and `InstallRollbackTests: PASS`
- `make install`: overwrites the app and LaunchAgent, then reports `state=running`
- `make dump`: reports the current `isConnected()` state with escaped fields
- Install rollback test: a staging failure leaves a running service untouched
- App bundle: approximately 180 KB; resident memory approximately 40 MB (measured)
- Build and installed binaries have matching SHA-256 hashes
- No connection, pairing, battery, log, or `sudo` calls in `Sources/`
