import XCTest
@testable import KeyDuty

@MainActor
final class KeyboardExclusionPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "KeyboardExclusionTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testLegacyExclusionsMigrateOnlyToModifierRowsOnce() throws {
        let assignments = [
            KeyAssignment(sourceKeyCode: 55, action: .eisu),
            KeyAssignment(sourceKeyCode: 60, action: .system(.displayOff), isEnabled: false),
            KeyAssignment(sourceKeyCode: 0, action: .kana),
            KeyAssignment(sourceKeyCode: 1, action: .system(.sleep), sourceModifiers: .command)
        ]
        defaults.set(try JSONEncoder().encode(assignments), forKey: "keyAssignments")
        defaults.set(try JSONEncoder().encode(["old-keyboard"]), forKey: "ignoredKeyboardIDs")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(
            preferences.keyAssignments.map(\.ignoredKeyboardIDs), [["old-keyboard"], ["old-keyboard"], [], []]
        )
        XCTAssertFalse(preferences.keyAssignments[1].isEnabled)
        preferences.keyAssignments[0].ignoredKeyboardIDs = []
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 63, action: .eisu))
        let restored = Preferences(defaults: defaults)
        XCTAssertTrue(restored.keyAssignments[0].ignoredKeyboardIDs.isEmpty)
        XCTAssertTrue(restored.keyAssignments[4].ignoredKeyboardIDs.isEmpty)
        XCTAssertEqual(restored.keyAssignments[1].ignoredKeyboardIDs, ["old-keyboard"])
    }

    func testLegacyModifierMappingsAlsoMigrate() throws {
        defaults.set(try JSONEncoder().encode(["old-keyboard"]), forKey: "ignoredKeyboardIDs")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.keyAssignments.count, 2)
        XCTAssertTrue(preferences.keyAssignments.allSatisfy { $0.ignoredKeyboardIDs == ["old-keyboard"] })
    }

    func testExclusionsAreIndependentAndUnknownDeviceDoesNotTriggerRestrictedRows() {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments[0].ignoredKeyboardIDs = ["external"]
        XCTAssertEqual(preferences.assignments(for: "external").compactMap(\.modifierKey), [.rightCommand])
        XCTAssertEqual(preferences.assignments(for: "internal").count, 2)
        XCTAssertEqual(preferences.assignments(for: nil).compactMap(\.modifierKey), [.rightCommand])
        XCTAssertEqual(Preferences(defaults: defaults).keyAssignments[0].ignoredKeyboardIDs, ["external"])
    }

    func testDisconnectedKeyboardNamesPersist() {
        let preferences = Preferences(defaults: defaults)
        preferences.rememberKeyboards([
            KeyboardDevice(id: "1234:0001", name: "Test Keyboard", vendorID: 0x1234, productID: 1, transport: "USB")
        ])
        preferences.rememberKeyboards([])
        XCTAssertEqual(Preferences(defaults: defaults).keyboardNames["1234:0001"], "Test Keyboard")
    }

    func testOldAssignmentWithoutExclusionFieldDecodes() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","sourceKeyCode":0,"destinationKeyCode":11,"isEnabled":true}
        """.utf8)
        XCTAssertTrue(try JSONDecoder().decode(KeyAssignment.self, from: data).ignoredKeyboardIDs.isEmpty)
    }
}
