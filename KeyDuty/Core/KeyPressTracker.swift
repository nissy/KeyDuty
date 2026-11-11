import AppKit
import IOKit.hidsystem

// flagsChangedには押下・解放の区別がないため、送信元ごとに修飾キーを追跡する。
struct KeyPressTracker {
    private var pressedModifiers: [UInt64: Set<ModifierKey>] = [:]
    private var capsLockEnabled = false

    mutating func reset(flags: CGEventFlags) {
        pressedModifiers.removeAll()
        capsLockEnabled = flags.contains(.maskAlphaShift)
    }

    mutating func isPress(type: CGEventType, event: CGEvent, senderID: UInt64) -> Bool {
        if type == .keyDown {
            return event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        }
        if type == SystemKeyInput.eventType {
            guard let cocoaEvent = NSEvent(cgEvent: event), let input = SystemKeyInput(cocoaEvent) else {
                return false
            }
            return input.isKeyDown && !input.isRepeat
        }
        guard type == .flagsChanged else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let capsLockChanged = capsLockEnabled != event.flags.contains(.maskAlphaShift)
        capsLockEnabled = event.flags.contains(.maskAlphaShift)
        if keyCode == 57 { return capsLockChanged }

        guard let key = ModifierKey.from(keyCode: keyCode) else { return false }
        if pressedModifiers[senderID, default: []].remove(key) != nil { return false }
        guard event.flags.contains(key.flagMask) else { return false }
        // 起動前から押されていた片側の解放を、反対側のフラグで押下と誤認しない。
        if let masks = Self.deviceMasks(for: key),
           event.flags.rawValue & masks.pair != 0,
           event.flags.rawValue & masks.key == 0 { return false }
        pressedModifiers[senderID, default: []].insert(key)
        return true
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
