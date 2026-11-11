import XCTest
@testable import KeyDuty

@MainActor
final class ShortcutPreferencesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ShortcutPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testExistingSingleKeyAndModifierRowsKeepTheirMeaning() throws {
        try withDefaults { defaults in
            let legacy = """
            [{"id":"\(UUID())","sourceKeyCode":60,"action":{"system":{"_0":"sleep"}},"isEnabled":true},
             {"id":"\(UUID())","sourceKeyCode":0,"destinationKeyCode":11,"isEnabled":false}]
            """
            defaults.set(Data(legacy.utf8), forKey: "keyAssignments")
            let preferences = Preferences(defaults: defaults)
            XCTAssertTrue(preferences.keyAssignments.allSatisfy { $0.sourceModifiers.isEmpty })
            XCTAssertEqual(preferences.action(for: .rightShift), .system(.sleep))
            XCTAssertEqual(preferences.assignedKeys(), [.rightShift])
            XCTAssertTrue(preferences.activeShortcuts.isEmpty)
            XCTAssertFalse(preferences.keyAssignments[1].isEnabled)
            let encoded = try JSONEncoder().encode(preferences.keyAssignments)
            XCTAssertEqual(try JSONDecoder().decode([KeyAssignment].self, from: encoded), preferences.keyAssignments)
        }
    }

    func testDifferentCombinationsOnSameKeyCoexistAndPersist() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
                KeyAssignment(sourceKeyCode: 0, action: .system(.sleep), sourceModifiers: [.command, .shift]),
                KeyAssignment(sourceKeyCode: 0, action: .system(.mediaPlay), sourceModifiers: [.control])
            ]
            let restored = Preferences(defaults: defaults)
            XCTAssertEqual(restored.keyAssignments, preferences.keyAssignments)
            XCTAssertEqual(restored.activeKeyRemappings, [0: 11])
            XCTAssertTrue(restored.activeSystemActions.isEmpty)
            XCTAssertEqual(restored.activeShortcuts, [
                KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift]): .system(.sleep),
                KeyboardShortcut(keyCode: 0, modifiers: [.control]): .system(.mediaPlay)
            ])
            XCTAssertFalse(restored.hasDuplicateSource(restored.keyAssignments[1]))
            XCTAssertEqual(restored.keyAssignments[1].inputName, "⇧⌘ A")
            XCTAssertEqual(restored.keyAssignments[1].behaviorName, L10n.text("behavior.shortcut"))
        }
    }

    func testOnlyIdenticalCombinationsConflict() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.keyAssignments = [
                KeyAssignment(sourceKeyCode: 0, action: .system(.sleep), sourceModifiers: [.command]),
                KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11, sourceModifiers: [.command]),
                KeyAssignment(sourceKeyCode: 0, action: .system(.mediaPause), sourceModifiers: [.command, .shift])
            ]
            XCTAssertTrue(preferences.hasDuplicateSource(preferences.keyAssignments[0]))
            XCTAssertEqual(preferences.activeShortcuts.count, 1)
            preferences.keyAssignments[1].isEnabled = false
            XCTAssertEqual(preferences.activeShortcuts.count, 2)
            preferences.keyAssignments[0].sourceModifiers = []
            XCTAssertEqual(preferences.activeSystemActions, [0: .sleep])
            XCTAssertEqual(preferences.activeShortcuts.count, 1)
        }
    }

    func testShortcutRequiresOrdinaryKeyAndSupportsSendingSameKeyWithoutModifiers() {
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: []).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 60, modifiers: [.command]).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 57, modifiers: [.command]).isValid)
        XCTAssertTrue(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 0, sourceModifiers: [.command]).isValid)
        XCTAssertFalse(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 0).isValid)
        XCTAssertFalse(KeyAssignment(sourceKeyCode: 55, action: .system(.sleep), sourceModifiers: [.shift]).isValid)
        XCTAssertFalse(KeyAssignment(action: .system(.sleep), sourceModifiers: [.shift]).isValid)
        let flags = ShortcutModifiers(flags: [.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn])
        XCTAssertEqual(flags, [.command, .shift, .function])
    }
}
