import Foundation

/// Samples the Bluetooth controller power state on a fixed interval.
///
/// macOS does not post a notification when the user flips the Bluetooth
/// switch in Control Center, so the app samples the cheap `powerState`
/// property instead of waiting for the next periodic refresh. The sample is
/// delivered on the main thread; the read itself runs on a private queue so a
/// slow Bluetooth stack can never block the user interface.
final class PowerStateWatcher {
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let readState: () -> BluetoothPowerState
    private let onSample: (BluetoothPowerState) -> Void
    private var timer: DispatchSourceTimer?

    init(
        interval: TimeInterval,
        queue: DispatchQueue = DispatchQueue(
            label: "com.justin.bluetoothstatus.powerwatch",
            qos: .utility
        ),
        readState: @escaping () -> BluetoothPowerState,
        onSample: @escaping (BluetoothPowerState) -> Void
    ) {
        self.interval = interval
        self.queue = queue
        self.readState = readState
        self.onSample = onSample
    }

    /// Starts sampling. The first sample is taken immediately so the caller
    /// learns the current power state without waiting a full interval.
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let state = self.readState()
            DispatchQueue.main.async { [weak self] in
                self?.onSample(state)
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
