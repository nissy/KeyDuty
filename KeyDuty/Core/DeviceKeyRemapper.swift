import CoreGraphics

struct DeviceKeyRemapper {
    private struct Press: Hashable {
        let senderID: UInt64
        let keyCode: CGKeyCode
    }

    private var remappers: [UInt64: KeyRemapper] = [:]
    private var heldOutputs: [Press: CGKeyCode] = [:]

    /// 押下を送ってまだ解放を送っていない出力キー。
    var heldOutputKeyCodes: Set<CGKeyCode> { Set(heldOutputs.values) }

    func hasKnownPress(_ keyCode: CGKeyCode) -> Bool {
        remappers.contains { $0.key != 0 && $0.value.isPressed(keyCode) }
    }

    mutating func remap(
        _ event: CGEvent, assignments: [KeyAssignment], origin: KeyboardEventOrigin, modifiers: ShortcutModifiers
    ) throws -> KeyRemapper.Result {
        var mappings: [CGKeyCode: CGKeyCode] = [:]
        var actions: [CGKeyCode: SystemAction] = [:]
        var shortcuts: [KeyboardShortcut: KeyAction] = [:]
        var pressReleaseActions: [KeyboardShortcut: PressReleaseActions] = [:]
        for assignment in assignments {
            if assignment.separatesPressAndRelease, assignment.modifierKey == nil,
               assignment.supportsPressRelease, let source = assignment.sourceKeyCode {
                let input = KeyboardShortcut(keyCode: source, modifiers: assignment.sourceModifiers)
                pressReleaseActions[input] = assignment.pressReleaseActions
            } else if !assignment.separatesPressAndRelease, let shortcut = assignment.shortcut {
                shortcuts[shortcut] = assignment.action
            } else if !assignment.separatesPressAndRelease,
                      assignment.modifierKey == nil, let source = assignment.sourceKeyCode {
                mappings[source] = assignment.destinationKeyCode
                actions[source] = assignment.action.systemAction
            }
        }
        // 同じキーを別のキーボードでも押した場合に、押下・解放を混同しない。
        let result = try remappers[origin.senderID, default: KeyRemapper()].remap(
            event, mappings: mappings, actions: actions, shortcuts: shortcuts,
            pressReleaseActions: pressReleaseActions, modifiers: modifiers
        )
        return trackOutput(result, input: event, senderID: origin.senderID)
    }

    private mutating func trackOutput(
        _ result: KeyRemapper.Result, input: CGEvent, senderID: UInt64
    ) -> KeyRemapper.Result {
        guard let output = result.event, input.type == .keyDown || input.type == .keyUp,
              let source = CGKeyCode(exactly: input.getIntegerValueField(.keyboardEventKeycode)),
              let destination = CGKeyCode(exactly: output.getIntegerValueField(.keyboardEventKeycode))
        else { return result }
        let press = Press(senderID: senderID, keyCode: source)
        if input.type == .keyDown {
            heldOutputs[press] = destination
        } else {
            heldOutputs.removeValue(forKey: press)
            // 別の入力が同じ出力キーを保持している間は、解放を送らない。
            if heldOutputs.values.contains(destination) {
                return KeyRemapper.Result(event: nil, action: result.action)
            }
        }
        return result
    }

    mutating func reset(preservingOriginalKeys: Bool = true) -> Set<CGKeyCode> {
        var released: Set<CGKeyCode> = []
        for sender in remappers.keys { released.formUnion(remappers[sender]?.reset() ?? []) }
        let originalHeld = Set(heldOutputs.compactMap { $0.key.keyCode == $0.value ? $0.value : nil })
        remappers.removeAll()
        heldOutputs.removeAll()
        return preservingOriginalKeys ? released.subtracting(originalHeld) : released
    }
}

struct DeviceModifierState {
    struct Result {
        var actions: [KeyAction] = []
        var suppressEvent = false
        var isPressRelease = false
    }

    private var states: [UInt64: ModifierStateMachine] = [:]
    private var suppressedFunctionSenders: Set<UInt64> = []
    private var pressReleaseActions: [UInt64: [ModifierKey: PressReleaseActions]] = [:]
    private var pressedAutomaticAssignments: [UInt64: [ModifierKey: KeyAssignment]] = [:]

    func hasKnownPress(_ key: ModifierKey) -> Bool {
        states.contains { $0.key != 0 && $0.value.isPhysicallyPressed(key) }
    }

    mutating func handle(
        _ key: ModifierKey, flags: CGEventFlags, origin: KeyboardEventOrigin, assignments: [KeyAssignment]
    ) -> Result {
        var state = states[origin.senderID, default: ModifierStateMachine()]
        let automaticAssignments = assignments.filter { !$0.separatesPressAndRelease }
        // 分割したキーも「割り当て済み」として扱い、後から押す従来側のあと勝ち条件を保つ。
        // 分割側の実行は下の押下・解放スナップショットだけで行う。
        let assignedKeys = Set(assignments.compactMap(\.modifierKey))
        let isRelease = state.isPhysicallyPressed(key)
        var pairedAction: KeyAction = .none
        var isPressRelease = false
        let fired: [ModifierKey]
        if isRelease {
            let pair = pressReleaseActions[origin.senderID]?.removeValue(forKey: key)
            pairedAction = pair?.onRelease ?? .none
            isPressRelease = pair != nil
            fired = state.modifierUp(key)
        } else if flags.contains(key.flagMask) {
            pressedAutomaticAssignments[origin.senderID, default: [:]][key] =
                automaticAssignments.first { $0.modifierKey == key }
            if let assignment = assignments.first(where: { $0.modifierKey == key && $0.separatesPressAndRelease }) {
                pressReleaseActions[origin.senderID, default: [:]][key] = assignment.pressReleaseActions
                pairedAction = assignment.pressReleaseActions.onPress
                isPressRelease = true
            }
            let otherDevicePressed = states.contains { $0.key != origin.senderID && !$0.value.physicalPressed.isEmpty }
            for sender in states.keys where sender != origin.senderID { states[sender]?.cancel() }
            if otherDevicePressed { state.cancel() }
            fired = state.modifierDown(key, assignedKeys: otherDevicePressed ? [] : assignedKeys)
        } else {
            return Result()
        }
        states[origin.senderID] = state
        var suppress = false
        if key == .function {
            if isRelease {
                suppress = suppressedFunctionSenders.remove(origin.senderID) != nil
            } else if assignedKeys.contains(.function) {
                suppressedFunctionSenders.insert(origin.senderID)
                suppress = true
            }
        }
        var actions = fired.compactMap {
            automaticAction(for: $0, senderID: origin.senderID, assignments: automaticAssignments)
        }
        if isRelease { pressedAutomaticAssignments[origin.senderID]?.removeValue(forKey: key) }
        if pairedAction != .none { actions.append(pairedAction) }
        return Result(actions: actions, suppressEvent: suppress, isPressRelease: isPressRelease)
    }

    private func automaticAction(
        for key: ModifierKey, senderID: UInt64, assignments: [KeyAssignment]
    ) -> KeyAction? {
        guard let pressed = pressedAutomaticAssignments[senderID]?[key],
              let current = assignments.first(where: { $0.modifierKey == key }),
              current.id == pressed.id, current.action == pressed.action else { return nil }
        return current.action
    }

    mutating func cancel() {
        for sender in states.keys { states[sender]?.cancel() }
    }

    mutating func reset() {
        states.removeAll()
        suppressedFunctionSenders.removeAll()
        pressReleaseActions.removeAll()
        pressedAutomaticAssignments.removeAll()
    }
}
