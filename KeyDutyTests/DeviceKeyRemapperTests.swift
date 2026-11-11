import CoreGraphics
import XCTest
@testable import KeyDuty

final class DeviceKeyRemapperTests: XCTestCase {
    private let first = KeyboardEventOrigin(senderID: 1, keyboardID: "first")
    private let second = KeyboardEventOrigin(senderID: 2, keyboardID: "second")
    private let assignments = [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)]

    private func event(_ code: CGKeyCode, down: Bool, repeatKey: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return event
    }

    func testSharedDestinationIsReleasedOnlyAfterBothKeyboardsRelease() throws {
        var remapper = DeviceKeyRemapper()
        for origin in [first, second] {
            let output = try remapper.remap(
                event(0, down: true), assignments: assignments, origin: origin, modifiers: []
            )
            XCTAssertEqual(output.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        }
        let firstUp = try remapper.remap(
            event(0, down: false), assignments: assignments, origin: first, modifiers: []
        )
        XCTAssertNil(firstUp.event, "The second keyboard is still holding B")
        let secondUp = try remapper.remap(
            event(0, down: false), assignments: assignments, origin: second, modifiers: []
        )
        XCTAssertEqual(secondUp.event?.type, .keyUp)
        XCTAssertEqual(secondUp.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertTrue(remapper.reset().isEmpty)
    }

    func testMappedDestinationAndOriginalKeyShareHeldState() throws {
        var remapper = DeviceKeyRemapper()
        _ = try remapper.remap(event(0, down: true), assignments: assignments, origin: first, modifiers: [])
        _ = try remapper.remap(event(11, down: true), assignments: [], origin: second, modifiers: [])
        let mappedUp = try remapper.remap(
            event(0, down: false), assignments: assignments, origin: first, modifiers: []
        )
        XCTAssertNil(mappedUp.event)
        let originalUp = try event(11, down: false)
        XCTAssertTrue(try remapper.remap(
            originalUp, assignments: [], origin: second, modifiers: []
        ).event === originalUp)
    }

    func testResetDoesNotReleaseDestinationStillHeldAsOriginalKey() throws {
        var remapper = DeviceKeyRemapper()
        _ = try remapper.remap(event(0, down: true), assignments: assignments, origin: first, modifiers: [])
        _ = try remapper.remap(event(11, down: true), assignments: [], origin: second, modifiers: [])
        XCTAssertTrue(remapper.reset().isEmpty, "A real B remains pressed on the other keyboard")
    }

    func testRepeatsDoNotLeaveDestinationPressedAfterRelease() throws {
        var remapper = DeviceKeyRemapper()
        _ = try remapper.remap(event(0, down: true), assignments: assignments, origin: first, modifiers: [])
        for _ in 0..<3 {
            _ = try remapper.remap(
                event(0, down: true, repeatKey: true), assignments: assignments, origin: first, modifiers: []
            )
        }
        let output = try remapper.remap(
            event(0, down: false), assignments: assignments, origin: first, modifiers: []
        )
        XCTAssertEqual(output.event?.type, .keyUp)
        XCTAssertTrue(remapper.reset().isEmpty)
    }

    func testDifferentSourceKeysOnSameKeyboardShareDestination() throws {
        var remapper = DeviceKeyRemapper()
        let mappings = assignments + [KeyAssignment(sourceKeyCode: 1, destinationKeyCode: 11)]
        _ = try remapper.remap(event(0, down: true), assignments: mappings, origin: first, modifiers: [])
        _ = try remapper.remap(event(1, down: true), assignments: mappings, origin: first, modifiers: [])
        XCTAssertNil(try remapper.remap(
            event(0, down: false), assignments: mappings, origin: first, modifiers: []
        ).event)
        XCTAssertEqual(try remapper.remap(
            event(1, down: false), assignments: mappings, origin: first, modifiers: []
        ).event?.type, .keyUp)
    }

    func testOriginalKeyReleaseDoesNotReleaseMappedKeyStillHeld() throws {
        var remapper = DeviceKeyRemapper()
        _ = try remapper.remap(event(0, down: true), assignments: assignments, origin: first, modifiers: [])
        _ = try remapper.remap(event(11, down: true), assignments: [], origin: second, modifiers: [])
        XCTAssertNil(try remapper.remap(
            event(11, down: false), assignments: [], origin: second, modifiers: []
        ).event)
        XCTAssertEqual(remapper.reset(), [11])
    }

    func testOutOfRangeKeyCodePassesThroughWithoutTrapping() throws {
        var remapper = DeviceKeyRemapper()
        let input = try event(0, down: true)
        input.setIntegerValueField(.keyboardEventKeycode, value: Int64.max)
        XCTAssertTrue(try remapper.remap(input, assignments: assignments, origin: first, modifiers: []).event === input)
    }
}
