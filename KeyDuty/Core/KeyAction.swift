import CoreGraphics

enum ModifierKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case leftCommand
    case rightCommand
    case leftShift
    case rightShift
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case function

    var id: String { rawValue }

    var keyCode: CGKeyCode {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftControl: 59
        case .rightControl: 62
        case .leftOption: 58
        case .rightOption: 61
        case .function: 63
        }
    }

    var localizationKey: String {
        self == .function ? "key.fnGlobe" : "key.\(rawValue)"
    }

    var displayName: String { L10n.text(localizationKey) }

    var flagMask: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand:
            .maskCommand
        case .leftShift, .rightShift:
            .maskShift
        case .leftControl, .rightControl:
            .maskControl
        case .leftOption, .rightOption:
            .maskAlternate
        case .function:
            .maskSecondaryFn
        }
    }

    static func from(keyCode: Int64) -> ModifierKey? {
        allCases.first { Int64($0.keyCode) == keyCode }
    }

    static func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
        allCases.contains { $0.keyCode == keyCode } || keyCode == 57 || keyCode == 63
    }
}

enum KeyAction: Codable, Equatable, Hashable, Sendable {
    case none
    case sendKey(keyCode: CGKeyCode)
    case system(SystemAction)

    static let eisu = KeyAction.sendKey(keyCode: 102)
    static let kana = KeyAction.sendKey(keyCode: 104)
    static let f13 = KeyAction.sendKey(keyCode: 105)
    static let f14 = KeyAction.sendKey(keyCode: 107)
    static let f15 = KeyAction.sendKey(keyCode: 113)
    static let f16 = KeyAction.sendKey(keyCode: 106)
    static let f17 = KeyAction.sendKey(keyCode: 64)
    static let f18 = KeyAction.sendKey(keyCode: 79)
    static let f19 = KeyAction.sendKey(keyCode: 80)
    static let f20 = KeyAction.sendKey(keyCode: 90)

    private static let presetNames: [KeyAction: String] = [
        .eisu: "key.eisu",
        .kana: "key.kana",
        .f13: "F13",
        .f14: "F14",
        .f15: "F15",
        .f16: "F16",
        .f17: "F17",
        .f18: "F18",
        .f19: "F19",
        .f20: "F20"
    ]

    var displayName: String {
        if let presetName = Self.presetNames[self] {
            return L10n.text(presetName)
        }
        switch self {
        case .none:
            return L10n.text("common.none")
        case let .sendKey(keyCode):
            return L10n.text("key.code", String(keyCode))
        case let .system(action):
            return action.displayName
        }
    }

    var isValid: Bool {
        switch self {
        case .none, .system:
            true
        case let .sendKey(keyCode):
            !ModifierKey.isModifierKeyCode(keyCode) && SystemKey.from(keyCode: keyCode) == nil
        }
    }

    var systemAction: SystemAction? {
        if case let .system(action) = self { return action }
        return nil
    }

    static let functionKeyPresets: [KeyAction] = [.f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20]
    static let selectablePresets: [KeyAction] = [.none, .eisu, .kana] + functionKeyPresets
}
