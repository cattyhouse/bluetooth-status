import Foundation

enum ConnectionState: Equatable {
    case unavailable
    case missing
    case disconnected
    case connected
    case disabled
}

enum StatusGlyph: Equatable {
    case connected
    case disconnected
    case unavailable
}

/// Bluetooth controller power, independent of the paired-device list.
enum BluetoothPowerState: Equatable {
    case on
    case off
    case unknown
}

/// The subset of `IOBluetoothDevice` the reader needs. It exists so device
/// aggregation can be exercised with test doubles; `IOBluetoothDevice`
/// conforms in `BluetoothReader.swift`.
protocol BluetoothDeviceDescriptor {
    var nameOrAddress: String? { get }
    var addressString: String? { get }
    var deviceClassMajor: UInt32 { get }
    var isHandsFreeDevice: Bool { get }
    var isHandsFreeAudioGateway: Bool { get }
    func isConnected() -> Bool
}

struct BluetoothDeviceInfo: Equatable {
    let name: String
    let address: String
    let isConnected: Bool
}

struct BluetoothStatusSnapshot: Equatable {
    let devices: [BluetoothDeviceInfo]?
    let powerState: BluetoothPowerState

    init(devices: [BluetoothDeviceInfo]?, powerState: BluetoothPowerState = .unknown) {
        self.devices = devices
        self.powerState = powerState
    }

    var state: ConnectionState {
        StatusLogic.state(devices: devices, powerState: powerState)
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

/// Turns a possibly-untrusted paired-device list into the app's model.
///
/// An element that cannot be interpreted as a Bluetooth device is a contract
/// failure, not an absent device: the whole enumeration is reported as
/// unavailable so the UI never claims "disconnected" from dropped data.
enum BluetoothDeviceAggregator {
    static func audioDevices(from objects: [Any]?) -> [BluetoothDeviceInfo]? {
        guard let objects else { return nil }

        var devices: [BluetoothDeviceInfo] = []
        devices.reserveCapacity(objects.count)
        for object in objects {
            guard let device = object as? BluetoothDeviceDescriptor else {
                return nil
            }
            guard AudioDeviceClassifier.matches(
                deviceClassMajor: device.deviceClassMajor,
                isHandsFreeDevice: device.isHandsFreeDevice,
                isHandsFreeAudioGateway: device.isHandsFreeAudioGateway
            ) else {
                continue
            }
            let address = device.addressString ?? ""
            let name: String
            if let deviceName = device.nameOrAddress, !deviceName.isEmpty {
                name = deviceName
            } else if !address.isEmpty {
                name = address
            } else {
                name = "Unknown device"
            }
            devices.append(BluetoothDeviceInfo(
                name: name,
                address: address,
                isConnected: device.isConnected()
            ))
        }
        return StatusLogic.sorted(devices)
    }
}

struct RefreshGate {
    private var inFlight = false
    private var pending = false

    var isIdle: Bool { !inFlight }

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

    static func state(
        devices: [BluetoothDeviceInfo]?,
        powerState: BluetoothPowerState = .unknown
    ) -> ConnectionState {
        if powerState == .off {
            return .disabled
        }
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
            let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return normalizedAddress(left.address) < normalizedAddress(right.address)
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
        case .disabled:
            return StatusDescriptor(state: state, statusText: "Bluetooth is off", glyph: .unavailable)
        }
    }

    /// Escape a value for the line-oriented `--dump` format.
    ///
    /// Device names are attacker-influenced, so line breaks, control
    /// characters, and escape sequences must never reach the output unencoded.
    static func escaped(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.utf8.count)
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) {
                    result += String(format: "\\u{%02X}", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    /// Make an untrusted device name safe for menu and tooltip text: control
    /// characters are dropped and the result is bounded.
    static func displayName(_ raw: String) -> String {
        let printable = raw.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 &&
                scalar.value != 0x7F &&
                !(0x80...0x9F).contains(scalar.value)
        }
        var name = String(String.UnicodeScalarView(printable))
        if name.count > 64 {
            name = String(name.prefix(63)) + "…"
        }
        if name.isEmpty {
            name = "Unnamed device"
        }
        return name
    }

    /// One key=value line per field; the only place `--dump` text is built.
    static func dumpLines(for snapshot: BluetoothStatusSnapshot) -> [String] {
        let descriptor = descriptor(for: snapshot.state)
        var lines = [
            "state=\(String(describing: snapshot.state))",
            "status=\(escaped(descriptor.statusText))",
            "connected=\(snapshot.connectedDevices.count)"
        ]

        if let devices = snapshot.devices {
            lines.append("audio_devices=\(devices.count)")
            for device in devices {
                lines.append(
                    "device=\(escaped(device.name)) address=\(escaped(device.address)) connected=\(device.isConnected)"
                )
            }
        } else {
            lines.append("audio_devices=unavailable")
        }
        return lines
    }

    static func liveUpdateNotice(available: Bool) -> String? {
        available ? nil : "Live updates unavailable; using periodic refresh"
    }
}
