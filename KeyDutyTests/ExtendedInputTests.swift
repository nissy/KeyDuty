import AppKit
import Carbon
import XCTest
@testable import KeyDuty

private final class ExtendedInputPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []
    func post(_ request: KeyEventRequest, source: CGEventSource) throws { requests.append(request) }
}

@MainActor
private final class ExtendedInputExecutor: SystemActionExecuting {
    var actions: [SystemAction] = []
    var onExecute: (() -> Void)?
    func execute(_ action: SystemAction) async throws {
        actions.append(action)
        onExecute?()
    }
}

@MainActor
final class ExtendedInputTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ExtendedInputTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suiteName) }

    private func key(_ code: CGKeyCode, _ type: CGEventType, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        return event
    }

    private func special(_ rawKey: Int, down: Bool, repeatKey: Bool = false,
                         flags: CGEventFlags = [], subtype: Int16 = 8) throws -> CGEvent {
        let data = (rawKey << 16) | ((down ? 0x0a : 0x0b) << 8) | (repeatKey ? 1 : 0)
        let event = try XCTUnwrap(NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: UInt(flags.rawValue)),
            timestamp: 0, windowNumber: 0, context: nil, subtype: subtype, data1: data, data2: -1
        )?.cgEvent)
        return event
    }

    func testAllSystemKeysPreserveOriginalEventsWhenUnassignedAndRemapCompletePresses() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = []
        let monitor = KeyMonitor(preferences: preferences, sender: try KeySender(canPostEvents: { false }),
                                 isSecureInputEnabled: { false }, currentModifierFlags: { [] })
        for systemKey in SystemKey.allCases {
            for down in [true, false] {
                let original = try special(systemKey.rawValue, down: down)
                XCTAssertTrue(monitor.handle(type: original.type, event: original) === original)
            }
            preferences.keyAssignments = [KeyAssignment(sourceKeyCode: systemKey.keyCode, destinationKeyCode: 0)]
            for (down, repeated) in [(true, false), (true, true), (false, false)] {
                let original = try special(systemKey.rawValue, down: down, repeatKey: repeated, flags: .maskShift)
                let output = try XCTUnwrap(monitor.handle(type: original.type, event: original))
                XCTAssertEqual(output.type, down ? .keyDown : .keyUp)
                XCTAssertEqual(output.getIntegerValueField(.keyboardEventKeycode), 0)
                XCTAssertEqual(output.getIntegerValueField(.keyboardEventAutorepeat), repeated ? 1 : 0)
                XCTAssertEqual(output.flags, .maskShift)
                XCTAssertEqual(original.type, SystemKeyInput.eventType)
            }
            preferences.keyAssignments = []
        }
        for event in [try special(255, down: true), try special(0, down: true, subtype: 7)] {
            XCTAssertTrue(monitor.handle(type: event.type, event: event) === event)
        }
    }

    func testSpecialKeyActionRunsOnceOnReleaseAndChangedAssignmentCancelsIt() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 72, action: .system(.mediaPause))]
        let executor = ExtendedInputExecutor()
        let executed = expectation(description: "One media action")
        executor.onExecute = { executed.fulfill() }
        let monitor = KeyMonitor(preferences: preferences, sender: try KeySender(canPostEvents: { false }),
                                 actionExecutor: executor, isSecureInputEnabled: { false },
                                 currentModifierFlags: { [] })
        let presses = [try special(0, down: true), try special(0, down: true, repeatKey: true)]
        for event in presses {
            XCTAssertNil(monitor.handle(type: event.type, event: event))
        }
        XCTAssertTrue(executor.actions.isEmpty)
        let release = try special(0, down: false)
        XCTAssertNil(monitor.handle(type: release.type, event: release))
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPause])
        _ = monitor.handle(type: SystemKeyInput.eventType, event: try special(0, down: true))
        preferences.keyAssignments[0].action = .system(.sleep)
        XCTAssertNil(monitor.handle(type: release.type, event: release))
        await Task.yield()
        XCTAssertEqual(executor.actions, [.mediaPause])
    }

    func testSpecialShortcutUsesModifiersAtPressAndSurvivesEarlierModifierRelease() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: SystemKey.playPause.keyCode,
                                                     destinationKeyCode: 0, sourceModifiers: [.command])]
        let poster = ExtendedInputPoster()
        let monitor = KeyMonitor(preferences: preferences,
                                 sender: try KeySender(poster: poster, canPostEvents: { true }),
                                 isSecureInputEnabled: { false }, currentModifierFlags: { [] })
        let press = try special(16, down: true, flags: .maskCommand)
        XCTAssertNil(monitor.handle(type: press.type, event: press))
        _ = monitor.handle(type: .flagsChanged, event: try key(55, .flagsChanged))
        let release = try special(16, down: false)
        XCTAssertNil(monitor.handle(type: release.type, event: release))
        XCTAssertEqual(poster.requests.map(\.keyCode), [0, 0])
    }

    func testFnTapAndFnShortcutDoNotFireEachOtherOrTreatArrowAsFn() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [
            KeyAssignment(sourceKeyCode: 63, destinationKeyCode: 102),
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 104, sourceModifiers: [.function]),
            KeyAssignment(sourceKeyCode: 123, destinationKeyCode: 104, sourceModifiers: [.function]),
            KeyAssignment(sourceKeyCode: 55, destinationKeyCode: 102)
        ]
        let poster = ExtendedInputPoster()
        let monitor = KeyMonitor(preferences: preferences,
                                 sender: try KeySender(poster: poster, canPostEvents: { true }),
                                 isSecureInputEnabled: { false }, currentModifierFlags: { [] })
        XCTAssertNil(monitor.handle(type: .flagsChanged, event: try key(63, .flagsChanged, flags: .maskSecondaryFn)))
        XCTAssertNil(monitor.handle(type: .flagsChanged, event: try key(63, .flagsChanged)))
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
        poster.requests = []
        _ = monitor.handle(type: .flagsChanged, event: try key(63, .flagsChanged, flags: .maskSecondaryFn))
        XCTAssertNil(monitor.handle(type: .keyDown, event: try key(0, .keyDown, flags: .maskSecondaryFn)))
        _ = monitor.handle(type: .flagsChanged, event: try key(63, .flagsChanged))
        XCTAssertNil(monitor.handle(type: .keyUp, event: try key(0, .keyUp)))
        XCTAssertEqual(poster.requests.map(\.keyCode), [104, 104])
        poster.requests = []
        for type in [CGEventType.keyDown, .keyUp] {
            let arrow = try key(123, type, flags: [.maskSecondaryFn, .maskNumericPad])
            XCTAssertTrue(monitor.handle(type: type, event: arrow) === arrow)
        }
        for event in [try key(55, .flagsChanged, flags: .maskCommand),
                      try key(63, .flagsChanged, flags: [.maskCommand, .maskSecondaryFn]),
                      try key(63, .flagsChanged, flags: .maskCommand), try key(55, .flagsChanged)] {
            _ = monitor.handle(type: event.type, event: event)
        }
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testCapsLockRunsOnEachToggleWithoutDependingOnPhysicalKeyUp() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 57, destinationKeyCode: 102)]
        XCTAssertTrue(preferences.keyAssignments[0].isValid)
        let poster = ExtendedInputPoster()
        var secureInput = false
        let monitor = KeyMonitor(preferences: preferences,
                                 sender: try KeySender(poster: poster, canPostEvents: { true }),
                                 isSecureInputEnabled: { secureInput }, currentModifierFlags: { [] })
        for flags: CGEventFlags in [.maskAlphaShift, .maskAlphaShift, [], []] {
            let event = try key(57, .flagsChanged, flags: flags)
            XCTAssertTrue(monitor.handle(type: event.type, event: event) === event)
        }
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102, 102, 102])
        secureInput = true
        _ = monitor.handle(type: .flagsChanged, event: try key(57, .flagsChanged, flags: .maskAlphaShift))
        secureInput = false
        _ = monitor.handle(type: .flagsChanged, event: try key(57, .flagsChanged, flags: .maskAlphaShift))
        XCTAssertEqual(poster.requests.count, 4)
    }

    func testRecordersAcceptSystemKeysAndFnButKeepInputOnlyKeysOutOfDestinations() throws {
        for systemKey in SystemKey.allCases {
            var state = KeyRecordingState(allowsModifiers: true, includesSystemKeys: true)
            let down = try XCTUnwrap(NSEvent(cgEvent: special(systemKey.rawValue, down: true)))
            let up = try XCTUnwrap(NSEvent(cgEvent: special(systemKey.rawValue, down: false)))
            XCTAssertEqual(state.receive(down), .waiting)
            XCTAssertEqual(state.receive(up), .selected(systemKey.keyCode))
            var destination = KeyRecordingState(allowsModifiers: false)
            guard case .message = destination.receive(down) else { return XCTFail("Input only") }
        }
        var state = ShortcutRecordingState()
        _ = state.receive(try XCTUnwrap(NSEvent(cgEvent: key(63, .flagsChanged, flags: .maskSecondaryFn))))
        _ = state.receive(try XCTUnwrap(NSEvent(cgEvent: special(16, down: true, flags: .maskSecondaryFn))))
        _ = state.receive(try XCTUnwrap(NSEvent(cgEvent: key(63, .flagsChanged))))
        XCTAssertEqual(state.receive(try XCTUnwrap(NSEvent(cgEvent: special(16, down: false)))),
                       .selected(KeyboardShortcut(keyCode: SystemKey.playPause.keyCode, modifiers: [.function])))
        var single = KeyRecordingState(allowsModifiers: true)
        _ = single.receive(try XCTUnwrap(NSEvent(cgEvent: key(63, .flagsChanged, flags: .maskSecondaryFn))))
        guard case .message = single.receive(try XCTUnwrap(NSEvent(cgEvent: key(0, .keyDown)))) else {
            return XCTFail("Fn + key must not be recorded as a single key")
        }
        XCTAssertEqual(single.receive(try XCTUnwrap(NSEvent(cgEvent: key(63, .flagsChanged)))), .waiting)
    }

    func testNewInputsPersistAndCatalogHasUniqueIDsAndSearchableNames() {
        let preferences = Preferences(defaults: defaults)
        let codes = [CGKeyCode(57), 63] + SystemKey.allCases.map(\.keyCode)
        preferences.keyAssignments = codes.map { KeyAssignment(sourceKeyCode: $0, action: .system(.mediaPause)) }
        XCTAssertTrue(preferences.keyAssignments.allSatisfy(\.isValid))
        XCTAssertEqual(Preferences(defaults: defaults).keyAssignments, preferences.keyAssignments)
        let inputs = KeyCatalog.inputGroups.flatMap(\.keys)
        XCTAssertEqual(inputs.count, Set(inputs.map(\.id)).count)
        for code in codes { XCTAssertTrue(inputs.contains { $0.id == code }) }
        XCTAssertTrue(inputs.contains { $0.id == 71 && $0.matches("NumLock") })
        XCTAssertTrue(inputs.contains { $0.id == 63 && $0.matches("地球儀") })
        for key in SystemKey.allCases {
            XCTAssertFalse(KeyAction.sendKey(keyCode: key.keyCode).isValid)
            XCTAssertFalse(KeyCatalog.keys.contains { $0.id == key.keyCode })
        }
    }

    func testSystemKeyRecordingUsesTapWithoutExecutingAssignmentOrChangingSystemVolume() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 72, action: .system(.sleep))]
        let poster = ExtendedInputPoster()
        let executor = ExtendedInputExecutor()
        let monitor = KeyMonitor(preferences: preferences,
                                 sender: try KeySender(poster: poster, canPostEvents: { true }),
                                 actionExecutor: executor, isSecureInputEnabled: { false },
                                 currentModifierFlags: { [] })
        let recorder = KeyRecorder()
        var selected: CGKeyCode?
        recorder.start(preferences: preferences, allowsModifiers: true, includesSystemKeys: true) { selected = $0 }
        defer { recorder.stop() }
        for down in [true, false] {
            let event = try special(0, down: down)
            XCTAssertNil(monitor.handle(type: event.type, event: event))
        }
        XCTAssertEqual(selected, 72)
        XCTAssertFalse(preferences.isRecordingKey)
        XCTAssertNil(preferences.recordingHandler)
        XCTAssertTrue(executor.actions.isEmpty)
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testResetReleasesHeldRemappedSystemKeyAndDoesNotFireHeldFnTap() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 72, destinationKeyCode: 49),
                                      KeyAssignment(sourceKeyCode: 63, destinationKeyCode: 102)]
        let poster = ExtendedInputPoster()
        let monitor = KeyMonitor(preferences: preferences,
                                 sender: try KeySender(poster: poster, canPostEvents: { true }),
                                 isSecureInputEnabled: { false }, currentModifierFlags: { .maskSecondaryFn })
        _ = monitor.handle(type: SystemKeyInput.eventType, event: try special(0, down: true))
        monitor.resetState()
        XCTAssertEqual(poster.requests.map(\.keyCode), [49])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [false])
        let release = try special(0, down: false)
        XCTAssertTrue(monitor.handle(type: release.type, event: release) === release)
        _ = monitor.handle(type: .flagsChanged, event: try key(63, .flagsChanged))
        XCTAssertEqual(poster.requests.count, 1)
    }
}
