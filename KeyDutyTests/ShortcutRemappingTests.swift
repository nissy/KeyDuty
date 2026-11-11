import CoreGraphics
import XCTest
@testable import KeyDuty

final class ShortcutRemappingTests: XCTestCase {
    private let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])

    private func event(down: Bool = true, flags: CGEventFlags = [.maskCommand, .maskShift],
                       repeating: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down))
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        return event
    }

    func testShortcutWinsOverSingleKeyMappingAndFiresOnceOnRelease() throws {
        var remapper = KeyRemapper()
        let shortcuts: [KeyboardShortcut: KeyAction] = [shortcut: .system(.sleep)]
        for event in [try event(), try event(repeating: true), try event(repeating: true)] {
            let result = try remapper.remap(event, mappings: [0: 11], actions: [0: .mediaPlay], shortcuts: shortcuts)
            XCTAssertNil(result.event)
            XCTAssertNil(result.action)
        }
        let result = try remapper.remap(event(down: false), mappings: [0: 11], shortcuts: shortcuts)
        XCTAssertNil(result.event)
        XCTAssertEqual(result.action, .system(.sleep))
        let duplicate = try remapper.remap(event(down: false), mappings: [:], shortcuts: shortcuts)
        XCTAssertNil(duplicate.action)
        XCTAssertNotNil(duplicate.event)
    }

    func testMissingOrExtraModifiersDoNotMatchAndLeaveOtherShortcutsAlone() throws {
        let flags: [CGEventFlags] = [[], .maskCommand, .maskShift, [.maskCommand, .maskShift, .maskControl]]
        for flags in flags {
            var remapper = KeyRemapper()
            let original = try event(flags: flags)
            let result = try remapper.remap(original, mappings: [:], shortcuts: [shortcut: .system(.sleep)])
            XCTAssertTrue(result.event === original)
            XCTAssertNil(result.action)
        }
    }

    func testModifierReleaseOrderDoesNotLoseMatchedShortcut() throws {
        var remapper = KeyRemapper()
        _ = try remapper.remap(event(), mappings: [:], shortcuts: [shortcut: .system(.mediaPause)])
        let repeated = try remapper.remap(event(flags: [], repeating: true), mappings: [:],
                                         shortcuts: [shortcut: .system(.mediaPause)])
        let release = try remapper.remap(event(down: false, flags: []), mappings: [:],
                                        shortcuts: [shortcut: .system(.mediaPause)])
        XCTAssertNil(repeated.event)
        XCTAssertNil(repeated.action)
        XCTAssertEqual(release.action, .system(.mediaPause))
    }

    func testAddingModifierWhileKeyIsHeldDoesNotActivateShortcut() throws {
        var remapper = KeyRemapper()
        _ = try remapper.remap(event(flags: []), mappings: [0: 11])
        let repeated = try remapper.remap(event(repeating: true), mappings: [:], shortcuts: [shortcut: .system(.sleep)])
        let release = try remapper.remap(event(down: false), mappings: [:], shortcuts: [shortcut: .system(.sleep)])
        XCTAssertEqual(repeated.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(release.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertNil(release.action)
    }

    func testRemovingOrChangingShortcutWhileHeldCancelsItAndConsumesRelease() throws {
        let variants: [[KeyboardShortcut: KeyAction]] = [[:], [shortcut: .system(.mediaPause)]]
        for shortcuts in variants {
            var remapper = KeyRemapper()
            _ = try remapper.remap(event(), mappings: [:], shortcuts: [shortcut: .system(.sleep)])
            let release = try remapper.remap(event(down: false), mappings: [:], shortcuts: shortcuts)
            XCTAssertNil(release.event)
            XCTAssertNil(release.action)
        }
    }

    func testHeldBeforeStartupAndResetDoNotFireShortcuts() throws {
        var remapper = KeyRemapper()
        let shortcuts: [KeyboardShortcut: KeyAction] = [shortcut: .system(.sleep)]
        let repeated = try remapper.remap(event(repeating: true), mappings: [:], shortcuts: shortcuts)
        XCTAssertNotNil(repeated.event)
        XCTAssertNil(try remapper.remap(event(down: false), mappings: [:], shortcuts: shortcuts).action)
        _ = try remapper.remap(event(), mappings: [:], shortcuts: shortcuts)
        XCTAssertTrue(remapper.reset().isEmpty)
        XCTAssertNil(try remapper.remap(event(down: false), mappings: [:], shortcuts: shortcuts).action)
    }

    func testShortcutCanSendAKeyAsAOneShotAction() throws {
        var remapper = KeyRemapper()
        let shortcuts: [KeyboardShortcut: KeyAction] = [shortcut: .sendKey(keyCode: 0)]
        _ = try remapper.remap(event(), mappings: [:], shortcuts: shortcuts)
        let release = try remapper.remap(event(down: false), mappings: [:], shortcuts: shortcuts)
        XCTAssertNil(release.event)
        XCTAssertEqual(release.action, .sendKey(keyCode: 0))
    }
}
