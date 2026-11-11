import CoreGraphics
import XCTest
@testable import KeyDuty

private final class RecordingEventPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []

    func post(_ request: KeyEventRequest, source: CGEventSource) throws {
        requests.append(request)
    }
}

@MainActor
final class KeyMonitorRemappingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "KeyMonitorRemappingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func event(_ keyCode: CGKeyCode, type: CGEventType, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        return event
    }

    func testNormalRemappingCancelsModifierTapAndPreservesShortcut() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments += [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)]
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )

        let commandDown = try event(55, type: .flagsChanged, flags: .maskCommand)
        let keyDown = try event(0, type: .keyDown, flags: .maskCommand)
        let keyUp = try event(0, type: .keyUp, flags: .maskCommand)
        let commandUp = try event(55, type: .flagsChanged)
        _ = monitor.handle(type: .flagsChanged, event: commandDown)
        let remappedDown = try XCTUnwrap(monitor.handle(type: .keyDown, event: keyDown))
        let remappedUp = try XCTUnwrap(monitor.handle(type: .keyUp, event: keyUp))
        _ = monitor.handle(type: .flagsChanged, event: commandUp)

        XCTAssertEqual(remappedDown.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(remappedUp.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(remappedDown.flags, .maskCommand)
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testModifierTapStillSendsOriginalActionAndOwnEventsBypassRemapping() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments += [KeyAssignment(sourceKeyCode: 102, destinationKeyCode: 11)]
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        for event in [
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(55, type: .flagsChanged)
        ] {
            _ = monitor.handle(type: event.type, event: event)
        }

        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [true, false])
        let ownEvent = try event(102, type: .keyDown)
        ownEvent.setIntegerValueField(.eventSourceUserData, value: sender.sessionToken)
        let output = try XCTUnwrap(monitor.handle(type: .keyDown, event: ownEvent))
        XCTAssertEqual(output.getIntegerValueField(.keyboardEventKeycode), 102)
    }

    func testResetAndStopReleaseHeldDestinationOnlyOnce() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments += [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)]
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        _ = monitor.handle(type: .keyDown, event: try event(0, type: .keyDown))

        monitor.resetState()
        monitor.stop()

        XCTAssertEqual(poster.requests, [
            KeyEventRequest(keyCode: 11, isKeyDown: false, userData: 123, preservesModifiers: true)
        ])
    }

    func testOneShotSendOfHeldRemappedKeyDoesNotReleaseIt() throws {
        // A→英数で保持中に、F13の押下側から英数を単発送信しても保持を解除しない。
        let preferences = Preferences(defaults: defaults)
        var split = KeyAssignment(sourceKeyCode: 105, action: .none)
        split.separatesPressAndRelease = true
        split.pressReleaseActions = PressReleaseActions(onPress: .eisu, onRelease: .kana)
        preferences.keyAssignments += [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 102), split]
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )

        let heldDown = try XCTUnwrap(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown)))
        XCTAssertEqual(heldDown.getIntegerValueField(.keyboardEventKeycode), 102)
        XCTAssertNil(monitor.handle(type: .keyDown, event: try event(105, type: .keyDown)))
        XCTAssertNil(monitor.handle(type: .keyUp, event: try event(105, type: .keyUp)))

        XCTAssertEqual(poster.requests, [
            KeyEventRequest(keyCode: 102, isKeyDown: true, userData: 123),
            KeyEventRequest(keyCode: 104, isKeyDown: true, userData: 123),
            KeyEventRequest(keyCode: 104, isKeyDown: false, userData: 123)
        ])

        let heldUp = try XCTUnwrap(monitor.handle(type: .keyUp, event: try event(0, type: .keyUp)))
        XCTAssertEqual(heldUp.getIntegerValueField(.keyboardEventKeycode), 102)
        XCTAssertEqual(heldUp.type, .keyUp)

        // 保持が終わった後の単発送信は、従来どおり押下と解放を送る。
        poster.requests.removeAll()
        _ = monitor.handle(type: .keyDown, event: try event(105, type: .keyDown))
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [true, false])
    }

    func testIdleSendOfHeldRemappedKeyDoesNotReleaseIt() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 102)]
        preferences.idleEnabled = true
        preferences.idleTimeoutSeconds = 5
        preferences.idleAction = .eisu
        var time: TimeInterval = 100
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }, now: { time }
        )

        _ = monitor.handle(type: .keyDown, event: try event(0, type: .keyDown))
        time = 105
        monitor.checkIdleTimeout()

        XCTAssertEqual(poster.requests, [KeyEventRequest(keyCode: 102, isKeyDown: true, userData: 123)])
        let heldUp = try XCTUnwrap(monitor.handle(type: .keyUp, event: try event(0, type: .keyUp)))
        XCTAssertEqual(heldUp.getIntegerValueField(.keyboardEventKeycode), 102)
        monitor.stop()
    }

    func testRecordingBypassesBothBehaviorsAndResumesAfterRecording() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        preferences.isRecordingKey = true
        let original = try event(0, type: .keyDown)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: original) === original)
        for event in [
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(55, type: .flagsChanged)
        ] {
            _ = monitor.handle(type: event.type, event: event)
        }
        XCTAssertTrue(poster.requests.isEmpty)

        preferences.isRecordingKey = false
        for event in [
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(55, type: .flagsChanged)
        ] {
            _ = monitor.handle(type: event.type, event: event)
        }
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
        let output = try XCTUnwrap(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown)))
        XCTAssertEqual(output.getIntegerValueField(.keyboardEventKeycode), 11)
    }

    func testStartingRecordingReleasesHeldRemappingImmediately() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        _ = monitor.handle(type: .keyDown, event: try event(0, type: .keyDown))

        preferences.isRecordingKey = true
        XCTAssertEqual(poster.requests.count, 1)
        XCTAssertEqual(poster.requests.first?.keyCode, 11)
        XCTAssertEqual(poster.requests.first?.isKeyDown, false)
        XCTAssertFalse(Preferences(defaults: defaults).isRecordingKey)
    }

    func testDisablingModifierWhileHeldDoesNotSendActionOnRelease() throws {
        let preferences = Preferences(defaults: defaults)
        let poster = RecordingEventPoster()
        let sender = try KeySender(poster: poster, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        _ = monitor.handle(type: .flagsChanged, event: try event(55, type: .flagsChanged, flags: .maskCommand))
        preferences.setEnabled(false, for: .leftCommand)
        _ = monitor.handle(type: .flagsChanged, event: try event(55, type: .flagsChanged))
        XCTAssertTrue(poster.requests.isEmpty)
    }
}
