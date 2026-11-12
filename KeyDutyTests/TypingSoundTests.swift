import AVFoundation
import CoreGraphics
import IOKit.hid
import XCTest
@testable import KeyDuty

private final class TypingSoundEventPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []

    func post(_ request: KeyEventRequest, source: CGEventSource) throws {
        requests.append(request)
    }
}

@MainActor
final class TypingSoundTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: Preferences!
    private var devices: KeyboardDeviceManager!

    override func setUp() async throws {
        suiteName = "TypingSoundTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = []
        devices = KeyboardDeviceManager()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSoundsPlayOnceForNewPressesAndFollowCurrentSelection() throws {
        var played: [(TypingSound, Bool)] = []
        let monitor = KeyMonitor(
            preferences: preferences,
            sender: try KeySender(sessionToken: 123),
            keyboardDeviceManager: devices,
            isSecureInputEnabled: { false },
            currentModifierFlags: { [] },
            onTypingSound: { played.append(($0, $1)) }
        )

        report(kHIDUsage_KeyboardA)
        report(kHIDUsage_KeyboardA, value: 0)
        XCTAssertTrue(played.isEmpty)

        preferences.typingSoundEnabled = true
        preferences.typingSound = .piko
        report(kHIDUsage_KeyboardA)
        report(kHIDUsage_KeyboardA)
        report(kHIDUsage_KeyboardA, value: 0)

        let generated = try key(49)
        generated.setIntegerValueField(.eventSourceUserData, value: 123)
        deliver(generated, to: monitor)

        preferences.typingSound = .poko
        report(kHIDUsage_KeyboardSpacebar)
        report(kHIDUsage_KeyboardReturnOrEnter)
        preferences.typingSoundEnabled = false
        report(kHIDUsage_KeyboardB)

        XCTAssertEqual(played.map(\.0), [.piko, .poko, .poko])
        XCTAssertEqual(played.map(\.1), [false, true, true])
    }

    func testAssignedModifierSoundsOnlyWhenPressed() throws {
        preferences.typingSoundEnabled = true
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102)]
        let poster = TypingSoundEventPoster()
        var plays = 0
        let monitor = KeyMonitor(
            preferences: preferences,
            sender: try KeySender(poster: poster, canPostEvents: { true }),
            keyboardDeviceManager: devices,
            isSecureInputEnabled: { false },
            currentModifierFlags: { [] },
            onTypingSound: { _, _ in plays += 1 }
        )

        report(kHIDUsage_KeyboardLeftGUI)
        let press = try key(55)
        press.type = .flagsChanged
        press.flags = .maskCommand
        deliver(press, to: monitor)
        XCTAssertEqual(plays, 1)
        XCTAssertTrue(poster.requests.isEmpty)

        report(kHIDUsage_KeyboardLeftGUI, value: 0)
        let release = try key(55, down: false)
        release.type = .flagsChanged
        release.flags = []
        deliver(release, to: monitor)
        XCTAssertEqual(plays, 1)
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])

        // The assignment output must remain silent even without a source PID or session tag.
        for request in poster.requests {
            let output = try key(request.keyCode, down: request.isKeyDown)
            deliver(output, to: monitor)
        }
        XCTAssertEqual(plays, 1)

        report(kHIDUsage_KeyboardLeftGUI)
        XCTAssertEqual(plays, 2)
    }

    func testLanguageTapFromCommandReleaseStaysSilent() throws {
        preferences.typingSoundEnabled = true
        var plays = 0
        let monitor = KeyMonitor(
            preferences: preferences,
            sender: try KeySender(),
            keyboardDeviceManager: devices,
            isSecureInputEnabled: { false },
            currentModifierFlags: { [] },
            onTypingSound: { _, _ in plays += 1 }
        )

        report(kHIDUsage_KeyboardLeftGUI, at: 10)
        report(kHIDUsage_KeyboardA, at: 10.5)
        report(kHIDUsage_KeyboardLeftGUI, value: 0, at: 11)
        report(kHIDUsage_KeyboardLANG2, at: 11.001)
        report(kHIDUsage_KeyboardLANG2, value: 0, at: 11.002)
        XCTAssertEqual(plays, 2)

        report(kHIDUsage_KeyboardRightGUI, at: 12)
        report(kHIDUsage_KeyboardRightGUI, value: 0, at: 13)
        report(kHIDUsage_KeyboardLANG1, at: 13.001, deviceID: ObjectIdentifier(devices))
        report(kHIDUsage_KeyboardLANG1, at: 13.002)
        report(kHIDUsage_KeyboardLANG1, value: 0, at: 13.003)
        XCTAssertEqual(plays, 4)

        report(kHIDUsage_KeyboardLANG1, at: 13.5)
        XCTAssertEqual(plays, 5)
        withExtendedLifetime(monitor) {}
    }

    func testSoundsStaySilentDuringSecureInputAndKeyRecording() throws {
        preferences.typingSoundEnabled = true
        var plays = 0
        var secureInput = true
        let monitor = KeyMonitor(
            preferences: preferences,
            sender: try KeySender(),
            keyboardDeviceManager: devices,
            isSecureInputEnabled: { secureInput },
            currentModifierFlags: { [] },
            onTypingSound: { _, _ in plays += 1 }
        )

        report(kHIDUsage_KeyboardA)
        secureInput = false
        preferences.isRecordingKey = true
        report(kHIDUsage_KeyboardB)
        XCTAssertEqual(plays, 0)
        withExtendedLifetime(monitor) {}
    }

    func testSavedSelectionAndAllBundledSounds() throws {
        XCTAssertFalse(preferences.typingSoundEnabled)
        XCTAssertEqual(preferences.typingSound, .kacha)
        XCTAssertEqual(preferences.typingSoundVolume, 0.5)
        preferences.typingSoundEnabled = true
        preferences.typingSound = .kira
        preferences.typingSoundVolume = 0.25
        let restored = Preferences(defaults: defaults)
        XCTAssertTrue(restored.typingSoundEnabled)
        XCTAssertEqual(restored.typingSound, .kira)
        XCTAssertEqual(restored.typingSoundVolume, 0.25)

        for sound in TypingSound.allCases {
            for deep in [false, true] {
                let url = try XCTUnwrap(sound.resourceURL(deep: deep))
                let player = try AVAudioPlayer(contentsOf: url)
                XCTAssertGreaterThan(player.duration, 0)
                XCTAssertLessThan(player.duration, 0.1)
            }
        }
    }

    private func report(_ usage: Int, value: Int = 1, at timestamp: TimeInterval = 10,
                        deviceID: ObjectIdentifier? = nil) {
        devices.receiveKeyInput(usagePage: kHIDPage_KeyboardOrKeypad, usage: usage, value: value,
                                deviceID: deviceID ?? ObjectIdentifier(self), timestamp: timestamp)
    }

    private func key(_ code: CGKeyCode, down: Bool = true) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        return event
    }

    private func deliver(_ event: CGEvent, to monitor: KeyMonitor) {
        _ = monitor.handle(type: event.type, event: event)
    }
}
