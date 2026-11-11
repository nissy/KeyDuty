import AppKit
import Combine

struct ShortcutRecordingState {
    enum Result: Equatable {
        case waiting
        case selected(KeyboardShortcut)
        case cancelled
        case message(String)
    }

    private var pendingShortcut: KeyboardShortcut?
    var functionKeyState = FunctionKeyState()

    mutating func receive(_ event: NSEvent) -> Result {
        guard let cgEvent = event.cgEvent else { return .waiting }
        functionKeyState.update(cgEvent)
        guard let input = RecordedKeyPress(event) else { return .waiting }
        if input.isKeyDown {
            let modifiers = functionKeyState.modifiers(for: cgEvent)
            if input.keyCode == 53 && modifiers.isEmpty { return .cancelled }
            guard !input.isRepeat else { return .waiting }
            let shortcut = KeyboardShortcut(keyCode: input.keyCode, modifiers: modifiers)
            guard shortcut.isValid, pendingShortcut == nil else {
                pendingShortcut = nil
                return .message(L10n.text("record.shortcutOnly"))
            }
            pendingShortcut = shortcut
        } else {
            if let shortcut = pendingShortcut, shortcut.keyCode == input.keyCode {
                pendingShortcut = nil
                return .selected(shortcut)
            }
        }
        return .waiting
    }
}

@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    private var monitor: Any?
    private var preferences: Preferences?
    private var state = ShortcutRecordingState()
    private var onSelect: ((KeyboardShortcut) -> Void)?

    func start(preferences: Preferences, onSelect: @escaping (KeyboardShortcut) -> Void) {
        stop()
        self.preferences = preferences
        self.onSelect = onSelect
        state = ShortcutRecordingState()
        state.functionKeyState.isPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        preferences.isRecordingKey = true
        isRecording = true
        message = L10n.text("record.shortcutInstructions")
        preferences.recordingHandler = { [weak self] in self?.receive($0) ?? false }
        let types: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .systemDefined]
        monitor = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.receive(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func receive(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .systemDefined && SystemKeyInput(event) == nil { return false }
        switch state.receive(event) {
        case let .selected(shortcut):
            let onSelect = onSelect
            stop()
            onSelect?(shortcut)
        case .cancelled:
            stop()
        case let .message(message):
            self.message = message
        case .waiting:
            break
        }
        return true
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        preferences?.recordingHandler = nil
        preferences?.isRecordingKey = false
        preferences = nil
        onSelect = nil
        isRecording = false
        message = nil
    }
}
