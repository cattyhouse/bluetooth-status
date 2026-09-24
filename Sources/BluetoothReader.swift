import Foundation
import IOBluetooth

enum BluetoothStatusReader {
    static func readSnapshot() -> BluetoothStatusSnapshot {
        BluetoothStatusSnapshot(devices: readAudioDevices())
    }

    static func readAudioDevices() -> [BluetoothDeviceInfo]? {
        guard let objects = IOBluetoothDevice.pairedDevices() else {
            return nil
        }

        let devices = objects.compactMap { object -> BluetoothDeviceInfo? in
            guard let device = object as? IOBluetoothDevice,
                  isAudioDevice(device) else {
                return nil
            }
            return BluetoothDeviceInfo(
                name: device.nameOrAddress,
                address: device.addressString,
                isConnected: device.isConnected()
            )
        }
        return StatusLogic.sorted(devices)
    }

    static func dump() -> String {
        let snapshot = readSnapshot()
        let descriptor = StatusLogic.descriptor(for: snapshot.state)
        var lines = [
            "state=\(String(describing: snapshot.state))",
            "status=\(descriptor.statusText)",
            "connected=\(snapshot.connectedDevices.count)"
        ]

        if let devices = snapshot.devices {
            lines.append("audio_devices=\(devices.count)")
            for device in devices {
                lines.append("device=\(device.name) address=\(device.address) connected=\(device.isConnected)")
            }
        } else {
            lines.append("audio_devices=unavailable")
        }
        return lines.joined(separator: "\n")
    }

    private static func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        // Class major Audio covers ordinary Bluetooth headsets/earbuds. The
        // HFP checks also catch devices whose cached class is incomplete.
        AudioDeviceClassifier.matches(
            deviceClassMajor: device.deviceClassMajor,
            isHandsFreeDevice: device.isHandsFreeDevice,
            isHandsFreeAudioGateway: device.isHandsFreeAudioGateway
        )
    }
}
