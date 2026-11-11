import AppKit
import XCTest
@testable import KeyDuty

final class ShortcutRecordingTests: XCTestCase {
    private func event(_ code: CGKeyCode = 0, type: CGEventType = .keyDown,
                       flags: CGEventFlags = [.maskCommand, .maskShift], repeatKey: Bool = false) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    func testRecordsCombinationOnOrdinaryKeyReleaseEvenIfModifiersReleasedFirst() throws {
        var state = ShortcutRecordingState()
        XCTAssertEqual(state.receive(try event(55, type: .flagsChanged, flags: .maskCommand)), .waiting)
        XCTAssertEqual(state.receive(try event()), .waiting)
        XCTAssertEqual(state.receive(try event(55, type: .flagsChanged, flags: [])), .waiting)
        XCTAssertEqual(state.receive(try event(type: .keyUp, flags: [])),
                       .selected(KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])))
    }

    func testNoModifierKeyIsRejectedButNextValidCombinationCanBeRecorded() throws {
        var state = ShortcutRecordingState()
        guard case .message = state.receive(try event(flags: [])) else { return XCTFail("説明が必要です") }
        XCTAssertEqual(state.receive(try event(type: .keyUp, flags: [])), .waiting)
        _ = state.receive(try event())
        XCTAssertEqual(state.receive(try event(type: .keyUp)),
                       .selected(KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])))
    }

    func testRepeatDoesNotRecordUntilReleaseAndStartupRepeatIsIgnored() throws {
        var state = ShortcutRecordingState()
        XCTAssertEqual(state.receive(try event(repeatKey: true)), .waiting)
        XCTAssertEqual(state.receive(try event(type: .keyUp)), .waiting)
        _ = state.receive(try event())
        XCTAssertEqual(state.receive(try event(repeatKey: true)), .waiting)
        XCTAssertEqual(state.receive(try event(type: .keyUp)),
                       .selected(KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])))
    }

    func testEscapeCancelsAloneButCanBePartOfShortcut() throws {
        var state = ShortcutRecordingState()
        XCTAssertEqual(state.receive(try event(53, flags: [])), .cancelled)
        XCTAssertEqual(state.receive(try event(53, flags: .maskControl)), .waiting)
        XCTAssertEqual(state.receive(try event(53, type: .keyUp, flags: .maskControl)),
                       .selected(KeyboardShortcut(keyCode: 53, modifiers: [.control])))
    }

    func testTwoOrdinaryKeysAreNotMistakenForOneShortcut() throws {
        var state = ShortcutRecordingState()
        _ = state.receive(try event())
        guard case .message = state.receive(try event(11)) else { return XCTFail("通常キーは1つに限定します") }
        XCTAssertEqual(state.receive(try event(11, type: .keyUp)), .waiting)
        XCTAssertEqual(state.receive(try event(type: .keyUp)), .waiting)
    }
}
