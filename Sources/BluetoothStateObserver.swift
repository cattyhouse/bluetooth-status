import CoreBluetooth
import Foundation

/// The Bluetooth stack states the app distinguishes.
enum BluetoothStackState: Equatable {
    case poweredOn
    case poweredOff
    case resetting
    case unauthorized
    case unsupported
    case unknown

    /// Whether this state can be trusted to announce Bluetooth switch changes.
    ///
    /// `unknown` carries no opinion: the framework has not reported a usable
    /// state yet, so the previous answer stays in effect.
    var reportsSwitchChanges: Bool? {
        switch self {
        case .poweredOn, .poweredOff, .resetting:
            return true
        case .unauthorized, .unsupported:
            return false
        case .unknown:
            return nil
        }
    }
}

/// Watches the Bluetooth stack state and reports every change.
///
/// The IOBluetooth framework does not announce a Bluetooth switch change, but
/// CoreBluetooth does: the central manager delegate is called in the same
/// millisecond as the switch is flipped. The observer only listens; it never
/// scans, connects, pairs, or changes any Bluetooth setting.
final class BluetoothStateObserver: NSObject, CBCentralManagerDelegate {
    private let onChange: (BluetoothStackState) -> Void
    private var manager: CBCentralManager?

    /// The last state reported by the framework.
    private(set) var state: BluetoothStackState = .unknown

    init(onChange: @escaping (BluetoothStackState) -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Starts observing. The power alert is suppressed: the app must never
    /// put a "Turn On Bluetooth" dialog on screen, and creating the manager
    /// while Bluetooth is off must not power the radio on.
    func start() {
        guard manager == nil else { return }
        manager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func stop() {
        manager?.delegate = nil
        manager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = BluetoothStackState(central.state)
        guard newState != state else { return }
        state = newState
        onChange(newState)
    }
}

extension BluetoothStackState {
    init(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            self = .poweredOn
        case .poweredOff:
            self = .poweredOff
        case .resetting:
            self = .resetting
        case .unauthorized:
            self = .unauthorized
        case .unsupported:
            self = .unsupported
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}
