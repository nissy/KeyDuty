import CoreGraphics

struct KeyHoldConflict: Identifiable {
    let keyCode: CGKeyCode
    let holdingAssignments: [KeyAssignment]
    let sendingAssignments: [KeyAssignment]

    var id: CGKeyCode { keyCode }

    func involves(_ assignment: KeyAssignment) -> Bool {
        holdingAssignments.contains { $0.id == assignment.id } ||
            sendingAssignments.contains { $0.id == assignment.id }
    }

    var message: String {
        let separator = L10n.text("list.separator")
        let holders = holdingAssignments.map { L10n.text("format.quote", $0.inputName) }.joined(separator: separator)
        let senders = sendingAssignments.map { L10n.text("format.quote", $0.inputName) }.joined(separator: separator)
        return L10n.text("warnings.keyHold", holders, KeyCatalog.name(for: keyCode), senders)
    }
}

struct ConfigurationWarnings {
    let keyHoldConflicts: [KeyHoldConflict]

    // 実際に有効な行だけを受け取り、実行中の設定とは独立して注意を計算する。
    // 自動送信はキーの押下中に実行しないため、保持中の出力キーとは干渉しない。
    init(activeAssignments: [KeyAssignment]) {
        let heldKeys = Set(activeAssignments.compactMap(Self.heldKey))
        keyHoldConflicts = heldKeys.sorted().compactMap { keyCode in
            let holders = activeAssignments.filter { Self.heldKey($0) == keyCode }
            let senders = activeAssignments.filter { Self.tappedKeys($0).contains(keyCode) }
            guard !senders.isEmpty else { return nil }
            // 除外する機種が異なっても、別キーボードからの同時入力で干渉し得る。
            return KeyHoldConflict(keyCode: keyCode, holdingAssignments: holders, sendingAssignments: senders)
        }
    }

    private static func heldKey(_ assignment: KeyAssignment) -> CGKeyCode? {
        guard !assignment.separatesPressAndRelease, assignment.sourceModifiers.isEmpty,
              let source = assignment.sourceKeyCode, !ModifierKey.isModifierKeyCode(source)
        else { return nil }
        return assignment.destinationKeyCode
    }

    private static func tappedKeys(_ assignment: KeyAssignment) -> Set<CGKeyCode> {
        guard heldKey(assignment) == nil else { return [] }
        let actions = assignment.separatesPressAndRelease
            ? [assignment.pressReleaseActions.onPress, assignment.pressReleaseActions.onRelease]
            : [assignment.action]
        return Set(actions.compactMap { action in
            if case let .sendKey(code) = action { return code }
            return nil
        })
    }
}

extension Preferences {
    var configurationWarnings: ConfigurationWarnings {
        ConfigurationWarnings(activeAssignments: activeAssignments)
    }
}
