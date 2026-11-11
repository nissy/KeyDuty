import AppKit
import IOKit.hidsystem
import XCTest
@testable import KeyDuty

private final class IdleEventPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []
    func post(_ request: KeyEventRequest, source: CGEventSource) throws { requests.append(request) }
}

@MainActor
final class IdleKeySendingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: Preferences!
    private var poster: IdleEventPoster!
    private var monitor: KeyMonitor!
    private var time: TimeInterval = 100

    override func setUp() async throws {
        suiteName = "IdleKeySendingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = []
        preferences.idleEnabled = true
        preferences.idleTimeoutSeconds = 5
        poster = IdleEventPoster()
        monitor = KeyMonitor(
            preferences: preferences,
            sender: try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true }),
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            now: { [unowned self] in time }
        )
    }

    override func tearDown() async throws {
        monitor.stop()
        monitor = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func key(_ code: CGKeyCode = 0, _ type: CGEventType = .keyDown,
                     flags: CGEventFlags = [], repeatKey: Bool = false, senderID: Int64 = 10) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: senderID)
        return event
    }

    private func deliver(_ event: CGEvent) {
        _ = monitor.handle(type: event.type, event: event)
    }

    private func check(at time: TimeInterval, taps: Int, file: StaticString = #filePath, line: UInt = #line) {
        self.time = time
        monitor.checkIdleTimeout()
        XCTAssertEqual(poster.requests.count, taps * 2, file: file, line: line)
        XCTAssertEqual(poster.requests.map(\.keyCode), Array(repeating: 102, count: taps * 2),
                       file: file, line: line)
    }

    func testStartupReleaseAndMouseEventsDoNotArmSending() throws {
        check(at: 200, taps: 0)
        for type: CGEventType in [.keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] {
            deliver(try key(0, type))
        }
        deliver(try key(55, .flagsChanged))
        deliver(try key(repeatKey: true))
        check(at: 300, taps: 0)
        deliver(try key())
        check(at: 304.9, taps: 0)
        check(at: 305, taps: 1)
    }

    func testReleaseMouseAndRepeatsDoNotDelayOrRearmSending() throws {
        deliver(try key())
        time = 104
        for type: CGEventType in [.keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] {
            deliver(try key(0, type))
        }
        deliver(try key(repeatKey: true))
        check(at: 105, taps: 1)
        time = 106
        deliver(try key(0, .keyUp))
        deliver(try key(0, .scrollWheel))
        deliver(try key(repeatKey: true))
        check(at: 200, taps: 1)
    }

    func testNewPressResetsDeadlineAndRearmsOneShot() throws {
        deliver(try key())
        time = 104
        deliver(try key(11))
        check(at: 105, taps: 0)
        check(at: 109, taps: 1)
        check(at: 200, taps: 1)
        deliver(try key())
        check(at: 204.9, taps: 1)
        check(at: 205, taps: 2)
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [true, false, true, false])
    }

    func testGeneratedKeysDoNotArmOrResetTimer() throws {
        let own = try key()
        own.setIntegerValueField(.eventSourceUserData, value: 123)
        deliver(own)
        check(at: 200, taps: 0)
        deliver(try key())
        time = 204
        deliver(own)
        check(at: 205, taps: 1)
        deliver(own)
        check(at: 300, taps: 1)
    }

    func testModifierPressesCountButReleasesWithOppositeSideHeldDoNot() throws {
        let left = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK))
        let both = CGEventFlags(rawValue: left.rawValue | UInt64(NX_DEVICERCMDKEYMASK))
        deliver(try key(55, .flagsChanged, flags: left))
        time = 104
        deliver(try key(54, .flagsChanged, flags: both))
        check(at: 105, taps: 0)
        time = 108
        deliver(try key(54, .flagsChanged, flags: left))
        check(at: 109, taps: 1)
        deliver(try key(55, .flagsChanged))
        check(at: 200, taps: 1)
    }

    func testSameModifierOnDifferentKeyboardsCountsEachPressOnly() throws {
        deliver(try key(55, .flagsChanged, flags: .maskCommand, senderID: 10))
        time = 104
        deliver(try key(55, .flagsChanged, flags: .maskCommand, senderID: 20))
        time = 108
        deliver(try key(55, .flagsChanged, flags: .maskCommand, senderID: 10))
        check(at: 109, taps: 1)
        deliver(try key(55, .flagsChanged, senderID: 20))
        check(at: 200, taps: 1)
    }

    func testFnAndBothCapsLockTogglesCountAsPresses() throws {
        deliver(try key(63, .flagsChanged, flags: .maskSecondaryFn))
        time = 104
        deliver(try key(63, .flagsChanged))
        check(at: 105, taps: 1)
        time = 110
        deliver(try key(57, .flagsChanged, flags: .maskAlphaShift))
        time = 114
        deliver(try key(57, .flagsChanged, flags: .maskAlphaShift))
        check(at: 115, taps: 2)
        time = 120
        deliver(try key(57, .flagsChanged))
        check(at: 125, taps: 3)
    }

    private func media(down: Bool, repeatKey: Bool = false) throws -> CGEvent {
        let data = (SystemKey.volumeUp.rawValue << 16) | ((down ? 0x0a : 0x0b) << 8) | (repeatKey ? 1 : 0)
        return try XCTUnwrap(NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1
        )?.cgEvent)
    }

    func testMediaPressCountsButRepeatAndReleaseDoNot() throws {
        deliver(try media(down: false))
        check(at: 200, taps: 0)
        deliver(try media(down: true))
        time = 204
        deliver(try media(down: true, repeatKey: true))
        deliver(try media(down: false))
        check(at: 205, taps: 1)
    }

    func testStopDisarmsUntilAnotherPress() throws {
        deliver(try key())
        monitor.stop()
        check(at: 200, taps: 0)
    }

    func testSleepAndWakeRequireFreshKeyPress() throws {
        deliver(try key())
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        check(at: 200, taps: 0)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        check(at: 300, taps: 0)
        deliver(try key())
        check(at: 305, taps: 1)
    }

    func testDisabledAutoSendDoesNotPost() throws {
        preferences.idleEnabled = false
        deliver(try key())
        check(at: 200, taps: 0)
    }
}
