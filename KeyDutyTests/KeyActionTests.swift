import XCTest
@testable import KeyDuty

final class KeyActionTests: XCTestCase {
    func testModifierKeyCodesIncludeLeftRightKeysAndFn() {
        XCTAssertEqual(ModifierKey.allCases.count, 9)
        for key in ModifierKey.allCases {
            XCTAssertEqual(ModifierKey.from(keyCode: Int64(key.keyCode)), key)
        }
    }

    func testPresetKeyCodes() {
        XCTAssertEqual(KeyAction.eisu, .sendKey(keyCode: 102))
        XCTAssertEqual(KeyAction.kana, .sendKey(keyCode: 104))
        XCTAssertEqual(
            KeyAction.functionKeyPresets,
            [
                .sendKey(keyCode: 105),
                .sendKey(keyCode: 107),
                .sendKey(keyCode: 113),
                .sendKey(keyCode: 106),
                .sendKey(keyCode: 64),
                .sendKey(keyCode: 79),
                .sendKey(keyCode: 80),
                .sendKey(keyCode: 90)
            ]
        )
        XCTAssertEqual(
            KeyAction.functionKeyPresets.map(\.displayName),
            ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20"]
        )
        XCTAssertEqual(
            KeyAction.selectablePresets,
            [.none, .eisu, .kana] + KeyAction.functionKeyPresets
        )
    }

    func testModifierKeyCannotBeUsedAsAction() {
        XCTAssertFalse(KeyAction.sendKey(keyCode: ModifierKey.leftCommand.keyCode).isValid)
        XCTAssertFalse(KeyAction.sendKey(keyCode: 57).isValid)
        XCTAssertFalse(KeyAction.sendKey(keyCode: 63).isValid)
        XCTAssertTrue(KeyAction.sendKey(keyCode: 105).isValid)
    }

    func testCodableRoundTrip() throws {
        let action = KeyAction.sendKey(keyCode: 105)
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(KeyAction.self, from: data), action)
    }
}
