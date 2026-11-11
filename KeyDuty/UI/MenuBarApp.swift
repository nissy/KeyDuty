import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "KeyDuty"

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil ||
            NSClassFromString("XCTest.XCTestCase") != nil
    }

    private static func statusIconImage() -> NSImage? {
        NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: appName)
    }

    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private let permissionManager = PermissionManager.shared
    private let imeStatusObserver = IMEStatusObserver()
    private let keyboardDeviceManager = KeyboardDeviceManager.shared
    private var keyMonitor: KeyMonitor?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        observeIMEStatus()
        observeLanguage()
        startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem = nil
        keyMonitor?.stop()
        keyMonitor = nil
        keyboardDeviceManager.stop()
        preferencesWindow?.close()
        preferencesWindow = nil
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusIconImage()

        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("menu.settings"), action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("menu.quit"), action: #selector(terminate), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func observeLanguage() {
        LanguageSettings.shared.changes.sink { [weak self] _ in
            guard let self else { return }
            statusItem?.menu?.items.first?.title = L10n.text("menu.settings")
            statusItem?.menu?.items.last?.title = L10n.text("menu.quit")
            preferencesWindow?.title = L10n.text("settings.window", Self.appName)
            imeStatusObserver.refresh()
        }.store(in: &cancellables)
    }

    private func observeIMEStatus() {
        imeStatusObserver.$displayName
            .removeDuplicates()
            .sink { [weak self] displayName in
                self?.statusItem?.button?.toolTip = "\(Self.appName) — \(displayName)"
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        permissionManager.refresh()
        guard permissionManager.isReady else {
            showPreferences()
            return
        }
        keyboardDeviceManager.start()

        if let keyMonitor {
            keyMonitor.resetState()
            keyMonitor.start()
            if keyMonitor.isRunning {
                handleMonitorRecovery()
            }
            return
        }

        do {
            let sender = try KeySender()
            let monitor = KeyMonitor(
                preferences: .shared,
                sender: sender,
                keyboardDeviceManager: keyboardDeviceManager,
                onError: { [weak self] error in
                    self?.handleMonitorError(error)
                },
                onStatusChange: { [weak self] isRunning in
                    self?.handleMonitorStatusChange(isRunning)
                }
            )
            keyMonitor = monitor
            monitor.start()
        } catch {
            handleMonitorError(error)
        }
    }

    private func handleMonitorError(_ error: Error) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: error.localizedDescription
        )

        permissionManager.refresh()
    }

    private func handleMonitorStatusChange(_ isRunning: Bool) {
        if isRunning {
            handleMonitorRecovery()
        }
    }

    private func handleMonitorRecovery() {
        statusItem?.button?.image = Self.statusIconImage()
    }

    @objc
    private func showPreferences() {
        if let preferencesWindow {
            presentPreferencesWindow(preferencesWindow)
            return
        }

        let controller = NSHostingController(
            rootView: PreferencesView(
                preferences: .shared,
                permissionManager: .shared,
                launchAtLoginManager: .shared,
                keyboardDeviceManager: .shared
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.title = L10n.text("settings.window", Self.appName)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 820, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        preferencesWindow = window
        presentPreferencesWindow(window)
    }

    private func presentPreferencesWindow(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    @objc
    func checkPermissions() {
        startMonitoring()
    }

    @objc
    private func terminate() {
        NSApp.terminate(nil)
    }
}
