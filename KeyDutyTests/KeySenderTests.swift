import CoreGraphics
import XCTest
@testable import KeyDuty

final class KeySenderTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case postFailed
    }

    private final class MockPoster: KeyEventPosting {
        var requests: [KeyEventRequest] = []
        var sources: [CGEventSource] = []

        func post(_ request: KeyEventRequest, source: CGEventSource) throws {
            requests.append(request)
            sources.append(source)
        }
    }

    private final class FailingPoster: KeyEventPosting {
        private(set) var callCount = 0

        func post(_ request: KeyEventRequest, source: CGEventSource) throws {
            callCount += 1
            throw TestError.postFailed
        }
    }

    func testSendPostsKeyDownThenKeyUpWithSessionToken() throws {
        let poster = MockPoster()
        let sender = try KeySender(
            poster: poster,
            sessionToken: 123,
            canPostEvents: { true }
        )

        try sender.send(.kana)

        XCTAssertEqual(
            poster.requests,
            [
                KeyEventRequest(keyCode: 104, isKeyDown: true, userData: 123),
                KeyEventRequest(keyCode: 104, isKeyDown: false, userData: 123)
            ]
        )
    }

    func testSendOfHeldKeyPostsOnlyKeyDown() throws {
        let poster = MockPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        sender.heldKeyCodes = [104]

        try sender.send(.kana)
        try sender.send(.eisu)

        XCTAssertEqual(
            poster.requests,
            [
                KeyEventRequest(keyCode: 104, isKeyDown: true, userData: 123),
                KeyEventRequest(keyCode: 102, isKeyDown: true, userData: 123),
                KeyEventRequest(keyCode: 102, isKeyDown: false, userData: 123)
            ]
        )
    }

    func testSendUsesSourceFromTriggeringEvent() throws {
        let poster = MockPoster()
        let fallbackSource = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        let triggeringSource = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let triggeringEvent = try XCTUnwrap(
            CGEvent(keyboardEventSource: triggeringSource, virtualKey: 55, keyDown: false)
        )
        let sender = try KeySender(
            poster: poster,
            fallbackSource: fallbackSource,
            canPostEvents: { true }
        )

        try sender.send(.kana, triggeringEvent: triggeringEvent)

        XCTAssertEqual(poster.sources.count, 2)
        XCTAssertEqual(poster.sources[0].sourceStateID, triggeringSource.sourceStateID)
        XCTAssertEqual(poster.sources[1].sourceStateID, triggeringSource.sourceStateID)
    }

    func testSendWithoutTriggeringEventUsesCombinedSessionSource() throws {
        let poster = MockPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })

        try sender.send(.kana)

        XCTAssertEqual(poster.sources.count, 2)
        XCTAssertEqual(poster.sources[0].sourceStateID, .combinedSessionState)
        XCTAssertEqual(poster.sources[1].sourceStateID, .combinedSessionState)
    }

    func testNoneDoesNotPost() throws {
        let poster = MockPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })

        try sender.send(.none)

        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testModifierKeyIsRejected() throws {
        let poster = MockPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })

        XCTAssertThrowsError(try sender.send(keyCode: ModifierKey.rightCommand.keyCode)) { error in
            XCTAssertEqual(error as? KeySenderError, .modifierKeyNotAllowed(ModifierKey.rightCommand.keyCode))
        }
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testPostAccessDeniedDoesNotPost() throws {
        let poster = MockPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { false })

        XCTAssertThrowsError(try sender.send(.kana)) { error in
            XCTAssertEqual(error as? KeySenderError, .postAccessDenied)
        }
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testOwnEventMatchesSessionToken() throws {
        let sender = try KeySender(sessionToken: 123, canPostEvents: { true })
        let metadata = KeySender.EventMetadata(userData: 123)

        XCTAssertTrue(sender.isOwnEvent(metadata))
    }

    func testForeignEventIsNotMatched() throws {
        let sender = try KeySender(sessionToken: 123, canPostEvents: { true })
        let metadata = KeySender.EventMetadata(userData: 999)

        XCTAssertFalse(sender.isOwnEvent(metadata))
    }

    func testCGEventIsMatchedUsingSessionToken() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        let ownEvent = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 104, keyDown: true))
        let foreignEvent = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 104, keyDown: true))
        let sender = try KeySender(sessionToken: 123, canPostEvents: { true })

        ownEvent.setIntegerValueField(.eventSourceUserData, value: 123)
        foreignEvent.setIntegerValueField(.eventSourceUserData, value: 999)

        XCTAssertTrue(sender.isOwnEvent(ownEvent))
        XCTAssertFalse(sender.isOwnEvent(foreignEvent))
    }

    func testNoneDoesNotCheckPostAccess() throws {
        let poster = MockPoster()
        var accessCheckCount = 0
        let sender = try KeySender(
            poster: poster,
            canPostEvents: {
                accessCheckCount += 1
                return false
            }
        )

        try sender.send(.none)

        XCTAssertEqual(accessCheckCount, 0)
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testPostFailureIsPropagatedWithoutPostingKeyUp() throws {
        let poster = FailingPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })

        XCTAssertThrowsError(try sender.send(.kana)) { error in
            XCTAssertEqual(error as? TestError, .postFailed)
        }
        XCTAssertEqual(poster.callCount, 1)
    }
}
