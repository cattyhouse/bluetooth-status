import Foundation
import Darwin

@main
struct StatusLogicTests {
    static func main() {
        normalizedAddress()
        audioClassifier()
        connectedDevice()
        disconnectedDevices()
        missingDeviceList()
        unavailableDeviceList()
        sorting()
        refreshGateCoalescesEvents()
        descriptors()
        print("StatusLogicTests: PASS")
    }

    private static func normalizedAddress() {
        let actual = StatusLogic.normalizedAddress("00:11:22:33:44:55")
        expect(actual == "001122334455", "Address separators and case should normalize")
        expect(StatusLogic.normalizedAddress("not-an-address") == "notanaddress", "Hyphens should be removed")
        expect(StatusLogic.normalizedAddress("") == "", "Empty address should stay empty")
    }

    private static func audioClassifier() {
        expect(AudioDeviceClassifier.matches(
            deviceClassMajor: 0x04,
            isHandsFreeDevice: false,
            isHandsFreeAudioGateway: false
        ), "Audio class should match")
        expect(AudioDeviceClassifier.matches(
            deviceClassMajor: 0x01,
            isHandsFreeDevice: true,
            isHandsFreeAudioGateway: false
        ), "HFP device should match")
        expect(!AudioDeviceClassifier.matches(
            deviceClassMajor: 0x01,
            isHandsFreeDevice: false,
            isHandsFreeAudioGateway: false
        ), "Non-audio device should not match")
    }

    private static func connectedDevice() {
        let devices = [
            device(name: "Keyboard", connected: false),
            device(name: "Earbuds", connected: true)
        ]
        expect(StatusLogic.state(devices: devices) == .connected, "Any connected audio device should be connected")
    }

    private static func disconnectedDevices() {
        let devices = [
            device(name: "Earbuds", connected: false),
            device(name: "Headset", connected: false)
        ]
        expect(StatusLogic.state(devices: devices) == .disconnected, "All disconnected devices should be disconnected")
    }

    private static func missingDeviceList() {
        expect(StatusLogic.state(devices: []) == .missing, "Empty list should be missing")
    }

    private static func unavailableDeviceList() {
        expect(StatusLogic.state(devices: nil) == .unavailable, "Nil list should be unavailable")
    }

    private static func sorting() {
        let devices = [
            device(name: "Zulu", connected: false),
            device(name: "Alpha", connected: false),
            device(name: "Connected", connected: true)
        ]
        let sorted = StatusLogic.sorted(devices)
        expect(sorted[0].name == "Connected", "Connected devices should sort first")
        expect(sorted[1].name == "Alpha", "Disconnected devices should sort by name")
        expect(sorted[2].name == "Zulu", "Disconnected devices should sort by name")
    }

    private static func refreshGateCoalescesEvents() {
        var gate = RefreshGate()
        expect(gate.begin(), "First refresh should start")
        expect(!gate.begin(), "Refresh during read should coalesce")
        expect(gate.finish(), "Pending refresh should run after read")
        expect(gate.begin(), "Follow-up refresh should start")
        expect(!gate.finish(), "No new event should not add a refresh")
        expect(!gate.finish(), "Idle finish should not add a refresh")
    }

    private static func descriptors() {
        let connected = StatusLogic.descriptor(for: .connected)
        expect(connected.statusText == "Connected", "Connected text is incorrect")
        expect(connected.glyph == .connected, "Connected glyph is incorrect")

        let disconnected = StatusLogic.descriptor(for: .disconnected)
        expect(disconnected.statusText == "Disconnected", "Disconnected text is incorrect")
        expect(disconnected.glyph == .disconnected, "Disconnected glyph is incorrect")

        let missing = StatusLogic.descriptor(for: .missing)
        expect(missing.statusText == "No Bluetooth audio devices found", "Missing text is incorrect")
        expect(missing.glyph == .unavailable, "Missing glyph is incorrect")
    }

    private static func device(name: String, connected: Bool) -> BluetoothDeviceInfo {
        BluetoothDeviceInfo(
            name: name,
            address: "00:11:22:33:44:55",
            isConnected: connected
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
