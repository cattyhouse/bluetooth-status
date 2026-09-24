import AppKit
import Foundation
import IOBluetooth

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let readTimeout: TimeInterval = 10
    private static let maxStuckReaders = 2

    private var statusItem: NSStatusItem?
    private var notificationTokens: [NSObjectProtocol] = []
    private var connectRegistration: IOBluetoothUserNotification?
    private var appearanceObservation: NSKeyValueObservation?
    private var maintenanceTimer: Timer?
    private var refreshCoordinator: RefreshCoordinator?
    private var liveUpdatesAvailable = true
    private var lastRendered: RenderedState?

    private struct RenderedState: Equatable {
        let snapshot: BluetoothStatusSnapshot
        let descriptor: StatusDescriptor
        let darkMenuBar: Bool
        let liveUpdatesAvailable: Bool
    }

    private let connectedNotification = Notification.Name(rawValue: "IOBluetoothDeviceConnected")
    private let disconnectedNotification = Notification.Name(rawValue: "IOBluetoothDeviceDisconnected")
    private let deviceChangeNotifications = [
        Notification.Name(rawValue: "IOBluetoothDeviceNameChanged"),
        Notification.Name(rawValue: "IOBluetoothDeviceInquiryInfoChanged"),
        Notification.Name(rawValue: "IOBluetoothDeviceServicesChanged")
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installStatusItem()
        installBluetoothNotifications()
        installLifecycleObservers()
        installAppearanceObservation()
        installRefreshCoordinator()
        startMaintenanceTimer()
        requestRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
        connectRegistration?.unregister()
        connectRegistration = nil
        appearanceObservation = nil
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        refreshCoordinator = nil
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.menu = NSMenu()
        statusItem = item
    }

    private func installBluetoothNotifications() {
        let center = NotificationCenter.default
        for name in [connectedNotification, disconnectedNotification] + deviceChangeNotifications {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.requestRefresh()
            }
            notificationTokens.append(token)
        }

        attemptConnectRegistration()
    }

    /// Registers the connect callback and retries it from the maintenance
    /// timer. A nil result silently degrades to periodic refresh otherwise, so
    /// it is surfaced in the menu and tooltip.
    private func attemptConnectRegistration() {
        guard connectRegistration == nil else { return }
        let registration = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleConnectNotification(_:device:))
        )
        connectRegistration = registration
        liveUpdatesAvailable = registration != nil
    }

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.requestRefresh()
            }
            notificationTokens.append(token)
        }

        let appCenter = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification] {
            let token = appCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.requestRefresh()
            }
            notificationTokens.append(token)
        }
    }

    private func installAppearanceObservation() {
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.requestRefresh()
            }
        }
    }

    private func installRefreshCoordinator() {
        refreshCoordinator = RefreshCoordinator(
            timeout: Self.readTimeout,
            maxStuckWorkers: Self.maxStuckReaders,
            startRead: { completion in
                // A fresh queue per read lets the coordinator abandon a wedged
                // reader instead of queueing every later read behind it. The
                // coordinator caps how many abandoned readers may exist.
                let queue = DispatchQueue(
                    label: "com.justin.bluetoothstatus.reader",
                    qos: .utility
                )
                queue.async {
                    let snapshot = BluetoothStatusReader.readSnapshot()
                    DispatchQueue.main.async { completion(snapshot) }
                }
            },
            scheduleTimeout: { delay, action in
                let item = DispatchWorkItem(block: action)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                return { item.cancel() }
            },
            apply: { [weak self] snapshot in
                self?.apply(snapshot)
            }
        )
    }

    private func startMaintenanceTimer() {
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.attemptConnectRegistration()
            self?.requestRefresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    @objc private func handleConnectNotification(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.requestRefresh()
        }
    }

    private func requestRefresh() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.requestRefresh()
            }
            return
        }
        refreshCoordinator?.requestRefresh()
    }

    private func apply(_ snapshot: BluetoothStatusSnapshot) {
        guard let button = statusItem?.button else { return }

        let descriptor = StatusLogic.descriptor(for: snapshot.state)
        let darkMenuBar = isDarkMenuBar()
        let rendered = RenderedState(
            snapshot: snapshot,
            descriptor: descriptor,
            darkMenuBar: darkMenuBar,
            liveUpdatesAvailable: liveUpdatesAvailable
        )
        guard rendered != lastRendered else { return }
        lastRendered = rendered

        let foreground: NSColor = darkMenuBar ? .white : .black
        button.image = makeStatusImage(glyph: descriptor.glyph, color: foreground)
        button.contentTintColor = nil
        button.setAccessibilityLabel("Bluetooth audio status")
        button.setAccessibilityValue(descriptor.statusText)
        button.toolTip = tooltip(for: snapshot, descriptor: descriptor)
        rebuildMenu(snapshot: snapshot, descriptor: descriptor)
    }

    private func tooltip(
        for snapshot: BluetoothStatusSnapshot,
        descriptor: StatusDescriptor
    ) -> String {
        let connected = snapshot.connectedDevices
        let base: String
        if connected.count == 1, let device = connected.first {
            base = "\(StatusLogic.displayName(device.name)): connected"
        } else if connected.count > 1 {
            base = "\(connected.count) Bluetooth audio devices connected"
        } else {
            base = "Bluetooth audio: \(descriptor.statusText)"
        }
        guard let notice = StatusLogic.liveUpdateNotice(available: liveUpdatesAvailable) else {
            return base
        }
        return base + "\n" + notice
    }

    private func rebuildMenu(snapshot: BluetoothStatusSnapshot, descriptor: StatusDescriptor) {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let stateItem = NSMenuItem(
            title: "Status: \(descriptor.statusText)",
            action: nil,
            keyEquivalent: ""
        )
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        if let notice = StatusLogic.liveUpdateNotice(available: liveUpdatesAvailable) {
            let noticeItem = NSMenuItem(title: notice, action: nil, keyEquivalent: "")
            noticeItem.isEnabled = false
            menu.addItem(noticeItem)
        }

        if let devices = snapshot.devices, !devices.isEmpty {
            menu.addItem(.separator())
            for device in devices {
                let status = device.isConnected ? "connected" : "disconnected"
                let item = NSMenuItem(
                    title: "\(StatusLogic.displayName(device.name))：\(status)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.toolTip = device.address
                menu.addItem(item)
            }
        } else {
            let item = NSMenuItem(
                title: snapshot.devices == nil ? "Device list unavailable" : "No paired Bluetooth audio devices",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeStatusImage(glyph: StatusGlyph, color: NSColor) -> NSImage? {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            let text: String
            switch glyph {
            case .connected:
                text = "B"
            case .disconnected:
                text = "B"
            case .unavailable:
                text = "?"
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: color
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedText.size()
            attributedText.draw(at: NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2 - 1
            ))

            if glyph == .disconnected {
                let slash = NSBezierPath()
                slash.lineWidth = 2
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 3, y: 3))
                slash.line(to: NSPoint(x: 17, y: 17))
                color.setStroke()
                slash.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func isDarkMenuBar() -> Bool {
        // NSStatusBarButton.effectiveAppearance can be VibrantLight even
        // when the menu bar itself is dark. Use the application appearance
        // and the global interface style as stable sources.
        let appearance = NSApplication.shared.effectiveAppearance
        let darkSystemAppearance = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // `UserDefaults(suiteName: "NSGlobalDomain")` is not a valid suite on
        // current macOS; the standard search list already includes the global
        // domain, which is where AppleInterfaceStyle lives.
        let darkInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
        return darkSystemAppearance || darkInterfaceStyle
    }

    @objc private func refreshNow() {
        requestRefresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
