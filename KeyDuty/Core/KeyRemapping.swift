import CoreGraphics
import Foundation

struct KeyRemapping: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceKeyCode: CGKeyCode?
    var destinationKeyCode: CGKeyCode?
    var isEnabled = true

    var isValid: Bool {
        guard let sourceKeyCode, let destinationKeyCode else { return false }
        return sourceKeyCode != destinationKeyCode &&
            !ModifierKey.isModifierKeyCode(sourceKeyCode) &&
            !ModifierKey.isModifierKeyCode(destinationKeyCode)
    }
}

struct KeyRemapper {
    struct Result {
        let event: CGEvent?
        var action: KeyAction?
        var isPressRelease = false
    }

    private enum Output {
        case key(CGKeyCode)
        case action(SystemAction)
        case shortcut(KeyboardShortcut, KeyAction)
        case pressRelease(PressReleaseActions)
    }

    // 押下時の変換先を解放まで保持し、途中で設定が変わっても押下・解放を対応させる。
    private var pressedKeys: [CGKeyCode: Output] = [:]

    func isPressed(_ keyCode: CGKeyCode) -> Bool { pressedKeys[keyCode] != nil }

    mutating func remap(
        _ event: CGEvent,
        mappings: [CGKeyCode: CGKeyCode],
        actions: [CGKeyCode: SystemAction] = [:],
        shortcuts: [KeyboardShortcut: KeyAction] = [:],
        pressReleaseActions: [KeyboardShortcut: PressReleaseActions] = [:],
        modifiers: ShortcutModifiers? = nil
    ) throws -> Result {
        guard event.type == .keyDown || event.type == .keyUp,
              let source = CGKeyCode(exactly: event.getIntegerValueField(.keyboardEventKeycode)),
              !ModifierKey.isModifierKeyCode(source)
        else { return Result(event: event) }

        let output: Output
        if event.type == .keyUp {
            output = pressedKeys[source] ?? .key(source)
        } else if let pressed = pressedKeys[source] {
            output = pressed
        } else if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            // 起動・復帰前から押されていたキーは、次に押し直されるまで変換しない。
            output = .key(source)
        } else {
            let shortcut = KeyboardShortcut(
                keyCode: source, modifiers: modifiers ?? ShortcutModifiers(flags: event.flags)
            )
            output = initialOutput(
                for: shortcut, mappings: mappings, actions: actions, shortcuts: shortcuts,
                pressReleaseActions: pressReleaseActions
            )
        }

        switch output {
        case let .pressRelease(actions):
            let action: KeyAction
            if event.type == .keyDown {
                action = pressedKeys[source] == nil ? actions.onPress : .none
                pressedKeys[source] = output
            } else {
                action = actions.onRelease
                pressedKeys.removeValue(forKey: source)
            }
            return Result(event: nil, action: action == .none ? nil : action,
                          isPressRelease: true)
        case let .action(action):
            return consume(event, source: source, output: output,
                           action: actions[source] == action ? .system(action) : nil)
        case let .shortcut(shortcut, action):
            return consume(event, source: source, output: output,
                           action: shortcuts[shortcut] == action ? action : nil)
        case let .key(destination):
            return try replaceKey(event, source: source, destination: destination)
        }
    }

    private mutating func replaceKey(_ event: CGEvent, source: CGKeyCode, destination: CGKeyCode) throws -> Result {
        let replacementEvent: CGEvent
        if destination == source {
            replacementEvent = event
        } else {
            // 新しいイベントにすることで、元イベントのUnicode文字列を引き継がない。
            guard let replacement = CGEvent(
                keyboardEventSource: CGEventSource(event: event),
                virtualKey: destination,
                keyDown: event.type == .keyDown
            ) else { throw KeySenderError.eventCreationFailed }
            replacement.flags = event.flags
            replacement.timestamp = event.timestamp
            for field in [CGEventField.keyboardEventAutorepeat, .keyboardEventKeyboardType, .eventSourceUserData] {
                replacement.setIntegerValueField(field, value: event.getIntegerValueField(field))
            }
            replacementEvent = replacement
        }

        if event.type == .keyDown {
            pressedKeys[source] = .key(destination)
        } else {
            pressedKeys.removeValue(forKey: source)
        }
        return Result(event: replacementEvent)
    }

    private mutating func consume(
        _ event: CGEvent, source: CGKeyCode, output: Output, action: KeyAction?
    ) -> Result {
        if event.type == .keyDown {
            pressedKeys[source] = output
        } else {
            pressedKeys.removeValue(forKey: source)
        }
        // 元キーとリピートを抑止し、押下時に決まった割り当てを解放時に1回実行する。
        // 修飾キーを先に離しても実行するが、削除・無効化・変更された割り当ては取り消す。
        return Result(event: nil, action: event.type == .keyUp ? action : nil)
    }

    private func initialOutput(
        for shortcut: KeyboardShortcut,
        mappings: [CGKeyCode: CGKeyCode], actions: [CGKeyCode: SystemAction],
        shortcuts: [KeyboardShortcut: KeyAction], pressReleaseActions: [KeyboardShortcut: PressReleaseActions]
    ) -> Output {
        let source = shortcut.keyCode
        if shortcut.isValid, let actions = pressReleaseActions[shortcut], actions.isValid {
            return .pressRelease(actions)
        }
        if shortcut.isValid, let action = shortcuts[shortcut], action != .none, action.isValid {
            return .shortcut(shortcut, action)
        }
        if let actions = pressReleaseActions[KeyboardShortcut(keyCode: source, modifiers: [])], actions.isValid {
            return .pressRelease(actions)
        }
        if let action = actions[source] { return .action(action) }
        let mapped = mappings[source] ?? source
        return .key(KeyAction.sendKey(keyCode: mapped).isValid ? mapped : source)
    }

    mutating func reset() -> Set<CGKeyCode> {
        let keysToRelease = Set(pressedKeys.compactMap { source, output -> CGKeyCode? in
            guard case let .key(destination) = output, source != destination else { return nil }
            return destination
        })
        pressedKeys.removeAll()
        return keysToRelease
    }
}
