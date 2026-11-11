import AppKit
import Carbon
import XCTest
@testable import KeyDuty

final class KeyRemapperTests: XCTestCase {
    private func event(
        _ keyCode: CGKeyCode,
        down: Bool = true,
        repeating: Bool = false
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        return event
    }

    func testRemapsBothPressAndReleaseWithoutChangingEventType() throws {
        var remapper = KeyRemapper()
        let down = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11]).event)
        let up = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [0: 11]).event)

        XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
        XCTAssertTrue(remapper.reset().isEmpty)
    }

    func testPreservesShortcutModifiersAndRepeatMetadata() throws {
        var remapper = KeyRemapper()
        _ = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11]).event)
        var repeated = try event(0, repeating: true)
        repeated.flags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        repeated.timestamp = 123_456
        repeated.setIntegerValueField(.keyboardEventKeyboardType, value: 40)

        repeated = try XCTUnwrap(remapper.remap(repeated, mappings: [0: 11]).event)

        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventAutorepeat), 1)
        XCTAssertEqual(repeated.flags, [.maskCommand, .maskShift, .maskControl, .maskAlternate])
        XCTAssertEqual(repeated.timestamp, 123_456)
        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventKeyboardType), 40)
    }

    func testChangingOrDeletingMappingWhileHeldKeepsOriginalDestinationUntilRelease() throws {
        var remapper = KeyRemapper()
        _ = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11]).event)
        let repeated = try XCTUnwrap(remapper.remap(event(0, repeating: true), mappings: [0: 8]).event)
        let up = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [:]).event)

        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 11)

        let nextDown = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 8]).event)
        XCTAssertEqual(nextDown.getIntegerValueField(.keyboardEventKeycode), 8)
    }

    func testEnablingMappingWhileUnmappedKeyIsHeldWaitsForNextPress() throws {
        var remapper = KeyRemapper()
        _ = try XCTUnwrap(remapper.remap(event(0), mappings: [:]).event)
        let repeated = try XCTUnwrap(remapper.remap(event(0, repeating: true), mappings: [0: 11]).event)
        let up = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [0: 11]).event)

        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventKeycode), 0)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 0)
    }

    func testKeysHeldBeforeStartupAreNotRemappedMidPress() throws {
        var remapper = KeyRemapper()
        let repeated = try XCTUnwrap(remapper.remap(event(0, repeating: true), mappings: [0: 11]).event)
        let up = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [0: 11]).event)
        XCTAssertEqual(repeated.getIntegerValueField(.keyboardEventKeycode), 0)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 0)

        let nextDown = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11]).event)
        XCTAssertEqual(nextDown.getIntegerValueField(.keyboardEventKeycode), 11)
    }

    func testUnmatchedReleaseIsNotRemapped() throws {
        var remapper = KeyRemapper()
        let up = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [0: 11]).event)
        XCTAssertEqual(up.getIntegerValueField(.keyboardEventKeycode), 0)
    }

    func testSwappedKeysAreMappedOnceAndTrackedIndependently() throws {
        var remapper = KeyRemapper()
        let first = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11, 11: 0]).event)
        let second = try XCTUnwrap(remapper.remap(event(11), mappings: [0: 11, 11: 0]).event)
        let firstUp = try XCTUnwrap(remapper.remap(event(0, down: false), mappings: [0: 11, 11: 0]).event)
        let secondUp = try XCTUnwrap(remapper.remap(event(11, down: false), mappings: [0: 11, 11: 0]).event)

        XCTAssertEqual(first.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(second.getIntegerValueField(.keyboardEventKeycode), 0)
        XCTAssertEqual(firstUp.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(secondUp.getIntegerValueField(.keyboardEventKeycode), 0)
    }

    func testResetReleasesOnlyMappedKeysAndOnlyOnce() throws {
        var remapper = KeyRemapper()
        _ = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 11]).event)
        _ = try XCTUnwrap(remapper.remap(event(8), mappings: [:]).event)
        XCTAssertEqual(remapper.reset(), [11])
        XCTAssertTrue(remapper.reset().isEmpty)
    }

    func testModifierKeysCannotBeRemappedInEitherDirection() throws {
        var remapper = KeyRemapper()
        let modifier = try XCTUnwrap(remapper.remap(event(55), mappings: [55: 11]).event)
        let ordinary = try XCTUnwrap(remapper.remap(event(0), mappings: [0: 55]).event)
        XCTAssertEqual(modifier.getIntegerValueField(.keyboardEventKeycode), 55)
        XCTAssertEqual(ordinary.getIntegerValueField(.keyboardEventKeycode), 0)
    }

    func testReplacingKeyRemovesOriginalExplicitUnicodeText() throws {
        var remapper = KeyRemapper()
        let original = try event(0)
        let unicode = Array("original text".utf16)
        original.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
        let remapped = try XCTUnwrap(remapper.remap(original, mappings: [0: 11]).event)

        let fresh = try event(11)
        fresh.flags = original.flags
        XCTAssertEqual(NSEvent(cgEvent: remapped)?.characters, NSEvent(cgEvent: fresh)?.characters)
    }

    func testCatalogContainsUniqueNonModifierKeysAndCommonSpecialKeys() {
        let codes = KeyCatalog.keys.map(\.id)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertFalse(codes.contains { ModifierKey.isModifierKeyCode($0) })
        for code in [kVK_ANSI_A, kVK_Return, kVK_Escape, kVK_Delete, kVK_LeftArrow, kVK_JIS_Kana] {
            XCTAssertTrue(codes.contains(CGKeyCode(code)))
        }
    }
}
