import CoreGraphics
import XCTest
@testable import KeyDuty

@MainActor
final class KeyAssignmentPreferencesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "KeyAssignmentPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testMigratesBothOldFormatsIncludingDisabledAndIncompleteRows() throws {
        try withDefaults { defaults in
            let mappings: [ModifierKey: KeyAction] = [.leftCommand: .eisu, .rightCommand: .kana, .leftShift: .f13]
            let enabled: [ModifierKey: Bool] = [.leftCommand: true, .rightCommand: false, .leftShift: false]
            let remappings = [KeyRemapping(sourceKeyCode: 0, destinationKeyCode: 11, isEnabled: false), KeyRemapping()]
            defaults.set(try JSONEncoder().encode(mappings), forKey: "keyMappings")
            defaults.set(try JSONEncoder().encode(enabled), forKey: "keyEnabled")
            defaults.set(try JSONEncoder().encode(remappings), forKey: "keyRemappings")

            let preferences = Preferences(defaults: defaults)
            XCTAssertEqual(preferences.keyAssignments.count, 5)
            XCTAssertEqual(preferences.keyAssignments.prefix(3).compactMap(\.modifierKey),
                           [.leftCommand, .rightCommand, .leftShift])
            XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])
            XCTAssertEqual(preferences.action(for: .leftShift), .f13)
            XCTAssertFalse(preferences.isEnabled(.rightCommand))
            XCTAssertEqual(preferences.keyAssignments[3].id, remappings[0].id)
            XCTAssertFalse(preferences.keyAssignments[3].isEnabled)
            XCTAssertNil(preferences.keyAssignments[4].sourceKeyCode)
            XCTAssertEqual(Preferences(defaults: defaults).keyAssignments, preferences.keyAssignments)
        }
    }

    func testDeletingAllRowsDoesNotRestoreLegacyMappingsOnRelaunch() throws {
        try withDefaults { defaults in
            defaults.set(try JSONEncoder().encode(Preferences.defaultMappings), forKey: "keyMappings")
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments.removeAll()

            let restored = Preferences(defaults: defaults)
            XCTAssertTrue(restored.keyAssignments.isEmpty)
            XCTAssertTrue(restored.assignedKeys().isEmpty)
        }
    }

    func testChangingInputBetweenModifierAndOrdinaryUpdatesBehaviorWithoutLeavingOldMapping() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102)]
            let id = preferences.keyAssignments[0].id
            XCTAssertEqual(preferences.keyAssignments[0].behaviorName, L10n.text("behavior.tap"))
            XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])

            preferences.keyAssignments[0].sourceKeyCode = 0
            XCTAssertEqual(preferences.keyAssignments[0].behaviorName, L10n.text("behavior.remap"))
            XCTAssertTrue(preferences.assignedKeys().isEmpty)
            XCTAssertEqual(preferences.action(for: .leftCommand), .none)
            XCTAssertEqual(preferences.activeKeyRemappings, [0: 102])

            preferences.keyAssignments[0].sourceKeyCode = 60
            XCTAssertEqual(preferences.assignedKeys(), [.rightShift])
            XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
            XCTAssertEqual(preferences.keyAssignments[0].id, id)
        }
    }

    func testEnabledModifierUsesItsDestinationWhenDuplicateRowIsDisabled() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102, isEnabled: false),
                KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 104)
            ]
            XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])
            XCTAssertEqual(preferences.action(for: .leftCommand), .kana)

            preferences.keyAssignments[0].isEnabled = true
            XCTAssertTrue(preferences.assignedKeys().isEmpty)
            XCTAssertTrue(preferences.hasDuplicateSource(preferences.keyAssignments[0]))
        }
    }

    func testIncompleteOrInvalidRowsDoNotDisableExistingAssignments() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102),
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
                KeyAssignment(sourceKeyCode: 55),
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 0)
            ]
            XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])
            XCTAssertEqual(preferences.activeKeyRemappings, [0: 11])
            XCTAssertFalse(preferences.hasDuplicateSource(preferences.keyAssignments[0]))
            XCTAssertFalse(preferences.hasDuplicateSource(preferences.keyAssignments[1]))

            preferences.keyAssignments[2].destinationKeyCode = 104
            XCTAssertTrue(preferences.assignedKeys().isEmpty)
            XCTAssertTrue(preferences.hasDuplicateSource(preferences.keyAssignments[2]))
        }
    }

    func testDeletingModifierAndOrdinaryRowsStopsBothBehaviors() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102),
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
            ]
            preferences.keyAssignments.removeAll()
            XCTAssertEqual(preferences.action(for: .leftCommand), .none)
            XCTAssertTrue(preferences.assignedKeys().isEmpty)
            XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
        }
    }

    func testFnAndCapsLockAreInputsButModifierDestinationsRemainInvalid() {
        for code: CGKeyCode in [57, 63] {
            XCTAssertTrue(KeyAssignment(sourceKeyCode: code, destinationKeyCode: 0).isValid)
            XCTAssertFalse(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: code).isValid)
        }
        XCTAssertFalse(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 55).isValid)
        XCTAssertTrue(KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 0).isValid)
        XCTAssertFalse(KeyAssignment().isValid)
    }
}
