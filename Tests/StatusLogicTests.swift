import Foundation
import Darwin

@main
struct StatusLogicTests {
    static func main() {
        normalizedAddress()
        displayName()
        audioClassifier()
        connectedDevice()
        disconnectedDevices()
        missingDeviceList()
        unavailableDeviceList()
        powerOffState()
        sorting()
        sortingTieBreak()
        aggregatorClassifiesAudioDevices()
        aggregatorFailsClosed()
        aggregatorNameFallback()
        dumpEscaping()
        dumpUnavailableShape()
        refreshGateCoalescesEvents()
        coordinatorAppliesCompletedRead()
        coordinatorCoalescesRequests()
        coordinatorTimeoutRejectsLateResultAndRecovers()
        coordinatorCapsStuckWorkers()
        descriptors()
        liveUpdateNotice()
        print("StatusLogicTests: PASS")
    }

    private static func normalizedAddress() {
        let actual = StatusLogic.normalizedAddress("00:11:22:33:44:55")
        expect(actual == "001122334455", "Address separators and case should normalize")
        expect(StatusLogic.normalizedAddress("not-an-address") == "notanaddress", "Hyphens should be removed")
        expect(StatusLogic.normalizedAddress("") == "", "Empty address should stay empty")
    }

    private static func displayName() {
        let dirty = StatusLogic.displayName("evil\nname\u{1B}]0;x\u{7}\t")
        expect(dirty == "evilname]0;x", "Control characters must be dropped from UI names")
        let long = StatusLogic.displayName(String(repeating: "a", count: 100))
        expect(long.count == 64, "Long names must be bounded with an ellipsis")
        expect(long.hasSuffix("…"), "Bounded name must keep an ellipsis")
        expect(StatusLogic.displayName("") == "Unnamed device", "Empty names need a placeholder")
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

    private static func powerOffState() {
        let connected = [device(name: "Earbuds", connected: true)]
        expect(
            StatusLogic.state(devices: connected, powerState: .off) == .disabled,
            "Powered-off controller must win over the cached device list"
        )
        expect(
            StatusLogic.state(devices: connected, powerState: .on) == .connected,
            "Powered-on controller keeps the connected state"
        )
        expect(
            BluetoothStatusSnapshot(devices: connected, powerState: .off).state == .disabled,
            "Snapshot must carry the power state"
        )
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

    private static func sortingTieBreak() {
        let devices = [
            BluetoothDeviceInfo(name: "Same", address: "BB-BB", isConnected: false),
            BluetoothDeviceInfo(name: "same", address: "AA-AA", isConnected: false)
        ]
        let forward = StatusLogic.sorted(devices)
        let backward = StatusLogic.sorted(Array(devices.reversed()))
        expect(forward == backward, "Equal names must order deterministically")
        expect(forward.first?.address == "AA-AA", "Normalized address should break the tie")
    }

    private static func aggregatorClassifiesAudioDevices() {
        let devices = BluetoothDeviceAggregator.audioDevices(from: [
            FakeDevice(name: "Headset", deviceClassMajor: 0x04, connected: true),
            FakeDevice(name: "Phone", deviceClassMajor: 0x01, isHandsFreeDevice: true),
            FakeDevice(name: "Keyboard", deviceClassMajor: 0x05)
        ])
        expect(devices?.count == 2, "Only audio devices should be aggregated")
        expect(devices?.first?.name == "Headset", "Connected devices should sort first")
    }

    private static func aggregatorFailsClosed() {
        expect(BluetoothDeviceAggregator.audioDevices(from: nil) == nil, "Nil list stays unavailable")
        expect(BluetoothDeviceAggregator.audioDevices(from: [])?.isEmpty == true, "Empty list stays empty")
        expect(
            BluetoothDeviceAggregator.audioDevices(from: [NotADevice()]) == nil,
            "An unknown element must fail closed instead of being dropped"
        )
    }

    private static func aggregatorNameFallback() {
        let addressFallback = BluetoothDeviceAggregator.audioDevices(from: [
            FakeDevice(name: nil, address: "AA-BB")
        ])
        expect(addressFallback?.first?.name == "AA-BB", "Missing name should fall back to the address")
        let unknown = BluetoothDeviceAggregator.audioDevices(from: [
            FakeDevice(name: nil, address: nil)
        ])
        expect(unknown?.first?.name == "Unknown device", "Missing name and address need a placeholder")
    }

    private static func dumpEscaping() {
        let dangerous = BluetoothDeviceInfo(
            name: "evil\nstate=connected",
            address: "00:11:22:33:44:55",
            isConnected: true
        )
        let escape = BluetoothDeviceInfo(
            name: "esc\u{1B}]0;x\u{7}",
            address: "AA-BB",
            isConnected: false
        )
        let lines = StatusLogic.dumpLines(for: BluetoothStatusSnapshot(devices: [dangerous, escape]))
        expect(lines.count == 6, "Field lines plus one line per device")
        for line in lines {
            expect(!line.contains("\n") && !line.contains("\r"), "A line must not contain raw line breaks")
            expect(!line.unicodeScalars.contains { $0.value == 0x1B }, "A line must not contain raw ESC")
        }
        let joined = lines.joined(separator: "\n")
        expect(!joined.contains("evil\nstate"), "A device name must not be able to forge a line")
        expect(
            joined.contains("device=evil\\nstate=connected address=00:11:22:33:44:55 connected=true"),
            "Newline and content must be escaped, not truncated"
        )
        expect(joined.contains("\\u{1B}") && joined.contains("\\u{07}"), "ESC and BEL must be escaped")
    }

    private static func dumpUnavailableShape() {
        let lines = StatusLogic.dumpLines(for: BluetoothStatusSnapshot(devices: nil))
        expect(lines.contains("state=unavailable"), "Unavailable dump state")
        expect(lines.contains("audio_devices=unavailable"), "Unavailable device list marker")
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

    private static func coordinatorAppliesCompletedRead() {
        let reader = ManualReader()
        let scheduler = ManualTimeoutScheduler()
        let recorder = SnapshotRecorder()
        let coordinator = makeCoordinator(reader: reader, scheduler: scheduler, recorder: recorder)
        let snapshot = BluetoothStatusSnapshot(devices: [device(name: "Earbuds", connected: true)])

        coordinator.requestRefresh()
        expect(reader.startCount == 1, "First request must start a read")
        expect(!coordinator.isIdle, "A read must hold the gate")
        reader.completeLatest(with: snapshot)
        expect(recorder.snapshots == [snapshot], "Completed read must be applied")
        expect(coordinator.isIdle, "Gate must be released after completion")
    }

    private static func coordinatorCoalescesRequests() {
        let reader = ManualReader()
        let scheduler = ManualTimeoutScheduler()
        let recorder = SnapshotRecorder()
        let coordinator = makeCoordinator(reader: reader, scheduler: scheduler, recorder: recorder)
        let snapshot = BluetoothStatusSnapshot(devices: [device(name: "Earbuds", connected: true)])

        coordinator.requestRefresh()
        coordinator.requestRefresh()
        expect(reader.startCount == 1, "Second request must coalesce")
        reader.completeLatest(with: snapshot)
        expect(recorder.snapshots.count == 1, "First result applied once")
        expect(reader.startCount == 2, "Pending request must start a follow-up read")
        reader.completeLatest(with: snapshot)
        expect(recorder.snapshots.count == 2, "Follow-up result applied")
        expect(coordinator.isIdle, "Gate must be idle after coalesced work")
    }

    private static func coordinatorTimeoutRejectsLateResultAndRecovers() {
        let reader = ManualReader()
        let scheduler = ManualTimeoutScheduler()
        let recorder = SnapshotRecorder()
        let coordinator = makeCoordinator(reader: reader, scheduler: scheduler, recorder: recorder)
        let snapshot = BluetoothStatusSnapshot(devices: [device(name: "Earbuds", connected: true)])

        coordinator.requestRefresh()
        scheduler.fireLatest()
        expect(coordinator.timedOutReadCount == 1, "Deadline must be counted")
        expect(coordinator.isIdle, "Timeout must release the gate")
        expect(recorder.snapshots.count == 1, "Timeout must report the degraded state")
        expect(recorder.snapshots[0].state == .unavailable, "Degraded state must be unavailable")

        reader.completeLatest(with: snapshot)
        expect(recorder.snapshots.count == 1, "Late result must be discarded")
        expect(coordinator.stuckWorkerCount == 0, "Late worker must refund its slot")

        coordinator.requestRefresh()
        expect(reader.startCount == 2, "Recovery read must be allowed")
        reader.completeLatest(with: snapshot)
        expect(recorder.snapshots.count == 2, "Recovery result must be applied")
        expect(recorder.snapshots[1].state == .connected, "Recovery result must be the real state")
    }

    private static func coordinatorCapsStuckWorkers() {
        let reader = ManualReader()
        let scheduler = ManualTimeoutScheduler()
        let recorder = SnapshotRecorder()
        let coordinator = makeCoordinator(
            reader: reader,
            scheduler: scheduler,
            recorder: recorder,
            maxStuckWorkers: 1
        )
        let snapshot = BluetoothStatusSnapshot(devices: [device(name: "Earbuds", connected: true)])

        coordinator.requestRefresh()
        scheduler.fireLatest()
        expect(coordinator.stuckWorkerCount == 1, "Timed-out worker must be counted")

        coordinator.requestRefresh()
        expect(reader.startCount == 1, "Capped coordinator must not leak another worker")
        expect(recorder.snapshots.count == 2, "Capped coordinator keeps reporting degraded state")
        expect(coordinator.isIdle, "Capped coordinator must stay idle")

        reader.completeLatest(with: snapshot)
        expect(coordinator.stuckWorkerCount == 0, "Returning stuck worker must refund its slot")
        coordinator.requestRefresh()
        expect(reader.startCount == 2, "Worker slot must be reusable after the stuck read returns")
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

        let unavailable = StatusLogic.descriptor(for: .unavailable)
        expect(unavailable.statusText == "Unable to read Bluetooth status", "Unavailable text is incorrect")
        expect(unavailable.glyph == .unavailable, "Unavailable glyph is incorrect")

        let disabled = StatusLogic.descriptor(for: .disabled)
        expect(disabled.statusText == "Bluetooth is off", "Disabled text is incorrect")
        expect(disabled.glyph == .unavailable, "Disabled glyph is incorrect")
    }

    private static func liveUpdateNotice() {
        expect(StatusLogic.liveUpdateNotice(available: true) == nil, "Healthy registration has no notice")
        expect(
            StatusLogic.liveUpdateNotice(available: false)?.isEmpty == false,
            "Failed registration must be visible"
        )
    }

    private static func makeCoordinator(
        reader: ManualReader,
        scheduler: ManualTimeoutScheduler,
        recorder: SnapshotRecorder,
        timeout: TimeInterval = 10,
        maxStuckWorkers: Int = 2
    ) -> RefreshCoordinator {
        RefreshCoordinator(
            timeout: timeout,
            maxStuckWorkers: maxStuckWorkers,
            startRead: reader.start,
            scheduleTimeout: scheduler.schedule,
            apply: { recorder.snapshots.append($0) }
        )
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

private struct FakeDevice: BluetoothDeviceDescriptor {
    let nameOrAddress: String?
    let addressString: String?
    let deviceClassMajor: UInt32
    let isHandsFreeDevice: Bool
    let isHandsFreeAudioGateway: Bool
    private let connected: Bool

    init(
        name: String? = "Fake",
        address: String? = "00:00:00:00:00:00",
        deviceClassMajor: UInt32 = 0x04,
        isHandsFreeDevice: Bool = false,
        isHandsFreeAudioGateway: Bool = false,
        connected: Bool = false
    ) {
        self.nameOrAddress = name
        self.addressString = address
        self.deviceClassMajor = deviceClassMajor
        self.isHandsFreeDevice = isHandsFreeDevice
        self.isHandsFreeAudioGateway = isHandsFreeAudioGateway
        self.connected = connected
    }

    func isConnected() -> Bool {
        connected
    }
}

private struct NotADevice {}

private final class ManualTimeoutScheduler {
    private final class Box {
        private var action: (() -> Void)?
        private var cancelled = false

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        func fire() {
            guard !cancelled, let action else { return }
            self.action = nil
            action()
        }

        func cancel() {
            cancelled = true
            action = nil
        }
    }

    private var boxes: [Box] = []

    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let box = Box(action)
        boxes.append(box)
        return { box.cancel() }
    }

    func fireLatest() {
        boxes.last?.fire()
    }
}

private final class ManualReader {
    private(set) var startCount = 0
    private var completions: [(BluetoothStatusSnapshot) -> Void] = []

    func start(_ completion: @escaping (BluetoothStatusSnapshot) -> Void) {
        startCount += 1
        completions.append(completion)
    }

    func completeLatest(with snapshot: BluetoothStatusSnapshot) {
        completions.last?(snapshot)
    }
}

private final class SnapshotRecorder {
    var snapshots: [BluetoothStatusSnapshot] = []
}
