import AppKit
import Combine

struct KeyRecordingState {
    enum Result: Equatable {
        case waiting
        case selected(CGKeyCode)
        case cancelled
        case message(String)
    }

    let allowsModifiers: Bool
    var includesSystemKeys = false
    var functionKeyState = FunctionKeyState()
    private var pendingKey: CGKeyCode?

    mutating func receive(_ event: NSEvent) -> Result {
        if let cgEvent = event.cgEvent { functionKeyState.update(cgEvent) }
        if event.type == .flagsChanged {
            if event.keyCode == 57 {
                pendingKey = nil
                return allowsModifiers ? .selected(57) : .message(L10n.text("record.capsLock"))
            }
            return receiveModifier(event)
        }
        guard let input = RecordedKeyPress(event), let cgEvent = event.cgEvent else { return .waiting }
        let code = input.keyCode
        guard SystemKey.from(keyCode: code) == nil || includesSystemKeys else {
            pendingKey = nil
            return .message(L10n.text("record.system"))
        }
        if input.isKeyDown {
            if code == 53 { return .cancelled }
            guard !input.isRepeat else { return .waiting }
            let heldModifiers = functionKeyState.modifiers(for: cgEvent)
            guard heldModifiers.isEmpty else {
                pendingKey = nil
                return .message(L10n.text("record.singleOnly"))
            }
            pendingKey = code
        } else {
            if pendingKey == code { return .selected(code) }
        }
        return .waiting
    }

    private mutating func receiveModifier(_ event: NSEvent) -> Result {
        let code = event.keyCode
        guard allowsModifiers, let modifier = ModifierKey.from(keyCode: Int64(code)) else {
            pendingKey = nil
            return .message(L10n.text("record.modifier"))
        }
        if pendingKey == code { return .selected(code) }
        let flag = NSEvent.ModifierFlags(rawValue: UInt(modifier.flagMask.rawValue))
        if pendingKey == nil && event.modifierFlags.contains(flag) {
            pendingKey = code
        } else {
            pendingKey = nil
        }
        return .waiting
    }
}

@MainActor
final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    private var monitor: Any?
    private var preferences: Preferences?
    private var state = KeyRecordingState(allowsModifiers: false)
    private var onSelect: ((CGKeyCode) -> Void)?

    func start(preferences: Preferences, allowsModifiers: Bool, includesSystemKeys: Bool = false,
               onSelect: @escaping (CGKeyCode) -> Void) {
        stop()
        self.preferences = preferences
        self.onSelect = onSelect
        state = KeyRecordingState(allowsModifiers: allowsModifiers, includesSystemKeys: includesSystemKeys)
        state.functionKeyState.isPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        preferences.isRecordingKey = true
        isRecording = true
        message = L10n.text("record.instructions")
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
        case let .selected(code):
            let onSelect = onSelect
            stop()
            onSelect?(code)
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
