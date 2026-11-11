import CoreGraphics
import XCTest
@testable import KeyDuty

@MainActor
final class KeyboardEventSourceTests: XCTestCase {
    func testSenderIdentityPreservesAllBitsAndCachesSuccessfulLookup() throws {
        var lookedUp: [UInt64] = []
        let resolver = KeyboardEventSourceResolver { sender in
            lookedUp.append(sender)
            return "1234:5678"
        }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        let field = try XCTUnwrap(CGEventField(rawValue: 87))
        event.setIntegerValueField(field, value: Int64(bitPattern: UInt64.max - 1))
        let origin = resolver.origin(for: event)
        XCTAssertEqual(origin, KeyboardEventOrigin(senderID: UInt64.max - 1, keyboardID: "1234:5678"))
        XCTAssertEqual(resolver.origin(for: event), origin)
        XCTAssertEqual(lookedUp, [UInt64.max - 1])
        resolver.reset()
        XCTAssertEqual(resolver.origin(for: event), origin)
        XCTAssertEqual(lookedUp.count, 2)
    }

    func testMissingSenderIsUnknownWithoutRegistryLookup() throws {
        let resolver = KeyboardEventSourceResolver { _ in
            XCTFail("Missing sender must not query the registry")
            return nil
        }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: 0)
        XCTAssertEqual(resolver.origin(for: event), KeyboardEventOrigin(senderID: 0, keyboardID: nil))
    }

    func testFailedLookupDoesNotGuessAnotherKeyboard() throws {
        let resolver = KeyboardEventSourceResolver { _ in nil }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: 123)
        XCTAssertEqual(resolver.origin(for: event), KeyboardEventOrigin(senderID: 123, keyboardID: nil))
    }
}
