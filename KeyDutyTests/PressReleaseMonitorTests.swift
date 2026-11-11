import AppKit
import XCTest
@testable import KeyDuty

private final class PressReleasePoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []
    func post(_ request: KeyEventRequest, source: CGEventSource) throws { requests.append(request) }
}

@MainActor
private final class PressReleaseExecutor: SystemActionExecuting {
    var actions: [SystemAction] = []
    var holdPlay = false
    var continuation: CheckedContinuation<Void, Never>?
    var onExecute: ((SystemAction) -> Void)?

    func execute(_ action: SystemAction) async throws {
        actions.append(action)
        if action == .mediaPlay, holdPlay {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onExecute?(action)
            }
        } else {
            onExecute?(action)
        }
    }
}

@MainActor
final class PressReleaseMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var preferences: Preferences!
    private var poster: PressReleasePoster!
    private var executor: PressReleaseExecutor!
    private var deviceManager: KeyboardDeviceManager!
    private var monitor: KeyMonitor!
    private var secureInput = false

    override func setUp() async throws {
        suite = "PressReleaseMonitorTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        poster = PressReleasePoster()
        executor = PressReleaseExecutor()
        deviceManager = KeyboardDeviceManager(sourceResolver: KeyboardEventSourceResolver {
            $0 == 1 ? "included" : "excluded"
        })
        monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(poster: poster, canPostEvents: { true }),
            actionExecutor: executor, keyboardDeviceManager: deviceManager,
            isSecureInputEnabled: { [weak self] in self?.secureInput ?? false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
    }

    override func tearDown() async throws {
        executor.continuation?.resume()
        executor.continuation = nil
        monitor.stop()
        monitor = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func assignment(_ code: CGKeyCode, press: KeyAction = .eisu, release: KeyAction = .kana,
                            modifiers: ShortcutModifiers = []) -> KeyAssignment {
        var assignment = KeyAssignment(sourceKeyCode: code, action: .none, sourceModifiers: modifiers)
        assignment.separatesPressAndRelease = true
        assignment.pressReleaseActions = PressReleaseActions(onPress: press, onRelease: release)
        return assignment
    }

    private func event(_ code: CGKeyCode, _ type: CGEventType, flags: CGEventFlags = [],
                       sender: Int64 = 1, repeated: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: sender)
        return event
    }

    @discardableResult
    private func send(_ code: CGKeyCode, _ type: CGEventType, flags: CGEventFlags = [],
                      sender: Int64 = 1, repeated: Bool = false) throws -> CGEvent? {
        monitor.handle(type: type, event: try event(code, type, flags: flags, sender: sender, repeated: repeated))
    }

    private func assertKeys(_ keys: [CGKeyCode], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(poster.requests.map(\.keyCode), keys.flatMap { [$0, $0] }, file: file, line: line)
        XCTAssertEqual(poster.requests.map(\.isKeyDown), keys.flatMap { _ in [true, false] }, file: file, line: line)
    }

    func testNormalKeySendsCompleteKeysAtEachEdgeAndSuppressesRepeats() throws {
        preferences.keyAssignments = [assignment(0)]
        XCTAssertNil(try send(0, .keyDown))
        assertKeys([102])
        for _ in 0..<3 { XCTAssertNil(try send(0, .keyDown, repeated: true)) }
        XCTAssertNil(try send(0, .keyDown), "Duplicate keyDown must not repeat an action")
        assertKeys([102])
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([102, 104])
        let orphan = try event(0, .keyUp)
        XCTAssertTrue(monitor.handle(type: .keyUp, event: orphan) === orphan)
        assertKeys([102, 104])
    }

    func testOneSidedAndSelfKeyDestinationsWorkWithoutRecursion() throws {
        preferences.keyAssignments = [assignment(0, press: .sendKey(keyCode: 0), release: .none)]
        XCTAssertNil(try send(0, .keyDown))
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([0])
        preferences.keyAssignments = [assignment(0, press: .none)]
        XCTAssertNil(try send(0, .keyDown))
        assertKeys([0])
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([0, 104])
        let ownEvent = try event(0, .keyDown)
        ownEvent.setIntegerValueField(.eventSourceUserData, value: try XCTUnwrap(poster.requests.last).userData)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: ownEvent) === ownEvent)
        assertKeys([0, 104])
    }

    func testShortcutRequiresExactModifiersAndReleasesAfterModifiersAreUp() throws {
        preferences.keyAssignments = [assignment(0, modifiers: [.command, .shift])]
        let plain = try event(0, .keyDown)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: plain) === plain)
        _ = try send(0, .keyUp)
        XCTAssertNil(try send(0, .keyDown, flags: [.maskCommand, .maskShift]))
        assertKeys([102])
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([102, 104])
    }

    func testModifierPairsAreIndependentAndDoNotUseLaterWins() throws {
        preferences.keyAssignments = [assignment(55), assignment(56, press: .f13, release: .f14)]
        _ = try send(55, .flagsChanged, flags: .maskCommand)
        _ = try send(56, .flagsChanged, flags: [.maskCommand, .maskShift])
        assertKeys([102, 105])
        _ = monitor.handle(type: .leftMouseDown, event: try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left
        )))
        _ = try send(0, .keyDown, flags: [.maskCommand, .maskShift])
        _ = try send(0, .keyUp, flags: [.maskCommand, .maskShift])
        _ = try send(55, .flagsChanged, flags: .maskShift)
        _ = try send(56, .flagsChanged)
        assertKeys([102, 105, 104, 107])
    }

    func testAutomaticModifiersRetainLaterWinsAcrossDifferentModifierKinds() throws {
        preferences.keyAssignments = [
            KeyAssignment(sourceKeyCode: 55, action: .eisu), KeyAssignment(sourceKeyCode: 56, action: .kana)
        ]
        _ = try send(55, .flagsChanged, flags: .maskCommand)
        assertKeys([])
        _ = try send(56, .flagsChanged, flags: [.maskCommand, .maskShift])
        assertKeys([104])
        _ = try send(55, .flagsChanged, flags: .maskShift)
        _ = try send(56, .flagsChanged)
        assertKeys([104])
    }

    func testMixingSplitAndAutomaticModifiersCancelsAutomaticTapOnly() throws {
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 55, action: .f13), assignment(54)]
        _ = try send(55, .flagsChanged, flags: .maskCommand)
        _ = try send(54, .flagsChanged, flags: .maskCommand)
        _ = try send(54, .flagsChanged, flags: .maskCommand)
        _ = try send(55, .flagsChanged)
        assertKeys([102, 104])
    }

    func testFnPairSuppressesGlobeEventsButRetainsReleaseDuringAChord() throws {
        preferences.keyAssignments = [assignment(63)]
        XCTAssertNil(try send(63, .flagsChanged, flags: .maskSecondaryFn))
        _ = try send(0, .keyDown, flags: .maskSecondaryFn)
        _ = try send(0, .keyUp, flags: .maskSecondaryFn)
        XCTAssertNil(try send(63, .flagsChanged))
        assertKeys([102, 104])
    }

    func testAutomaticModifierPressedAfterSplitStillWinsWithoutDiscardingSplitRelease() throws {
        preferences.keyAssignments = [assignment(55), KeyAssignment(sourceKeyCode: 56, action: .f13)]
        _ = try send(55, .flagsChanged, flags: .maskCommand)
        assertKeys([102])
        _ = try send(56, .flagsChanged, flags: [.maskCommand, .maskShift])
        assertKeys([102, 105])
        _ = try send(56, .flagsChanged, flags: .maskCommand)
        _ = try send(55, .flagsChanged)
        assertKeys([102, 105, 104])
    }

    func testSettingsChangesDoNotDiscardOrChangeReleaseOfStartedPair() throws {
        for code: CGKeyCode in [0, 55, 63] {
            preferences.keyAssignments = [assignment(code)]
            let modifier = ModifierKey.from(keyCode: Int64(code))
            _ = try send(code, modifier == nil ? .keyDown : .flagsChanged, flags: modifier?.flagMask ?? [])
            preferences.keyAssignments.removeAll()
            _ = try send(code, modifier == nil ? .keyUp : .flagsChanged)
        }
        assertKeys([102, 104, 102, 104, 102, 104])
    }

    func testEnablingSplitWhileOriginalKeyIsHeldDoesNotOrphanOriginalOutput() throws {
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11)]
        XCTAssertEqual(try send(0, .keyDown)?.getIntegerValueField(.keyboardEventKeycode), 11)
        preferences.keyAssignments[0].setSeparatesPressAndRelease(true)
        preferences.keyAssignments[0].pressReleaseActions = PressReleaseActions(onPress: .eisu, onRelease: .kana)
        XCTAssertEqual(try send(0, .keyUp)?.getIntegerValueField(.keyboardEventKeycode), 11)
        assertKeys([])
        XCTAssertNil(try send(0, .keyDown))
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([102, 104])
    }

    func testKeyboardExclusionsAndSeparateDeviceReleasesAreRespected() throws {
        var mapping = assignment(0)
        mapping.ignoredKeyboardIDs = ["excluded"]
        preferences.keyAssignments = [mapping]
        XCTAssertNil(try send(0, .keyDown))
        for type: CGEventType in [.keyDown, .keyUp] {
            let excluded = try event(0, type, sender: 2)
            XCTAssertTrue(monitor.handle(type: type, event: excluded) === excluded)
        }
        assertKeys([102])
        preferences.keyAssignments[0].ignoredKeyboardIDs.insert("included")
        XCTAssertNil(try send(0, .keyUp))
        assertKeys([102, 104])
    }

    func testUnknownSenderCancelsPairRatherThanGuessingItsRelease() throws {
        preferences.keyAssignments = [assignment(0)]
        _ = try send(0, .keyDown)
        _ = try send(0, .keyUp, sender: 0)
        assertKeys([102])
        _ = try send(0, .keyDown)
        _ = try send(0, .keyUp)
        assertKeys([102, 102, 104])
    }

    func testResetStopRemovalRecordingAndSecureInputCancelPendingReleases() throws {
        for code: CGKeyCode in [0, 55] {
            for cancellation in 0..<5 {
                preferences.keyAssignments = [assignment(code)]
                _ = try send(code, code == 0 ? .keyDown : .flagsChanged, flags: code == 0 ? [] : .maskCommand)
                switch cancellation {
                case 0: monitor.resetState()
                case 1: monitor.stop()
                case 2: deviceManager.removals.send()
                case 3: preferences.isRecordingKey = true
                default:
                    secureInput = true
                    _ = try send(1, .keyDown)
                }
                _ = try send(code, code == 0 ? .keyUp : .flagsChanged)
                preferences.isRecordingKey = false
                secureInput = false
            }
        }
        assertKeys(Array(repeating: 102, count: 10))
    }

    func testMediaKeysUseSamePressReleasePathWithoutSendingOriginalMediaKey() throws {
        preferences.keyAssignments = [assignment(SystemKey.playPause.keyCode)]
        for down in [true, false] {
            let raw = (SystemKey.playPause.rawValue << 16) | ((down ? 0x0a : 0x0b) << 8)
            let input = try XCTUnwrap(NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 8, data1: raw, data2: -1
            )?.cgEvent)
            input.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: 1)
            XCTAssertNil(monitor.handle(type: input.type, event: input))
        }
        assertKeys([102, 104])
    }

    func testSystemActionsRunOutsideCallbackAndReleaseWaitsForPressAction() async throws {
        preferences.keyAssignments = [assignment(0, press: .system(.mediaPlay), release: .system(.mediaPause))]
        executor.holdPlay = true
        let started = expectation(description: "Press action started")
        let released = expectation(description: "Release action executed")
        executor.onExecute = { action in
            if action == .mediaPlay { started.fulfill() } else { released.fulfill() }
        }
        XCTAssertNil(try send(0, .keyDown))
        XCTAssertNil(try send(0, .keyUp))
        XCTAssertTrue(executor.actions.isEmpty)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPlay])
        executor.continuation?.resume()
        executor.continuation = nil
        await fulfillment(of: [released], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPlay, .mediaPause])
        assertKeys([])
    }
}
