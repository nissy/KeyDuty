import CoreGraphics
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt64

    static let control = Self(rawValue: CGEventFlags.maskControl.rawValue)
    static let option = Self(rawValue: CGEventFlags.maskAlternate.rawValue)
    static let shift = Self(rawValue: CGEventFlags.maskShift.rawValue)
    static let command = Self(rawValue: CGEventFlags.maskCommand.rawValue)
    static let function = Self(rawValue: CGEventFlags.maskSecondaryFn.rawValue)
    static let supported: Self = [.control, .option, .shift, .command, .function]

    init(rawValue: UInt64) { self.rawValue = rawValue }

    init(flags: CGEventFlags) {
        rawValue = flags.rawValue & Self.supported.rawValue
    }

    var symbols: String {
        Self.choices.filter { contains($0.value) }.map(\.symbol).joined()
    }

    struct Choice: Sendable {
        let value: ShortcutModifiers
        let symbol: String
        let nameKey: String
        var name: String { L10n.text(nameKey) }
    }

    static let choices: [Choice] = [
        Choice(value: .control, symbol: "⌃", nameKey: "Control"),
        Choice(value: .option, symbol: "⌥", nameKey: "Option"),
        Choice(value: .shift, symbol: "⇧", nameKey: "Shift"),
        Choice(value: .command, symbol: "⌘", nameKey: "Command"),
        Choice(value: .function, symbol: "Fn", nameKey: "key.fnGlobe")
    ]
}

// 矢印やFキーにもFnフラグが付くため、物理FnのflagsChangedを別に追跡する。
struct FunctionKeyState {
    var isPressed = false

    mutating func update(_ event: CGEvent) {
        if event.type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == 63 {
            isPressed = event.flags.contains(.maskSecondaryFn)
        }
    }

    func modifiers(for event: CGEvent) -> ShortcutModifiers {
        var modifiers = ShortcutModifiers(flags: event.flags)
        modifiers.remove(.function)
        if isPressed { modifiers.insert(.function) }
        return modifiers
    }
}

struct KeyboardShortcut: Hashable, Sendable {
    let keyCode: CGKeyCode
    let modifiers: ShortcutModifiers

    var isValid: Bool {
        !modifiers.isEmpty && modifiers.isSubset(of: .supported) && !ModifierKey.isModifierKeyCode(keyCode)
    }

    var displayName: String { modifiers.symbols + " " + KeyCatalog.name(for: keyCode) }
}
