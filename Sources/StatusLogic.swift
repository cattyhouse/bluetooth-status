import Foundation

enum ConnectionState: Equatable {
    case unavailable
    case missing
    case disconnected
    case connected
}

enum StatusGlyph: Equatable {
    case connected
    case disconnected
    case unavailable
}

struct BluetoothDeviceInfo: Equatable {
    let name: String
    let address: String
    let isConnected: Bool
}

struct BluetoothStatusSnapshot: Equatable {
    let devices: [BluetoothDeviceInfo]?

    var state: ConnectionState {
        StatusLogic.state(devices: devices)
    }

    var connectedDevices: [BluetoothDeviceInfo] {
        devices?.filter(\.isConnected) ?? []
    }
}

struct StatusDescriptor: Equatable {
    let state: ConnectionState
    let statusText: String
    let glyph: StatusGlyph
}

enum AudioDeviceClassifier {
    static let audioDeviceClassMajor: UInt32 = 0x04

    static func matches(
        deviceClassMajor: UInt32,
        isHandsFreeDevice: Bool,
        isHandsFreeAudioGateway: Bool
    ) -> Bool {
        deviceClassMajor == audioDeviceClassMajor ||
            isHandsFreeDevice ||
            isHandsFreeAudioGateway
    }
}

struct RefreshGate {
    private var inFlight = false
    private var pending = false

    mutating func begin() -> Bool {
        guard !inFlight else {
            pending = true
            return false
        }
        inFlight = true
        return true
    }

    mutating func finish() -> Bool {
        guard inFlight else { return false }
        inFlight = false
        let shouldRefreshAgain = pending
        pending = false
        return shouldRefreshAgain
    }
}

enum StatusLogic {
    static func normalizedAddress(_ raw: String) -> String {
        raw.lowercased().filter { $0 != ":" && $0 != "-" && !$0.isWhitespace }
    }

    static func state(devices: [BluetoothDeviceInfo]?) -> ConnectionState {
        guard let devices else {
            return .unavailable
        }
        guard !devices.isEmpty else {
            return .missing
        }
        return devices.contains(where: \.isConnected) ? .connected : .disconnected
    }

    static func sorted(_ devices: [BluetoothDeviceInfo]) -> [BluetoothDeviceInfo] {
        devices.sorted { left, right in
            if left.isConnected != right.isConnected {
                return left.isConnected && !right.isConnected
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    static func descriptor(for state: ConnectionState) -> StatusDescriptor {
        switch state {
        case .connected:
            return StatusDescriptor(state: state, statusText: "Connected", glyph: .connected)
        case .disconnected:
            return StatusDescriptor(state: state, statusText: "Disconnected", glyph: .disconnected)
        case .missing:
            return StatusDescriptor(state: state, statusText: "No Bluetooth audio devices found", glyph: .unavailable)
        case .unavailable:
            return StatusDescriptor(state: state, statusText: "Unable to read Bluetooth status", glyph: .unavailable)
        }
    }
}
