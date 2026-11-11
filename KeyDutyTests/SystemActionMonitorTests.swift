import CoreGraphics
import XCTest
@testable import KeyDuty

@MainActor
private final class RecordingActionExecutor: SystemActionExecuting {
    var actions: [SystemAction] = []
    var error: Error?
    var onExecute: (() -> Void)?

    func execute(_ action: SystemAction) async throws {
        actions.append(action)
        onExecute?()
        if let error { throw error }
    }
}

@MainActor
final class SystemActionMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "SystemActionMonitorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func event(_ code: CGKeyCode, type: CGEventType, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        return event
    }

    func testEachActionRunsAfterCallbackWithoutSendingAKey() async throws {
        let preferences = Preferences(defaults: defaults)
        let executor = RecordingActionExecutor()
        let executed = expectation(description: "All six actions executed")
        executed.expectedFulfillmentCount = SystemAction.allCases.count
        executor.onExecute = { executed.fulfill() }
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(canPostEvents: { false }), actionExecutor: executor,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
        for action in SystemAction.allCases {
            preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, action: .system(action))]
            XCTAssertNil(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown)))
            XCTAssertNil(monitor.handle(type: .keyUp, event: try event(0, type: .keyUp)))
        }
        XCTAssertTrue(executor.actions.isEmpty, "Native APIs must run outside the event tap callback")
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions.count, SystemAction.allCases.count)
        XCTAssertEqual(Set(executor.actions), Set(SystemAction.allCases))
    }

    func testModifierSingleTapFiresButChordDoesNot() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 55, action: .system(.mediaPause))]
        let executor = RecordingActionExecutor()
        let executed = expectation(description: "Single modifier tap")
        executor.onExecute = { executed.fulfill() }
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(canPostEvents: { false }), actionExecutor: executor,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
        for event in [
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(0, type: .keyDown, flags: .maskCommand),
            try event(0, type: .keyUp, flags: .maskCommand),
            try event(55, type: .flagsChanged),
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(55, type: .flagsChanged)
        ] {
            _ = monitor.handle(type: event.type, event: event)
        }
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPause])
    }

    func testResetStopAndRecordingCancelPendingActions() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, action: .system(.sleep))]
        let executor = RecordingActionExecutor()
        let unexpected = expectation(description: "No action after cancellation")
        unexpected.isInverted = true
        executor.onExecute = { unexpected.fulfill() }
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(canPostEvents: { false }), actionExecutor: executor,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }
        )
        for cancellation in 0..<3 {
            _ = monitor.handle(type: .keyDown, event: try event(0, type: .keyDown))
            _ = monitor.handle(type: .keyUp, event: try event(0, type: .keyUp))
            switch cancellation {
            case 0: monitor.resetState()
            case 1: monitor.stop()
            default: preferences.isRecordingKey = true
            }
        }
        let recorded = try event(0, type: .keyDown)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: recorded) === recorded)
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertTrue(executor.actions.isEmpty)
    }

    func testExecutionFailureReachesSettingsAndErrorHandler() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, action: .system(.mediaPlay))]
        let executor = RecordingActionExecutor()
        executor.error = SystemActionError.rejected
        let failed = expectation(description: "Failure reported")
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(canPostEvents: { false }), actionExecutor: executor,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { _ in failed.fulfill() }
        )
        _ = monitor.handle(type: .keyDown, event: try event(0, type: .keyDown))
        _ = monitor.handle(type: .keyUp, event: try event(0, type: .keyUp))
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(try XCTUnwrap(preferences.actionError).contains(L10n.text("action.play")))
        let rejection = try XCTUnwrap(SystemActionError.rejected.errorDescription)
        XCTAssertTrue(try XCTUnwrap(preferences.actionError).contains(rejection))
    }

    func testSecureInputCancelsHeldActionAndOnlyFreshPressAfterRecoveryFires() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments = [KeyAssignment(sourceKeyCode: 0, action: .system(.mediaPause))]
        let executor = RecordingActionExecutor()
        var secureInput = false
        let executed = expectation(description: "Fresh press after secure input")
        executor.onExecute = { executed.fulfill() }
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(canPostEvents: { false }), actionExecutor: executor,
            isSecureInputEnabled: { secureInput }, currentModifierFlags: { [] }
        )
        XCTAssertNil(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown)))
        secureInput = true
        let release = try event(0, type: .keyUp)
        XCTAssertTrue(monitor.handle(type: .keyUp, event: release) === release)
        let downWhileSecure = try event(0, type: .keyDown)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: downWhileSecure) === downWhileSecure)
        secureInput = false
        let heldRelease = try event(0, type: .keyUp)
        XCTAssertTrue(monitor.handle(type: .keyUp, event: heldRelease) === heldRelease)
        XCTAssertTrue(executor.actions.isEmpty)
        XCTAssertNil(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown)))
        XCTAssertNil(monitor.handle(type: .keyUp, event: try event(0, type: .keyUp)))
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPause])
    }
}
