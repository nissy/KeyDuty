import Carbon
import Combine
import Foundation

@MainActor
final class IMEStatusObserver: NSObject, ObservableObject {
    @Published private(set) var displayName = L10n.text("unknown")

    private var debounceTimer: Timer?

    override init() {
        super.init()
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            displayName = L10n.text("unknown")
            return
        }

        displayName = Self.stringProperty(source, key: kTISPropertyLocalizedName)
            ?? Self.stringProperty(source, key: kTISPropertyInputSourceID)
            ?? L10n.text("unknown")
    }

    @objc
    private func inputSourceDidChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(refreshAfterDebounce),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func refreshAfterDebounce() {
        debounceTimer = nil
        refresh()
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
