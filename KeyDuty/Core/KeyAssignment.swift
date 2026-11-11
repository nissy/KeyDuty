import CoreGraphics
import Foundation

struct PressReleaseActions: Codable, Equatable, Sendable {
    var onPress: KeyAction = .none
    var onRelease: KeyAction = .none

    var isEmpty: Bool { onPress == .none && onRelease == .none }
    var isValid: Bool { !isEmpty && onPress.isValid && onRelease.isValid }
}

struct KeyAssignment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceKeyCode: CGKeyCode?
    var sourceModifiers: ShortcutModifiers = []
    var action: KeyAction = .none
    var isEnabled = true
    var ignoredKeyboardIDs: Set<String> = []
    var separatesPressAndRelease = false
    var pressReleaseActions = PressReleaseActions()
    // 未設定と、利用者が明示的に両方を「何もしない」にした設定を区別する。
    private var hasConfiguredPressReleaseActions = false

    var destinationKeyCode: CGKeyCode? {
        get {
            if case let .sendKey(code) = action { return code }
            return nil
        }
        set { action = newValue.map { .sendKey(keyCode: $0) } ?? .none }
    }

    init(id: UUID = UUID(), sourceKeyCode: CGKeyCode? = nil,
         destinationKeyCode: CGKeyCode? = nil, isEnabled: Bool = true, sourceModifiers: ShortcutModifiers = []) {
        self.id = id
        self.sourceKeyCode = sourceKeyCode
        self.sourceModifiers = sourceModifiers
        self.action = destinationKeyCode.map { .sendKey(keyCode: $0) } ?? .none
        self.isEnabled = isEnabled
    }

    init(id: UUID = UUID(), sourceKeyCode: CGKeyCode? = nil, action: KeyAction,
         isEnabled: Bool = true, sourceModifiers: ShortcutModifiers = []) {
        self.id = id
        self.sourceKeyCode = sourceKeyCode
        self.sourceModifiers = sourceModifiers
        self.action = action
        self.isEnabled = isEnabled
    }

    var modifierKey: ModifierKey? {
        guard sourceModifiers.isEmpty else { return nil }
        return sourceKeyCode.flatMap { ModifierKey.from(keyCode: Int64($0)) }
    }

    var shortcut: KeyboardShortcut? {
        guard let sourceKeyCode, !sourceModifiers.isEmpty else { return nil }
        return KeyboardShortcut(keyCode: sourceKeyCode, modifiers: sourceModifiers)
    }

    var inputName: String {
        shortcut?.displayName ?? sourceKeyCode.map(KeyCatalog.name(for:)) ?? L10n.text("common.unset")
    }

    var behaviorName: String {
        guard sourceKeyCode != nil else { return L10n.text("common.unset") }
        if separatesPressAndRelease { return L10n.text("behavior.split") }
        if sourceKeyCode == 57 { return L10n.text("behavior.toggle") }
        if !sourceModifiers.isEmpty { return L10n.text("behavior.shortcut") }
        if modifierKey != nil { return L10n.text("behavior.tap") }
        return action.systemAction == nil ? L10n.text("behavior.remap") : L10n.text("behavior.release")
    }

    var isValid: Bool {
        guard let sourceKeyCode else { return false }
        if separatesPressAndRelease {
            guard supportsPressRelease, pressReleaseActions.isValid else { return false }
            return shortcut?.isValid ?? true
        }
        guard action != .none, action.isValid else { return false }
        if let shortcut { return shortcut.isValid }
        return sourceKeyCode != destinationKeyCode &&
            (sourceKeyCode == 57 || modifierKey != nil || !ModifierKey.isModifierKeyCode(sourceKeyCode))
    }

    // Caps LockのflagsChangedは物理的な解放ではなく、オン／オフの切替を通知する。
    var supportsPressRelease: Bool { sourceKeyCode != 57 }

    mutating func setSeparatesPressAndRelease(_ enabled: Bool) {
        guard !enabled || supportsPressRelease else { return }
        if enabled, !hasConfiguredPressReleaseActions {
            if pressReleaseActions.isEmpty {
                if modifierKey == nil, sourceModifiers.isEmpty, action.systemAction == nil {
                    pressReleaseActions.onPress = action
                } else {
                    pressReleaseActions.onRelease = action
                }
            }
            hasConfiguredPressReleaseActions = true
        }
        // 通常の割り当てと分けた割り当てを両方保持し、切替だけで設定を失わない。
        separatesPressAndRelease = enabled
    }

    func applies(to keyboardID: String?) -> Bool {
        guard !ignoredKeyboardIDs.isEmpty else { return true }
        // 識別できない入力で、除外指定のある割り当てを誤って発動させない。
        guard let keyboardID else { return false }
        return !ignoredKeyboardIDs.contains(keyboardID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceKeyCode, sourceModifiers, destinationKeyCode, action, isEnabled, ignoredKeyboardIDs
        case separatesPressAndRelease, pressReleaseActions
        case hasConfiguredPressReleaseActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceKeyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .sourceKeyCode)
        sourceModifiers = try container.decodeIfPresent(ShortcutModifiers.self, forKey: .sourceModifiers) ?? []
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        ignoredKeyboardIDs = try container.decodeIfPresent(Set<String>.self, forKey: .ignoredKeyboardIDs) ?? []
        separatesPressAndRelease = try container.decodeIfPresent(Bool.self, forKey: .separatesPressAndRelease) ?? false
        pressReleaseActions = try container.decodeIfPresent(PressReleaseActions.self, forKey: .pressReleaseActions) ??
            PressReleaseActions()
        hasConfiguredPressReleaseActions = try container.decodeIfPresent(
            Bool.self, forKey: .hasConfiguredPressReleaseActions
        ) ?? (container.contains(.pressReleaseActions) || separatesPressAndRelease)
        if let savedAction = try container.decodeIfPresent(KeyAction.self, forKey: .action) {
            action = savedAction
        } else {
            let legacyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .destinationKeyCode)
            action = legacyCode.map { .sendKey(keyCode: $0) } ?? .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(sourceKeyCode, forKey: .sourceKeyCode)
        try container.encode(sourceModifiers, forKey: .sourceModifiers)
        try container.encode(action, forKey: .action)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(ignoredKeyboardIDs, forKey: .ignoredKeyboardIDs)
        try container.encode(separatesPressAndRelease, forKey: .separatesPressAndRelease)
        try container.encode(pressReleaseActions, forKey: .pressReleaseActions)
        try container.encode(hasConfiguredPressReleaseActions, forKey: .hasConfiguredPressReleaseActions)
    }
}
