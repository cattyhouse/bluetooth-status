import AppKit
import Foundation
import IOBluetooth

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let readerQueue = DispatchQueue(label: "com.justin.bluetoothstatus.reader", qos: .utility)
    private var statusItem: NSStatusItem?
    private var notificationTokens: [NSObjectProtocol] = []
    private var connectRegistration: IOBluetoothUserNotification?
    private var appearanceObservation: NSKeyValueObservation?
    private var maintenanceTimer: Timer?
    private var refreshGate = RefreshGate()

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

        connectRegistration = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleConnectNotification(_:device:))
        )
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

    private func startMaintenanceTimer() {
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
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
        guard refreshGate.begin() else { return }

        readerQueue.async { [weak self] in
            let snapshot = BluetoothStatusReader.readSnapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                let shouldRefreshAgain = self.refreshGate.finish()
                self.apply(snapshot)
                if shouldRefreshAgain {
                    self.requestRefresh()
                }
            }
        }
    }

    private func apply(_ snapshot: BluetoothStatusSnapshot) {
        guard let button = statusItem?.button else { return }

        let descriptor = StatusLogic.descriptor(for: snapshot.state)
        let foreground = menuBarForegroundColor()
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
        if connected.count == 1, let device = connected.first {
            return "\(device.name): connected"
        }
        if connected.count > 1 {
            return "\(connected.count) Bluetooth audio devices connected"
        }
        return "Bluetooth audio: \(descriptor.statusText)"
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

        if let devices = snapshot.devices, !devices.isEmpty {
            menu.addItem(.separator())
            for device in devices {
                let status = device.isConnected ? "connected" : "disconnected"
                let item = NSMenuItem(
                    title: "\(device.name)：\(status)",
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

    private func menuBarForegroundColor() -> NSColor {
        // NSStatusBarButton.effectiveAppearance can be VibrantLight even
        // when the menu bar itself is dark. Use the application appearance
        // and the global interface style as stable sources.
        let appearance = NSApplication.shared.effectiveAppearance
        let globalDefaults = UserDefaults(suiteName: "NSGlobalDomain")
        let darkSystemAppearance = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let darkInterfaceStyle = globalDefaults?.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
        return (darkSystemAppearance || darkInterfaceStyle) ? .white : .black
    }

    @objc private func refreshNow() {
        requestRefresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
