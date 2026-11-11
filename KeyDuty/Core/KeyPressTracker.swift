import AppKit
import IOKit.hidsystem

// 無操作判定のため、押下の開始と、物理的に押し続けているキーを送信元ごとに追跡する。
// flagsChangedには押下・解放の区別がないため、修飾キーはフラグの変化から判定する。
struct KeyPressTracker {
    enum Change: Equatable {
        case unchanged
        case press
        // 押していたキーがすべて離れた
        case allReleased
    }

    private struct HeldKey: Hashable {
        let senderID: UInt64
        let keyCode: CGKeyCode
    }

    private var pressedModifiers: [UInt64: Set<ModifierKey>] = [:]
    private var heldKeys: Set<HeldKey> = []
    private var heldSystemKeys: Set<HeldKey> = []
    private var capsLockEnabled = false

    var isHoldingKeys: Bool {
        !heldKeys.isEmpty || !heldSystemKeys.isEmpty || pressedModifiers.values.contains { !$0.isEmpty }
    }

    mutating func reset(flags: CGEventFlags) {
        pressedModifiers.removeAll()
        heldKeys.removeAll()
        heldSystemKeys.removeAll()
        capsLockEnabled = flags.contains(.maskAlphaShift)
    }

    mutating func update(type: CGEventType, event: CGEvent, senderID: UInt64) -> Change {
        let wasHolding = isHoldingKeys
        let isPress = record(type: type, event: event, senderID: senderID)
        if isPress { return .press }
        return wasHolding && !isHoldingKeys ? .allReleased : .unchanged
    }

    // 解放イベントを取りこぼしたキーを、OSが報告する物理状態で取り除く。
    // 特殊キーとFnは仮想キーの状態で判定できないため対象外。
    @discardableResult
    mutating func removeReleasedKeys(isKeyDown: (CGKeyCode) -> Bool) -> Bool {
        let wasHolding = isHoldingKeys
        heldKeys = heldKeys.filter { isKeyDown($0.keyCode) }
        for (senderID, keys) in pressedModifiers {
            pressedModifiers[senderID] = keys.filter { $0 == .function || isKeyDown($0.keyCode) }
        }
        return wasHolding && !isHoldingKeys
    }

    private mutating func record(type: CGEventType, event: CGEvent, senderID: UInt64) -> Bool {
        let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown {
            heldKeys.insert(HeldKey(senderID: senderID, keyCode: keyCode))
            return event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        }
        if type == .keyUp {
            Self.release(keyCode, senderID: senderID, from: &heldKeys)
            return false
        }
        if type == SystemKeyInput.eventType {
            guard let cocoaEvent = NSEvent(cgEvent: event), let input = SystemKeyInput(cocoaEvent) else {
                return false
            }
            if input.isKeyDown {
                heldSystemKeys.insert(HeldKey(senderID: senderID, keyCode: input.keyCode))
            } else {
                Self.release(input.keyCode, senderID: senderID, from: &heldSystemKeys)
            }
            return input.isKeyDown && !input.isRepeat
        }
        guard type == .flagsChanged else { return false }

        let capsLockChanged = capsLockEnabled != event.flags.contains(.maskAlphaShift)
        capsLockEnabled = event.flags.contains(.maskAlphaShift)
        if keyCode == 57 { return capsLockChanged }

        guard let key = ModifierKey.from(keyCode: Int64(keyCode)) else { return false }
        if pressedModifiers[senderID, default: []].remove(key) != nil { return false }
        guard event.flags.contains(key.flagMask) else { return false }
        // 起動前から押されていた片側の解放を、反対側のフラグで押下と誤認しない。
        if let masks = Self.deviceMasks(for: key),
           event.flags.rawValue & masks.pair != 0,
           event.flags.rawValue & masks.key == 0 { return false }
        pressedModifiers[senderID, default: []].insert(key)
        return true
    }

    // 送信元が欠けた解放は、どのキーボードの押下か判別できないため同じキーをすべて解放する。
    private static func release(_ keyCode: CGKeyCode, senderID: UInt64, from keys: inout Set<HeldKey>) {
        if senderID == 0 || keys.remove(HeldKey(senderID: senderID, keyCode: keyCode)) == nil {
            keys = keys.filter { $0.keyCode != keyCode }
        }
    }

    private static func deviceMasks(for key: ModifierKey) -> (key: UInt64, pair: UInt64)? {
        let left: Int32
        let right: Int32
        let isLeft: Bool
        switch key {
        case .leftCommand, .rightCommand:
            (left, right, isLeft) = (NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK, key == .leftCommand)
        case .leftShift, .rightShift:
            (left, right, isLeft) = (NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK, key == .leftShift)
        case .leftControl, .rightControl:
            (left, right, isLeft) = (NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK, key == .leftControl)
        case .leftOption, .rightOption:
            (left, right, isLeft) = (NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK, key == .leftOption)
        case .function:
            return nil
        }
        return (UInt64(isLeft ? left : right), UInt64(left | right))
    }
}
