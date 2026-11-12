import Combine
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum DefaultsKey {
        static let keyMappings = "keyMappings"
        static let keyEnabled = "keyEnabled"
        static let keyRemappings = "keyRemappings"
        static let keyAssignments = "keyAssignments"
        static let typingSoundEnabled = "typingSoundEnabled"
        static let typingSound = "typingSound"
        static let typingSoundVolume = "typingSoundVolume"
        static let idleEnabled = "idleEnabled"
        static let idleTimeoutSeconds = "idleTimeoutSeconds"
        static let idleAction = "idleAction"
        static let ignoredKeyboardIDs = "ignoredKeyboardIDs" // 旧形式の移行専用
        static let keyboardExclusionsMigrated = "keyboardExclusionsMigrated"
        static let keyboardNames = "keyboardNames"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published var keyAssignments: [KeyAssignment] {
        didSet { persist(keyAssignments, forKey: DefaultsKey.keyAssignments) }
    }

    // 実キーの選択中は変換を止め、物理キーをそのまま受け取る。保存はしない。
    @Published var isRecordingKey = false
    var recordingHandler: ((NSEvent) -> Bool)?
    @Published private var actionErrorProvider: (() -> String)?

    var actionError: String? {
        get { actionErrorProvider?() }
        set { actionErrorProvider = newValue.map { message in { message } } }
    }

    func reportActionError(for action: KeyAction, error: Error) {
        actionErrorProvider = { L10n.text("error.action", action.displayName, error.localizedDescription) }
    }

    @Published var typingSoundEnabled: Bool {
        didSet { defaults.set(typingSoundEnabled, forKey: DefaultsKey.typingSoundEnabled) }
    }

    @Published var typingSound: TypingSound {
        didSet { defaults.set(typingSound.rawValue, forKey: DefaultsKey.typingSound) }
    }

    @Published var typingSoundVolume: Double {
        didSet { defaults.set(typingSoundVolume, forKey: DefaultsKey.typingSoundVolume) }
    }

    @Published var idleEnabled: Bool {
        didSet { defaults.set(idleEnabled, forKey: DefaultsKey.idleEnabled) }
    }

    @Published var idleTimeoutSeconds: Double {
        didSet {
            let clamped = min(max(idleTimeoutSeconds, 5), 300)
            if clamped != idleTimeoutSeconds {
                idleTimeoutSeconds = clamped
                return
            }
            defaults.set(idleTimeoutSeconds, forKey: DefaultsKey.idleTimeoutSeconds)
        }
    }

    @Published var idleAction: KeyAction {
        didSet {
            guard idleAction.isValid, idleAction.systemAction == nil else {
                idleAction = .eisu
                return
            }
            persist(idleAction, forKey: DefaultsKey.idleAction)
        }
    }

    @Published var keyboardNames: [String: String] {
        didSet { persist(keyboardNames, forKey: DefaultsKey.keyboardNames) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        keyAssignments = Self.decode(
            [KeyAssignment].self,
            from: defaults.data(forKey: DefaultsKey.keyAssignments),
            decoder: decoder
        ) ?? Self.migrateAssignments(from: defaults)
        typingSoundEnabled = defaults.bool(forKey: DefaultsKey.typingSoundEnabled)
        typingSound = defaults.string(forKey: DefaultsKey.typingSound).flatMap(TypingSound.init(rawValue:)) ?? .kacha
        let savedVolume = defaults.object(forKey: DefaultsKey.typingSoundVolume) as? Double ?? 0.5
        typingSoundVolume = savedVolume.isFinite ? min(max(savedVolume, 0), 1) : 0.5
        idleEnabled = defaults.object(forKey: DefaultsKey.idleEnabled) as? Bool ?? false
        idleTimeoutSeconds = min(
            max(defaults.object(forKey: DefaultsKey.idleTimeoutSeconds) as? Double ?? 60, 5),
            300
        )
        idleAction = Self.decode(
            KeyAction.self,
            from: defaults.data(forKey: DefaultsKey.idleAction),
            decoder: decoder
        ) ?? .eisu
        keyboardNames = Self.decode(
            [String: String].self, from: defaults.data(forKey: DefaultsKey.keyboardNames), decoder: decoder
        ) ?? [:]
        if !defaults.bool(forKey: DefaultsKey.keyboardExclusionsMigrated) {
            let legacyIDs = Self.decode(
                Set<String>.self, from: defaults.data(forKey: DefaultsKey.ignoredKeyboardIDs), decoder: decoder
            ) ?? []
            for index in keyAssignments.indices where keyAssignments[index].modifierKey != nil {
                keyAssignments[index].ignoredKeyboardIDs.formUnion(legacyIDs)
            }
        }

        if !idleAction.isValid || idleAction.systemAction != nil { idleAction = .eisu }

        persist(keyAssignments, forKey: DefaultsKey.keyAssignments)
        defaults.set(true, forKey: DefaultsKey.keyboardExclusionsMigrated)
    }

    func action(for key: ModifierKey) -> KeyAction {
        let assignment = activeAssignments.first { $0.modifierKey == key && !$0.separatesPressAndRelease } ??
            keyAssignments.first { $0.modifierKey == key && !$0.separatesPressAndRelease }
        let action = assignment?.action ?? .none
        return action.isValid ? action : .none
    }

    func isEnabled(_ key: ModifierKey) -> Bool {
        keyAssignments.contains { $0.modifierKey == key && $0.isEnabled }
    }

    func assignedKeys() -> Set<ModifierKey> {
        Set(activeAssignments.filter { !$0.separatesPressAndRelease }.compactMap(\.modifierKey))
    }

    var activeKeyRemappings: [CGKeyCode: CGKeyCode] {
        var mappings: [CGKeyCode: CGKeyCode] = [:]
        for assignment in activeAssignments where !assignment.separatesPressAndRelease &&
            assignment.modifierKey == nil && assignment.sourceModifiers.isEmpty {
            guard let source = assignment.sourceKeyCode,
                  let destination = assignment.destinationKeyCode
            else { continue }
            mappings[source] = destination
        }
        return mappings
    }

    var activeSystemActions: [CGKeyCode: SystemAction] {
        var actions: [CGKeyCode: SystemAction] = [:]
        for assignment in activeAssignments where !assignment.separatesPressAndRelease &&
            assignment.modifierKey == nil && assignment.sourceModifiers.isEmpty {
            guard let source = assignment.sourceKeyCode, let action = assignment.action.systemAction else { continue }
            actions[source] = action
        }
        return actions
    }

    var activeShortcuts: [KeyboardShortcut: KeyAction] {
        var shortcuts: [KeyboardShortcut: KeyAction] = [:]
        for assignment in activeAssignments where !assignment.separatesPressAndRelease {
            if let shortcut = assignment.shortcut { shortcuts[shortcut] = assignment.action }
        }
        return shortcuts
    }

    var activeAssignments: [KeyAssignment] {
        keyAssignments.filter { $0.isEnabled && $0.isValid && !hasDuplicateSource($0) }
    }

    func hasDuplicateSource(_ assignment: KeyAssignment) -> Bool {
        guard assignment.isEnabled, assignment.isValid, let source = assignment.sourceKeyCode else { return false }
        return keyAssignments.contains {
            $0.id != assignment.id && $0.isEnabled && $0.isValid && $0.sourceKeyCode == source &&
                $0.sourceModifiers == assignment.sourceModifiers
        }
    }

    func setAction(_ action: KeyAction, for key: ModifierKey) {
        guard action.isValid else { return }
        if let index = keyAssignments.firstIndex(where: { $0.modifierKey == key }) {
            keyAssignments[index].action = action
        } else if action != .none {
            keyAssignments.append(KeyAssignment(
                sourceKeyCode: key.keyCode, action: action, isEnabled: false
            ))
        }
    }

    func setEnabled(_ enabled: Bool, for key: ModifierKey) {
        if let index = keyAssignments.firstIndex(where: { $0.modifierKey == key }) {
            keyAssignments[index].isEnabled = enabled
        } else if enabled {
            keyAssignments.append(KeyAssignment(sourceKeyCode: key.keyCode))
        }
    }

    func assignments(for keyboardID: String?) -> [KeyAssignment] {
        activeAssignments.filter { $0.applies(to: keyboardID) }
    }

    func rememberKeyboards(_ devices: [KeyboardDevice]) {
        var names = keyboardNames
        for device in devices { names[device.id] = device.name }
        if names != keyboardNames { keyboardNames = names }
    }

    private static func migrateAssignments(from defaults: UserDefaults) -> [KeyAssignment] {
        let decoder = JSONDecoder()
        let mappings = decode(
            [ModifierKey: KeyAction].self,
            from: defaults.data(forKey: DefaultsKey.keyMappings), decoder: decoder
        ) ?? defaultMappings
        let enabled = decode(
            [ModifierKey: Bool].self,
            from: defaults.data(forKey: DefaultsKey.keyEnabled), decoder: decoder
        ) ?? defaultEnabled
        let modifiers: [KeyAssignment] = ModifierKey.allCases.compactMap { key in
            let action = mappings[key] ?? .none
            let isEnabled = enabled[key] ?? false
            let destination: CGKeyCode?
            if case let .sendKey(code) = action, action.isValid { destination = code } else { destination = nil }
            guard destination != nil || isEnabled else { return nil }
            return KeyAssignment(sourceKeyCode: key.keyCode, destinationKeyCode: destination, isEnabled: isEnabled)
        }
        let remappings = decode(
            [KeyRemapping].self,
            from: defaults.data(forKey: DefaultsKey.keyRemappings), decoder: decoder
        ) ?? []
        return modifiers + remappings.map {
            KeyAssignment(
                id: $0.id, sourceKeyCode: $0.sourceKeyCode,
                destinationKeyCode: $0.destinationKeyCode, isEnabled: $0.isEnabled
            )
        }
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?,
        decoder: JSONDecoder
    ) -> Value? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static var defaultMappings: [ModifierKey: KeyAction] {
        var mappings = Dictionary(uniqueKeysWithValues: ModifierKey.allCases.map { ($0, KeyAction.none) })
        mappings[.leftCommand] = .eisu
        mappings[.rightCommand] = .kana
        return mappings
    }

    static var defaultEnabled: [ModifierKey: Bool] {
        Dictionary(uniqueKeysWithValues: ModifierKey.allCases.map { key in
            (key, key == .leftCommand || key == .rightCommand)
        })
    }
}
