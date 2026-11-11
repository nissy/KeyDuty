import XCTest
@testable import KeyDuty

@MainActor
final class SystemActionPreferencesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "SystemActionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testExistingUnifiedRowsMigrateWithoutLosingIdentityOrderOrDisabledState() throws {
        try withDefaults { defaults in
            let firstID = UUID(), secondID = UUID(), emptyID = UUID()
            let legacy = """
            [
              {"id":"\(firstID)","sourceKeyCode":55,"destinationKeyCode":102,"isEnabled":true},
              {"id":"\(secondID)","sourceKeyCode":0,"destinationKeyCode":11,"isEnabled":false},
              {"id":"\(emptyID)","isEnabled":true}
            ]
            """
            defaults.set(Data(legacy.utf8), forKey: "keyAssignments")
            let preferences = Preferences(defaults: defaults)
            XCTAssertEqual(preferences.keyAssignments.map(\.id), [firstID, secondID, emptyID])
            XCTAssertEqual(preferences.keyAssignments.map(\.action), [.eisu, .sendKey(keyCode: 11), .none])
            XCTAssertFalse(preferences.keyAssignments[1].isEnabled)
            XCTAssertFalse(preferences.keyAssignments[2].isValid)
            XCTAssertEqual(preferences.assignedKeys(), [.leftCommand])
            XCTAssertEqual(Preferences(defaults: defaults).keyAssignments, preferences.keyAssignments)
            let saved = try XCTUnwrap(defaults.data(forKey: "keyAssignments"))
            XCTAssertFalse(try XCTUnwrap(String(data: saved, encoding: .utf8)).contains("destinationKeyCode"))
        }
    }

    func testAllSixActionsPersistAndRouteForBothInputTypes() throws {
        try withDefaults { defaults in
            for action in SystemAction.allCases {
                let preferences = Preferences(defaults: defaults)
                preferences.keyAssignments = [
                    KeyAssignment(sourceKeyCode: 55, action: .system(action)),
                    KeyAssignment(sourceKeyCode: 0, action: .system(action))
                ]
                let restored = Preferences(defaults: defaults)
                XCTAssertEqual(restored.keyAssignments, preferences.keyAssignments)
                XCTAssertEqual(restored.action(for: .leftCommand), .system(action))
                XCTAssertEqual(restored.assignedKeys(), [.leftCommand])
                XCTAssertEqual(restored.activeSystemActions, [0: action])
                XCTAssertTrue(restored.activeKeyRemappings.isEmpty)
                XCTAssertEqual(restored.keyAssignments.map(\.behaviorName),
                               [L10n.text("behavior.tap"), L10n.text("behavior.release")])
                let encoded = try JSONEncoder().encode(KeyAction.system(action))
                XCTAssertEqual(try JSONDecoder().decode(KeyAction.self, from: encoded), .system(action))
            }
        }
    }

    func testKeyAndSystemActionWithSameSourceConflictUntilOneIsDisabled() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
                KeyAssignment(sourceKeyCode: 0, action: .system(.lockScreen))
            ]
            XCTAssertTrue(preferences.activeKeyRemappings.isEmpty)
            XCTAssertTrue(preferences.activeSystemActions.isEmpty)
            XCTAssertTrue(preferences.hasDuplicateSource(preferences.keyAssignments[1]))
            preferences.keyAssignments[0].isEnabled = false
            XCTAssertEqual(preferences.activeSystemActions, [0: .lockScreen])
            preferences.keyAssignments[1].action = .sendKey(keyCode: 8)
            XCTAssertTrue(preferences.activeSystemActions.isEmpty)
            XCTAssertEqual(preferences.activeKeyRemappings, [0: 8])
        }
    }

    func testSystemActionRequiresSupportedInputAndDoesNotBecomeAnIdleAction() {
        XCTAssertFalse(KeyAssignment(action: .system(.sleep)).isValid)
        XCTAssertTrue(KeyAssignment(sourceKeyCode: 57, action: .system(.sleep)).isValid)
        XCTAssertTrue(KeyAssignment(sourceKeyCode: 63, action: .system(.sleep)).isValid)
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.setAction(.system(.mediaPause), for: .rightShift)
            preferences.setEnabled(true, for: .rightShift)
            XCTAssertEqual(preferences.action(for: .rightShift), .system(.mediaPause))
            XCTAssertTrue(preferences.assignedKeys().contains(.rightShift))
            preferences.idleAction = .system(.sleep)
            XCTAssertEqual(preferences.idleAction, .eisu)
        }
    }

    func testMediaCommandsAreSeparateAndNeverToggle() {
        XCTAssertEqual(SystemAction.mediaPlay.mediaCommand, 0)
        XCTAssertEqual(SystemAction.mediaPause.mediaCommand, 1)
        XCTAssertNil(SystemAction.lockScreen.mediaCommand)
    }
}
