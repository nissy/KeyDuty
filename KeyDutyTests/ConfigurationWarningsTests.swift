import XCTest
@testable import KeyDuty

@MainActor
final class ConfigurationWarningsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var preferences: Preferences!

    override func setUp() async throws {
        suite = "ConfigurationWarningsTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = []
        preferences.idleEnabled = false
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testHoldAndBothSplitOutputsIdentifyBothRowsAndDeduplicateSameKey() throws {
        let hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        var split = KeyAssignment(sourceKeyCode: 105, action: .none)
        split.setSeparatesPressAndRelease(true)
        split.pressReleaseActions = PressReleaseActions(onPress: .sendKey(keyCode: 11),
                                                       onRelease: .sendKey(keyCode: 11))
        preferences.keyAssignments = [hold, split]
        let conflicts = preferences.configurationWarnings.keyHoldConflicts
        XCTAssertEqual(conflicts.count, 1)
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(conflict.keyCode, 11)
        XCTAssertEqual(conflict.holdingAssignments.map(\.id), [hold.id])
        XCTAssertEqual(conflict.sendingAssignments.map(\.id), [split.id])
        XCTAssertTrue(conflict.involves(hold))
        XCTAssertTrue(conflict.involves(split))
        XCTAssertTrue(conflict.message.contains(L10n.text("format.quote", "A")))
        XCTAssertTrue(conflict.message.contains(split.inputName))
        XCTAssertFalse(conflict.includesIdle)
    }

    func testSingleTapsCapsLockAndShortcutsAreSendersRatherThanHolders() throws {
        let hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        let taps = [
            KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 63, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 57, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 1, destinationKeyCode: 11, sourceModifiers: [.command, .shift])
        ]
        preferences.keyAssignments = [hold] + taps
        let conflict = try XCTUnwrap(preferences.configurationWarnings.keyHoldConflicts.first)
        XCTAssertEqual(conflict.holdingAssignments.map(\.id), [hold.id])
        XCTAssertEqual(conflict.sendingAssignments.map(\.id), taps.map(\.id))
    }

    func testUnrelatedOutputsHoldPairsAndTapPairsDoNotWarn() {
        var split = KeyAssignment(sourceKeyCode: 105, action: .none)
        split.setSeparatesPressAndRelease(true)
        split.pressReleaseActions.onPress = .kana
        preferences.keyAssignments = [
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 1, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 55, action: .kana), split,
            KeyAssignment(sourceKeyCode: 2, action: .system(.mediaPlay))
        ]
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
    }

    func testOnlyActiveSplitOutputsAreConsidered() {
        let hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        var split = KeyAssignment(sourceKeyCode: 105, destinationKeyCode: 11)
        split.setSeparatesPressAndRelease(true)
        split.pressReleaseActions = PressReleaseActions(onRelease: .system(.mediaPause))
        preferences.keyAssignments = [hold, split]
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        preferences.keyAssignments[1].pressReleaseActions.onRelease = .sendKey(keyCode: 11)
        XCTAssertEqual(preferences.configurationWarnings.keyHoldConflicts.count, 1)
        preferences.keyAssignments[1].pressReleaseActions = PressReleaseActions()
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
    }

    func testDisabledInvalidAndDuplicateRowsDoNotWarnAndReenableUpdatesWarning() {
        let hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        let tap = KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 11, isEnabled: false)
        preferences.keyAssignments = [hold, tap]
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        preferences.keyAssignments[1].isEnabled = true
        XCTAssertEqual(preferences.configurationWarnings.keyHoldConflicts.count, 1)
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 55, action: .kana))
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        preferences.keyAssignments.removeLast()
        preferences.keyAssignments[0].isEnabled = false
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        preferences.keyAssignments[0].isEnabled = true
        preferences.keyAssignments[0].sourceKeyCode = nil
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
    }

    func testIdleWarnsAboutHeldKeysEvenWithoutAssignmentsAndStopsWhenDisabledOrUnselected() {
        preferences.idleEnabled = true
        XCTAssertNotNil(preferences.configurationWarnings.idleHoldMessage)
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        preferences.idleEnabled = false
        XCTAssertNil(preferences.configurationWarnings.idleHoldMessage)
        preferences.idleEnabled = true
        preferences.idleAction = .none
        XCTAssertNil(preferences.configurationWarnings.idleHoldMessage)
    }

    func testIdleSameOutputConflictAppearsForHoldRowAndIdleAndUpdatesAfterEditing() throws {
        let hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        preferences.keyAssignments = [hold]
        preferences.idleEnabled = true
        preferences.idleAction = .sendKey(keyCode: 11)
        let conflict = try XCTUnwrap(preferences.configurationWarnings.keyHoldConflicts.first)
        XCTAssertTrue(conflict.includesIdle)
        XCTAssertTrue(conflict.involves(hold))
        XCTAssertTrue(conflict.sendingAssignments.isEmpty)
        XCTAssertTrue(conflict.message.contains(L10n.text("tab.idle")))
        preferences.idleAction = .eisu
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
        XCTAssertNotNil(preferences.configurationWarnings.idleHoldMessage)
        preferences.idleAction = .sendKey(keyCode: 11)
        preferences.idleEnabled = false
        XCTAssertTrue(preferences.configurationWarnings.keyHoldConflicts.isEmpty)
    }

    func testDifferentKeyboardExclusionsDoNotHidePotentialCrossDeviceConflict() throws {
        var hold = KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)
        hold.ignoredKeyboardIDs = ["external"]
        var tap = KeyAssignment(sourceKeyCode: 105, destinationKeyCode: 11, sourceModifiers: .command)
        tap.ignoredKeyboardIDs = ["internal"]
        preferences.keyAssignments = [hold, tap]
        let conflict = try XCTUnwrap(preferences.configurationWarnings.keyHoldConflicts.first)
        XCTAssertTrue(conflict.involves(hold))
        XCTAssertTrue(conflict.involves(tap))
    }

    func testSeveralHoldersAreGroupedAndDifferentOutputsAreSortedWithoutMutatingSettings() {
        var split = KeyAssignment(sourceKeyCode: 105, action: .none)
        split.setSeparatesPressAndRelease(true)
        split.pressReleaseActions = PressReleaseActions(onPress: .sendKey(keyCode: 12),
                                                       onRelease: .sendKey(keyCode: 11))
        let assignments = [
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 12),
            KeyAssignment(sourceKeyCode: 1, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 2, destinationKeyCode: 11), split
        ]
        preferences.keyAssignments = assignments
        let before = defaults.data(forKey: "keyAssignments")
        let conflicts = preferences.configurationWarnings.keyHoldConflicts
        XCTAssertEqual(conflicts.map(\.keyCode), [11, 12])
        XCTAssertEqual(conflicts.first?.holdingAssignments.map(\.id), [assignments[1].id, assignments[2].id])
        XCTAssertEqual(conflicts.last?.sendingAssignments.map(\.id), [split.id])
        XCTAssertEqual(preferences.keyAssignments, assignments)
        XCTAssertEqual(defaults.data(forKey: "keyAssignments"), before)
    }
}
