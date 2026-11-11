import AppKit
import CoreGraphics
import XCTest
@testable import KeyDuty

private final class ExclusionEventPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []
    func post(_ request: KeyEventRequest, source: CGEventSource) throws { requests.append(request) }
}

@MainActor
private final class ExclusionActionExecutor: SystemActionExecuting {
    var actions: [SystemAction] = []
    var onExecute: (() -> Void)?
    func execute(_ action: SystemAction) async throws {
        actions.append(action)
        onExecute?()
    }
}

@MainActor
final class KeyboardExclusionMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var preferences: Preferences!
    private var poster: ExclusionEventPoster!
    private var executor: ExclusionActionExecutor!
    private var monitor: KeyMonitor!
    private var deviceManager: KeyboardDeviceManager!

    override func setUp() async throws {
        suite = "KeyboardExclusionMonitorTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        poster = ExclusionEventPoster()
        executor = ExclusionActionExecutor()
        let resolver = KeyboardEventSourceResolver { $0 == 1 ? "included" : "excluded" }
        deviceManager = KeyboardDeviceManager(sourceResolver: resolver)
        monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(poster: poster, canPostEvents: { true }),
            actionExecutor: executor, keyboardDeviceManager: deviceManager,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
    }

    override func tearDown() async throws {
        monitor.stop()
        monitor = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func event(
        _ code: CGKeyCode, _ type: CGEventType, sender: Int64 = 1, flags: CGEventFlags = []
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: sender)
        return event
    }

    private func configure(_ assignment: KeyAssignment) {
        var restricted = assignment
        restricted.ignoredKeyboardIDs = ["excluded"]
        preferences.keyAssignments = [restricted]
    }

    func testNormalKeyAndReleaseAreIndependentAcrossKeyboards() throws {
        configure(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        let includedDown = try event(0, .keyDown)
        let excludedDown = try event(0, .keyDown, sender: 2)
        let excludedUp = try event(0, .keyUp, sender: 2)
        XCTAssertEqual(
            monitor.handle(type: .keyDown, event: includedDown)?.getIntegerValueField(.keyboardEventKeycode), 11
        )
        XCTAssertTrue(monitor.handle(type: .keyDown, event: excludedDown) === excludedDown)
        XCTAssertTrue(monitor.handle(type: .keyUp, event: excludedUp) === excludedUp)
        let includedUp = try event(0, .keyUp)
        XCTAssertEqual(monitor.handle(type: .keyUp, event: includedUp)?.getIntegerValueField(.keyboardEventKeycode), 11)
    }

    func testDeviceRemovalReleasesMappedKeyAndClearsModifierState() throws {
        preferences.keyAssignments = [
            KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11),
            KeyAssignment(sourceKeyCode: 55, action: .eisu)
        ]
        _ = monitor.handle(type: .keyDown, event: try event(0, .keyDown))
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, flags: .maskCommand))
        deviceManager.removals.send()
        XCTAssertEqual(poster.requests.map(\.keyCode), [11])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [false])

        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, sender: 2, flags: .maskCommand))
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, sender: 2))
        XCTAssertEqual(poster.requests.map(\.keyCode), [11, 102, 102])
    }

    func testDeviceRemovalCancelsPendingSystemAction() async throws {
        configure(KeyAssignment(sourceKeyCode: 0, action: .system(.sleep)))
        let unexpected = expectation(description: "Disconnected keyboard action must not execute")
        unexpected.isInverted = true
        executor.onExecute = { unexpected.fulfill() }
        _ = monitor.handle(type: .keyDown, event: try event(0, .keyDown))
        _ = monitor.handle(type: .keyUp, event: try event(0, .keyUp))
        deviceManager.removals.send()
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testDeviceRemovalReleasesMappedDestinationEvenIfOriginalKeyWasHeld() throws {
        configure(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        _ = monitor.handle(type: .keyDown, event: try event(0, .keyDown))
        _ = monitor.handle(type: .keyDown, event: try event(11, .keyDown, sender: 2))
        deviceManager.removals.send()
        XCTAssertEqual(poster.requests.map(\.keyCode), [11])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [false])
    }

    func testReleaseWithMissingSenderDoesNotLeaveMappedDestinationHeld() throws {
        configure(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        _ = monitor.handle(type: .keyDown, event: try event(0, .keyDown))
        let unidentifiedRelease = try event(0, .keyUp, sender: 0)
        XCTAssertTrue(monitor.handle(type: .keyUp, event: unidentifiedRelease) === unidentifiedRelease)
        XCTAssertEqual(poster.requests.map(\.keyCode), [11])
        XCTAssertEqual(poster.requests.map(\.isKeyDown), [false])
        monitor.stop()
        XCTAssertEqual(poster.requests.count, 1, "The destination must already be released")
    }

    func testMissingModifierSenderDoesNotFireActionOnNextKeyDown() throws {
        configure(KeyAssignment(sourceKeyCode: 55, action: .eisu))
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, flags: .maskCommand))
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, sender: 0))
        XCTAssertTrue(poster.requests.isEmpty)
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged, flags: .maskCommand))
        XCTAssertTrue(poster.requests.isEmpty, "A lost release must not turn the next press into a release")
        _ = monitor.handle(type: .flagsChanged, event: try event(55, .flagsChanged))
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
    }

    func testChangingExclusionsWhileHeldStillReleasesMappedKey() throws {
        configure(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        _ = monitor.handle(type: .keyDown, event: try event(0, .keyDown))
        preferences.keyAssignments[0].ignoredKeyboardIDs.insert("included")
        let output = monitor.handle(type: .keyUp, event: try event(0, .keyUp))
        XCTAssertEqual(output?.getIntegerValueField(.keyboardEventKeycode), 11)
        let newDown = try event(0, .keyDown)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: newDown) === newDown)
    }

    func testModifierIgnoresOnlyItsOwnRule() throws {
        configure(KeyAssignment(sourceKeyCode: 55, action: .eisu))
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 54, action: .kana))
        for code: CGKeyCode in [55, 54] {
            for input in [try event(code, .flagsChanged, sender: 2, flags: .maskCommand),
                          try event(code, .flagsChanged, sender: 2)] {
                XCTAssertTrue(monitor.handle(type: .flagsChanged, event: input) === input)
            }
        }
        XCTAssertEqual(poster.requests.map(\.keyCode), [104, 104])
    }

    func testShortcutActionRunsOnlyOnIncludedKeyboard() async throws {
        configure(KeyAssignment(sourceKeyCode: 1, action: .system(.sleep), sourceModifiers: [.command, .shift]))
        let executed = expectation(description: "Included shortcut executes once")
        executor.onExecute = { executed.fulfill() }
        for sender: Int64 in [2, 1] {
            for type: CGEventType in [.keyDown, .keyUp] {
                let input = try event(1, type, sender: sender, flags: [.maskCommand, .maskShift])
                let output = monitor.handle(type: type, event: input)
                if sender == 2 { XCTAssertTrue(output === input) } else { XCTAssertNil(output) }
            }
        }
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions, [.sleep])
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testExcludingHeldActionCancelsItOnRelease() async throws {
        configure(KeyAssignment(sourceKeyCode: 0, action: .system(.displayOff)))
        let unexpected = expectation(description: "Excluded action does not run")
        unexpected.isInverted = true
        executor.onExecute = { unexpected.fulfill() }
        XCTAssertNil(monitor.handle(type: .keyDown, event: try event(0, .keyDown)))
        preferences.keyAssignments[0].ignoredKeyboardIDs.insert("included")
        XCTAssertNil(monitor.handle(type: .keyUp, event: try event(0, .keyUp)))
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testCapsLockExclusionPreservesOriginalToggle() throws {
        configure(KeyAssignment(sourceKeyCode: 57, action: .eisu))
        let excluded = try event(57, .flagsChanged, sender: 2, flags: .maskAlphaShift)
        XCTAssertTrue(monitor.handle(type: .flagsChanged, event: excluded) === excluded)
        XCTAssertTrue(poster.requests.isEmpty)
        let included = try event(57, .flagsChanged)
        XCTAssertTrue(monitor.handle(type: .flagsChanged, event: included) === included)
        XCTAssertEqual(poster.requests.map(\.keyCode), [102, 102])
    }

    func testUnknownSourceBypassesRestrictedButNotUnrestrictedAssignments() throws {
        configure(KeyAssignment(sourceKeyCode: 0, destinationKeyCode: 11))
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 1, destinationKeyCode: 2))
        let unknown = try event(0, .keyDown, sender: 0)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: unknown) === unknown)
        let unrestricted = try event(1, .keyDown, sender: 0)
        XCTAssertEqual(
            monitor.handle(type: .keyDown, event: unrestricted)?.getIntegerValueField(.keyboardEventKeycode), 2
        )
    }

    func testSpecialMediaKeyUsesOriginalEventSource() throws {
        configure(KeyAssignment(sourceKeyCode: SystemKey.playPause.keyCode, action: .eisu))
        for sender: Int64 in [2, 1] {
            for down in [true, false] {
                let data = (Int(SystemKey.playPause.rawValue) << 16) | (down ? 0x0a00 : 0x0b00)
                let input = try XCTUnwrap(NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1
                )?.cgEvent)
                input.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: sender)
                let output = monitor.handle(type: SystemKeyInput.eventType, event: input)
                if sender == 2 {
                    XCTAssertTrue(output === input)
                } else {
                    XCTAssertEqual(output?.getIntegerValueField(.keyboardEventKeycode), 102)
                }
            }
        }
    }
}
