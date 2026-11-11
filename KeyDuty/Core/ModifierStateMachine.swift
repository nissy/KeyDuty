import Foundation

struct ModifierStateMachine {
    enum KeyState: Equatable, Sendable {
        case singlePressed
        case multiPressed
        case suppressed
    }

    private(set) var physicalPressed: Set<ModifierKey> = []
    private(set) var keyStates: [ModifierKey: KeyState] = [:]

    mutating func modifierDown(
        _ key: ModifierKey,
        assignedKeys: Set<ModifierKey>
    ) -> [ModifierKey] {
        guard !physicalPressed.contains(key) else { return [] }

        let assigned = assignedKeys.contains(key)
        let pressedAssigned = physicalPressed.intersection(assignedKeys)
        let pressedUnassigned = physicalPressed.subtracting(assignedKeys)
        physicalPressed.insert(key)

        if physicalPressed.contains(.function), physicalPressed.count > 1 {
            suppressSinglePressedKeys()
            if assigned { keyStates[key] = .suppressed }
            return []
        }

        guard assigned else {
            suppressSinglePressedKeys()
            return []
        }

        if !pressedUnassigned.isEmpty {
            keyStates[key] = .suppressed
            return []
        }

        if !pressedAssigned.isEmpty {
            for pressedKey in pressedAssigned where keyStates[pressedKey] == .singlePressed {
                keyStates[pressedKey] = .multiPressed
            }
            keyStates[key] = .multiPressed
            return [key]
        }

        keyStates[key] = .singlePressed
        return []
    }

    mutating func modifierUp(_ key: ModifierKey) -> [ModifierKey] {
        physicalPressed.remove(key)
        let state = keyStates.removeValue(forKey: key)
        return state == .singlePressed ? [key] : []
    }

    mutating func cancel() {
        suppressSinglePressedKeys()
    }

    mutating func reset() {
        physicalPressed.removeAll()
        keyStates.removeAll()
    }

    func isPhysicallyPressed(_ key: ModifierKey) -> Bool {
        physicalPressed.contains(key)
    }

    private mutating func suppressSinglePressedKeys() {
        for key in keyStates.keys where keyStates[key] == .singlePressed {
            keyStates[key] = .suppressed
        }
    }
}
