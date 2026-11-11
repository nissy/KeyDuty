import XCTest
@testable import KeyDuty

@MainActor
final class PressReleasePreferencesTests: XCTestCase {
    func testOldAssignmentsDecodeWithoutEnablingSplit() throws {
        let original = KeyAssignment(sourceKeyCode: 55, action: .eisu)
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "separatesPressAndRelease")
        json.removeValue(forKey: "pressReleaseActions")
        json.removeValue(forKey: "hasConfiguredPressReleaseActions")
        let restored = try JSONDecoder().decode(
            KeyAssignment.self, from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.behaviorName, L10n.text("behavior.tap"))
    }

    func testTogglePreservesBothConfigurationsAndPersistence() throws {
        let suite = "PressReleasePreferencesTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var assignment = KeyAssignment(sourceKeyCode: 55, action: .eisu)
        assignment.setSeparatesPressAndRelease(true)
        XCTAssertEqual(assignment.pressReleaseActions.onRelease, .eisu)
        assignment.pressReleaseActions = PressReleaseActions(onPress: .system(.mediaPlay), onRelease: .kana)
        assignment.ignoredKeyboardIDs = ["excluded"]
        preferences.keyAssignments = [assignment]
        XCTAssertTrue(preferences.assignedKeys().isEmpty)
        XCTAssertEqual(preferences.action(for: .leftCommand), .none)
        XCTAssertEqual(Preferences(defaults: defaults).keyAssignments, [assignment])

        assignment.setSeparatesPressAndRelease(false)
        XCTAssertEqual(assignment.action, .eisu)
        XCTAssertEqual(assignment.behaviorName, L10n.text("behavior.tap"))
        assignment.setSeparatesPressAndRelease(true)
        XCTAssertEqual(assignment.pressReleaseActions.onPress, .system(.mediaPlay))
        XCTAssertEqual(assignment.pressReleaseActions.onRelease, .kana)
    }

    func testInitialSplitKeepsExistingExecutionTiming() {
        var key = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        key.setSeparatesPressAndRelease(true)
        XCTAssertEqual(key.pressReleaseActions.onPress, .sendKey(keyCode: 11))
        XCTAssertEqual(key.pressReleaseActions.onRelease, .none)
        var action = KeyAssignment(sourceKeyCode: 0, action: .system(.sleep))
        action.setSeparatesPressAndRelease(true)
        XCTAssertEqual(action.pressReleaseActions.onPress, .none)
        XCTAssertEqual(action.pressReleaseActions.onRelease, .system(.sleep))
        var shortcut = KeyAssignment(sourceKeyCode: 0, action: .eisu, sourceModifiers: .command)
        shortcut.setSeparatesPressAndRelease(true)
        XCTAssertEqual(shortcut.pressReleaseActions.onRelease, .eisu)
    }

    func testClearedSplitDestinationsStayClearedAfterToggleAndReload() throws {
        var assignment = KeyAssignment(sourceKeyCode: 55, action: .system(.sleep))
        assignment.setSeparatesPressAndRelease(true)
        assignment.pressReleaseActions = PressReleaseActions()
        assignment.setSeparatesPressAndRelease(false)
        assignment = try JSONDecoder().decode(KeyAssignment.self, from: JSONEncoder().encode(assignment))
        assignment.setSeparatesPressAndRelease(true)
        XCTAssertTrue(assignment.pressReleaseActions.isEmpty, "Explicitly cleared actions must not restore sleep")
    }

    func testPreviouslySavedSplitConfigurationMigratesWithoutRestoringClearedActions() throws {
        for enabled in [false, true] {
            var assignment = KeyAssignment(sourceKeyCode: 55, action: .system(.sleep))
            assignment.setSeparatesPressAndRelease(true)
            assignment.pressReleaseActions = PressReleaseActions()
            assignment.setSeparatesPressAndRelease(enabled)
            let data = try JSONEncoder().encode(assignment)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json.removeValue(forKey: "hasConfiguredPressReleaseActions")
            assignment = try JSONDecoder().decode(
                KeyAssignment.self, from: JSONSerialization.data(withJSONObject: json)
            )
            assignment.setSeparatesPressAndRelease(false)
            assignment.setSeparatesPressAndRelease(true)
            XCTAssertTrue(assignment.pressReleaseActions.isEmpty)
        }
    }

    func testOneSidedAssignmentsAreValidAndInvalidOutputsRemainRejected() {
        var assignment = KeyAssignment(sourceKeyCode: 0, action: .none)
        assignment.setSeparatesPressAndRelease(true)
        XCTAssertFalse(assignment.isValid)
        assignment.pressReleaseActions.onRelease = .kana
        XCTAssertTrue(assignment.isValid)
        assignment.pressReleaseActions = PressReleaseActions(onPress: .eisu)
        XCTAssertTrue(assignment.isValid)
        assignment.pressReleaseActions.onRelease = .sendKey(keyCode: 55)
        XCTAssertFalse(assignment.isValid)
        assignment.pressReleaseActions.onRelease = .sendKey(keyCode: SystemKey.playPause.keyCode)
        XCTAssertFalse(assignment.isValid)
        assignment.pressReleaseActions.onRelease = .system(.lockScreen)
        XCTAssertTrue(assignment.isValid)
    }

    func testCapsLockKeepsItsToggleBehavior() {
        var assignment = KeyAssignment(sourceKeyCode: 57, action: .eisu)
        assignment.setSeparatesPressAndRelease(true)
        XCTAssertFalse(assignment.separatesPressAndRelease)
        XCTAssertEqual(assignment.behaviorName, L10n.text("behavior.toggle"))
        XCTAssertTrue(assignment.isValid)
        assignment.separatesPressAndRelease = true
        assignment.pressReleaseActions.onRelease = .kana
        XCTAssertFalse(assignment.isValid)
    }

    func testSplitAssignmentsNeverLeakIntoAutomaticRemappingAndStillConflictWithSameInput() throws {
        let suite = "PressReleasePreferencesTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var key = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        key.setSeparatesPressAndRelease(true)
        var action = KeyAssignment(sourceKeyCode: 1, action: .system(.sleep))
        action.setSeparatesPressAndRelease(true)
        var shortcut = KeyAssignment(sourceKeyCode: 2, action: .kana, sourceModifiers: .command)
        shortcut.setSeparatesPressAndRelease(true)
        preferences.keyAssignments = [key, action, shortcut]
        XCTAssertEqual(preferences.activeAssignments.count, 3)
        XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
        XCTAssertTrue(preferences.activeSystemActions.isEmpty)
        XCTAssertTrue(preferences.activeShortcuts.isEmpty)
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 12))
        XCTAssertTrue(preferences.hasDuplicateSource(key))
        XCTAssertFalse(preferences.activeAssignments.contains { $0.sourceKeyCode == 0 })
    }
}
