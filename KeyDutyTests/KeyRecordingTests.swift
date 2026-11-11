import AppKit
import XCTest
@testable import KeyDuty

final class KeyRecordingTests: XCTestCase {
    private func event(_ code: CGKeyCode, type: CGEventType, flags: CGEventFlags = []) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type == .keyDown))
        event.type = type
        event.flags = flags
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    func testOrdinaryKeyIsSelectedOnRelease() throws {
        var state = KeyRecordingState(allowsModifiers: false)
        XCTAssertEqual(state.receive(try event(0, type: .keyDown)), .waiting)
        XCTAssertEqual(state.receive(try event(0, type: .keyUp)), .selected(0))
    }

    func testLeftAndRightModifiersAreRecordedSeparatelyOnRelease() throws {
        for key in ModifierKey.allCases {
            var state = KeyRecordingState(allowsModifiers: true)
            XCTAssertEqual(state.receive(try event(key.keyCode, type: .flagsChanged, flags: key.flagMask)), .waiting)
            XCTAssertEqual(state.receive(try event(key.keyCode, type: .flagsChanged)), .selected(key.keyCode))
        }
    }

    func testDestinationRejectsModifiersButAcceptsNextOrdinaryKey() throws {
        var state = KeyRecordingState(allowsModifiers: false)
        let result = state.receive(try event(55, type: .flagsChanged, flags: .maskCommand))
        guard case .message = result else { return XCTFail("修飾キーを拒否する説明が必要です") }
        _ = state.receive(try event(55, type: .flagsChanged))
        _ = state.receive(try event(49, type: .keyDown))
        XCTAssertEqual(state.receive(try event(49, type: .keyUp)), .selected(49))
    }

    func testShortcutIsNotMistakenForSingleKey() throws {
        var state = KeyRecordingState(allowsModifiers: true)
        _ = state.receive(try event(55, type: .flagsChanged, flags: .maskCommand))
        let result = state.receive(try event(12, type: .keyDown, flags: .maskCommand))
        guard case .message = result else { return XCTFail("組み合わせは選択できません") }
        XCTAssertEqual(state.receive(try event(12, type: .keyUp, flags: .maskCommand)), .waiting)
        XCTAssertEqual(state.receive(try event(55, type: .flagsChanged)), .waiting)
    }

    func testEscapeCancelsRecording() throws {
        var state = KeyRecordingState(allowsModifiers: true)
        XCTAssertEqual(state.receive(try event(53, type: .keyDown)), .cancelled)
    }
}
