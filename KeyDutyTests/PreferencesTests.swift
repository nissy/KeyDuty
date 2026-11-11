import XCTest
@testable import KeyDuty

@MainActor
final class PreferencesTests: XCTestCase {
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "KeyDutyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    func testDefaultsMatchSpecification() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.action(for: .leftCommand), .eisu)
        XCTAssertEqual(preferences.action(for: .rightCommand), .kana)
        XCTAssertTrue(preferences.isEnabled(.leftCommand))
        XCTAssertTrue(preferences.isEnabled(.rightCommand))
        XCTAssertFalse(preferences.isEnabled(.leftShift))
        XCTAssertFalse(preferences.idleEnabled)
        XCTAssertEqual(preferences.idleTimeoutSeconds, 60)
        XCTAssertEqual(preferences.idleAction, .eisu)
        XCTAssertTrue(preferences.keyAssignments.allSatisfy { $0.ignoredKeyboardIDs.isEmpty })
    }

    func testSettingsPersistAcrossInstances() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var preferences: Preferences? = Preferences(defaults: defaults)
        preferences?.setAction(.sendKey(keyCode: 105), for: .leftShift)
        preferences?.setEnabled(true, for: .leftShift)
        preferences?.idleEnabled = true
        preferences?.idleTimeoutSeconds = 90
        preferences?.idleAction = .kana
        preferences?.keyAssignments[0].ignoredKeyboardIDs = ["3434:0820"]
        preferences = nil

        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.action(for: .leftShift), .sendKey(keyCode: 105))
        XCTAssertTrue(restored.isEnabled(.leftShift))
        XCTAssertTrue(restored.idleEnabled)
        XCTAssertEqual(restored.idleTimeoutSeconds, 90)
        XCTAssertEqual(restored.idleAction, .kana)
        XCTAssertEqual(restored.keyAssignments[0].ignoredKeyboardIDs, ["3434:0820"])
    }

    func testIdleTimeoutIsClamped() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5.0, forKey: "idleTimeoutSeconds")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.idleTimeoutSeconds, 5)

        preferences.idleTimeoutSeconds = 0
        XCTAssertEqual(preferences.idleTimeoutSeconds, 5)

        preferences.idleTimeoutSeconds = 1_000
        XCTAssertEqual(preferences.idleTimeoutSeconds, 300)
    }

    func testInvalidModifierActionIsRejected() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        let original = preferences.action(for: .leftCommand)

        preferences.setAction(.sendKey(keyCode: ModifierKey.rightShift.keyCode), for: .leftCommand)

        XCTAssertEqual(preferences.action(for: .leftCommand), original)
    }

    func testAssignedKeysRequireEnabledNonEmptyAction() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        preferences.setEnabled(false, for: .rightCommand)
        preferences.setEnabled(true, for: .leftShift)
        XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])

        preferences.setAction(.f13, for: .leftShift)
        XCTAssertEqual(preferences.assignedKeys(), [.leftCommand, .leftShift])
    }

    func testIgnoredKeyboardCanBeRemoved() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        preferences.keyAssignments[0].ignoredKeyboardIDs.insert("3434:0820")
        preferences.keyAssignments[0].ignoredKeyboardIDs.remove("3434:0820")

        XCTAssertTrue(preferences.keyAssignments.allSatisfy { $0.ignoredKeyboardIDs.isEmpty })
    }

    func testInvalidIdleActionFallsBackToEisu() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        preferences.idleAction = .sendKey(keyCode: ModifierKey.leftShift.keyCode)

        XCTAssertEqual(preferences.idleAction, .eisu)
    }

    func testNewRemappingsStartEmptyWithoutChangingModifierDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.keyAssignments.compactMap(\.modifierKey), [.leftCommand, .rightCommand])
        XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
        XCTAssertEqual(preferences.action(for: .leftCommand), .eisu)
        XCTAssertEqual(preferences.action(for: .rightCommand), .kana)
    }

    func testAddingEditingDisablingAndDeletingRowsPersists() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        preferences.setAction(.f13, for: .leftCommand)
        let addedIndex = preferences.keyAssignments.count
        preferences.keyAssignments.append(KeyAssignment())
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        preferences.keyAssignments[addedIndex].sourceKeyCode = 48
        preferences.keyAssignments[addedIndex].destinationKeyCode = 53
        preferences.keyAssignments[addedIndex + 1].isEnabled = false

        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.keyAssignments, preferences.keyAssignments)
        XCTAssertEqual(restored.activeKeyRemappings, [48: 53])
        XCTAssertEqual(restored.action(for: .leftCommand), .f13)

        restored.keyAssignments.remove(at: addedIndex)
        let afterDeletion = Preferences(defaults: defaults)
        XCTAssertEqual(afterDeletion.keyAssignments.count, 3)
        XCTAssertTrue(afterDeletion.activeKeyRemappings.isEmpty)
    }

    func testIncompleteDisabledIdentityAndModifierMappingsDoNotRemapOrdinaryKeys() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [
            KeyAssignment(),
            KeyAssignment(sourceKeyCode: 0),
            KeyAssignment(sourceKeyCode: 11, destinationKeyCode: 8, isEnabled: false),
            KeyAssignment(sourceKeyCode: 48, destinationKeyCode: 48),
            KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 53),
            KeyAssignment(sourceKeyCode: 53, destinationKeyCode: 56)
        ]
        XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
    }

    func testDuplicateSourcesAreInactiveUntilConflictIsDisabled() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 8),
            KeyAssignment(sourceKeyCode: 48, destinationKeyCode: 53)
        ]
        XCTAssertEqual(preferences.activeKeyRemappings, [48: 53])
        XCTAssertTrue(preferences.hasDuplicateSource(preferences.keyAssignments[0]))

        preferences.keyAssignments[1].isEnabled = false
        XCTAssertEqual(preferences.activeKeyRemappings, [0: 11, 48: 53])
        XCTAssertFalse(preferences.hasDuplicateSource(preferences.keyAssignments[0]))
    }

    func testLegacyDataDoesNotOverrideSavedUnifiedAssignments() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        Preferences(defaults: defaults).setAction(.f14, for: .rightCommand)
        defaults.set(Data("invalid".utf8), forKey: "keyRemappings")

        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.keyAssignments.count, 2)
        XCTAssertEqual(restored.action(for: .rightCommand), .f14)
    }
}
