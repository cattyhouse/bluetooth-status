import Foundation

/// Coalesces refresh requests and bounds a blocking snapshot read with a
/// deadline.
///
/// Thread confinement: every method must run on the main thread. `startRead`
/// may perform its work anywhere, but it must deliver its completion on the
/// main thread. A completion from a read that already timed out is discarded
/// by generation, and its worker slot is refunded so a later refresh can retry.
///
/// A timed-out worker cannot be cancelled (it may be blocked inside a system
/// call), so at most `maxStuckWorkers` of them are ever abandoned. Beyond that
/// cap the coordinator keeps reporting the degraded state without leaking
/// another thread.
final class RefreshCoordinator {
    private let startRead: (@escaping (BluetoothStatusSnapshot) -> Void) -> Void
    private let scheduleTimeout: (TimeInterval, @escaping () -> Void) -> () -> Void
    private let timeout: TimeInterval
    private let maxStuckWorkers: Int
    private let apply: (BluetoothStatusSnapshot) -> Void

    private var gate = RefreshGate()
    private var generation: UInt64 = 0
    private var stuckWorkers = 0
    private var cancelTimeout: (() -> Void)?

    /// Number of reads whose deadline expired while the worker was blocked.
    private(set) var timedOutReadCount = 0

    var isIdle: Bool { gate.isIdle }

    /// Workers still blocked after their deadline.
    var stuckWorkerCount: Int { stuckWorkers }

    init(
        timeout: TimeInterval,
        maxStuckWorkers: Int,
        startRead: @escaping (@escaping (BluetoothStatusSnapshot) -> Void) -> Void,
        scheduleTimeout: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void,
        apply: @escaping (BluetoothStatusSnapshot) -> Void
    ) {
        self.timeout = timeout
        self.maxStuckWorkers = max(0, maxStuckWorkers)
        self.startRead = startRead
        self.scheduleTimeout = scheduleTimeout
        self.apply = apply
    }

    func requestRefresh() {
        precondition(Thread.isMainThread, "RefreshCoordinator is main-thread confined")
        guard gate.begin() else { return }

        guard stuckWorkers < maxStuckWorkers else {
            // Every worker slot is blocked; do not leak another one.
            apply(BluetoothStatusSnapshot(devices: nil))
            finishCurrentRead()
            return
        }

        generation &+= 1
        let token = generation
        cancelTimeout = scheduleTimeout(timeout) { [weak self] in
            self?.timeoutFired(token)
        }
        startRead { [weak self] snapshot in
            self?.readCompleted(token, snapshot)
        }
    }

    private func readCompleted(_ token: UInt64, _ snapshot: BluetoothStatusSnapshot) {
        precondition(Thread.isMainThread, "RefreshCoordinator is main-thread confined")
        guard token == generation else {
            // Result arrived after its deadline: the app already showed a
            // degraded state, so preserve it and refund the worker slot.
            stuckWorkers = max(0, stuckWorkers - 1)
            return
        }
        cancelTimeout?()
        cancelTimeout = nil
        apply(snapshot)
        finishCurrentRead()
    }

    private func timeoutFired(_ token: UInt64) {
        precondition(Thread.isMainThread, "RefreshCoordinator is main-thread confined")
        guard token == generation else { return }
        generation &+= 1
        stuckWorkers += 1
        timedOutReadCount += 1
        cancelTimeout = nil
        apply(BluetoothStatusSnapshot(devices: nil))
        finishCurrentRead()
    }

    private func finishCurrentRead() {
        if gate.finish() {
            requestRefresh()
        }
    }
}
