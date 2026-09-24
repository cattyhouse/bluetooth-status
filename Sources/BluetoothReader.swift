import Foundation
import IOBluetooth

/// Adapts the Objective-C device to the testable descriptor protocol. The
/// imported `String!` properties cannot satisfy `String?` requirements
/// directly, so the conversion happens here once.
private struct IOBluetoothDeviceDescriptor: BluetoothDeviceDescriptor {
    let device: IOBluetoothDevice

    var nameOrAddress: String? { device.nameOrAddress }
    var addressString: String? { device.addressString }
    var deviceClassMajor: UInt32 { device.deviceClassMajor }
    var isHandsFreeDevice: Bool { device.isHandsFreeDevice }
    var isHandsFreeAudioGateway: Bool { device.isHandsFreeAudioGateway }

    func isConnected() -> Bool {
        device.isConnected()
    }
}

enum BluetoothStatusReader {
    static func readSnapshot() -> BluetoothStatusSnapshot {
        BluetoothStatusSnapshot(
            devices: readAudioDevices(),
            powerState: readPowerState()
        )
    }

    static func readAudioDevices() -> [BluetoothDeviceInfo]? {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() else {
            return nil
        }
        let wrapped: [Any] = pairedDevices.map { object in
            if let device = object as? IOBluetoothDevice {
                return IOBluetoothDeviceDescriptor(device: device)
            }
            // Keep the unexpected element so the aggregator fails closed.
            return object
        }
        return BluetoothDeviceAggregator.audioDevices(from: wrapped)
    }

    static func readPowerState() -> BluetoothPowerState {
        guard let controller = IOBluetoothHostController.default() else {
            return .unknown
        }
        // BluetoothHCIPowerState: kBluetoothHCIPowerStateON = 0x01,
        // kBluetoothHCIPowerStateOFF = 0x00 (Bluetooth.h:2765-2767).
        switch controller.powerState.rawValue {
        case 0x01:
            return .on
        case 0x00:
            return .off
        default:
            return .unknown
        }
    }

    static func dump() -> String {
        StatusLogic.dumpLines(for: readSnapshot()).joined(separator: "\n")
    }
}
