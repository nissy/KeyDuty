import CoreGraphics
import XCTest
@testable import KeyDuty

private final class AuditOutput {
    var events: [String] = []
}

private final class AuditPoster: KeyEventPosting {
    let output: AuditOutput
    var onPress: (() -> Void)?
    init(output: AuditOutput) { self.output = output }
    func post(_ request: KeyEventRequest, source: CGEventSource) throws {
        if request.isKeyDown {
            output.events.append("key:\(request.keyCode)")
            onPress?()
        }
    }
}

@MainActor
private final class HeldActionExecutor: SystemActionExecuting {
    let output: AuditOutput
    var continuation: CheckedContinuation<Void, Error>?
    var onStart: (() -> Void)?
    init(output: AuditOutput) { self.output = output }

    func execute(_ action: SystemAction) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
        output.events.append("system")
    }
}

@MainActor
final class ActionExecutionRegressionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var output: AuditOutput!
    private var poster: AuditPoster!
    private var executor: HeldActionExecutor!
    private var monitor: KeyMonitor!
    private var errors: [Error] = []

    override func setUp() async throws {
        suite = "ActionExecutionRegressionTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        output = AuditOutput()
        poster = AuditPoster(output: output)
        executor = HeldActionExecutor(output: output)
        monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(poster: poster, canPostEvents: { true }),
            actionExecutor: executor, isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { [weak self] in self?.errors.append($0) }
        )
    }

    override func tearDown() async throws {
        executor.continuation?.resume()
        executor.continuation = nil
        monitor.stop()
        monitor = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func configure(_ code: CGKeyCode) {
        var assignment = KeyAssignment(sourceKeyCode: code, action: .none)
        assignment.separatesPressAndRelease = true
        assignment.pressReleaseActions = PressReleaseActions(onPress: .system(.mediaPlay), onRelease: .kana)
        preferences.keyAssignments = [assignment]
    }

    private func send(_ code: CGKeyCode, down: Bool) throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
        if let modifier = ModifierKey.from(keyCode: Int64(code)) {
            event.type = .flagsChanged
            event.flags = down ? modifier.flagMask : []
        } else {
            event.flags = []
        }
        _ = monitor.handle(type: event.type, event: event)
    }

    private func assertReleaseKeyWaitsForPressAction(_ code: CGKeyCode) async throws {
        configure(code)
        let started = expectation(description: "Press system action started")
        let sent = expectation(description: "Release key sent")
        executor.onStart = { started.fulfill() }
        poster.onPress = { sent.fulfill() }
        try send(code, down: true)
        try send(code, down: false)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(output.events.isEmpty, "The release key must not overtake the pending press action")
        executor.continuation?.resume()
        executor.continuation = nil
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(output.events, ["system", "key:104"])
    }

    func testNormalReleaseKeyDoesNotOvertakePressSystemAction() async throws {
        try await assertReleaseKeyWaitsForPressAction(0)
    }

    func testModifierReleaseKeyDoesNotOvertakePressSystemAction() async throws {
        try await assertReleaseKeyWaitsForPressAction(55)
    }

    func testFnReleaseKeyDoesNotOvertakePressSystemAction() async throws {
        try await assertReleaseKeyWaitsForPressAction(63)
    }

    func testUnrelatedAutomaticTapIsNotDelayedByRunningSystemAction() async throws {
        configure(0)
        preferences.keyAssignments.append(KeyAssignment(sourceKeyCode: 55, action: .eisu))
        let started = expectation(description: "Press system action started")
        executor.onStart = { started.fulfill() }
        try send(0, down: true)
        await fulfillment(of: [started], timeout: 2)
        try send(55, down: true)
        try send(55, down: false)
        XCTAssertEqual(output.events, ["key:102"], "Unrelated mappings must remain responsive")
    }

    func testResetCancelsReleaseKeyQueuedBehindPressAction() async throws {
        configure(0)
        let started = expectation(description: "Press system action started")
        let unexpected = expectation(description: "Cancelled release key must not be sent")
        unexpected.isInverted = true
        executor.onStart = { started.fulfill() }
        poster.onPress = { unexpected.fulfill() }
        try send(0, down: true)
        await fulfillment(of: [started], timeout: 2)
        try send(0, down: false)
        monitor.resetState()
        executor.continuation?.resume()
        executor.continuation = nil
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertEqual(output.events, ["system"])
    }

    func testCancelledActionFailureDoesNotOverwriteNewErrorState() async throws {
        configure(0)
        let started = expectation(description: "Old action started")
        executor.onStart = { started.fulfill() }
        try send(0, down: true)
        await fulfillment(of: [started], timeout: 2)
        monitor.resetState()
        preferences.actionError = "new state"
        executor.continuation?.resume(throwing: SystemActionError.rejected)
        executor.continuation = nil
        // キューに入っているMainActorの完了処理を通してから結果を調べる。
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(preferences.actionError, "new state")
        XCTAssertTrue(errors.isEmpty)
    }

    func testCancelledActionSuccessDoesNotClearNewErrorState() async throws {
        configure(0)
        let started = expectation(description: "Old action started")
        executor.onStart = { started.fulfill() }
        try send(0, down: true)
        await fulfillment(of: [started], timeout: 2)
        monitor.resetState()
        preferences.actionError = "new state"
        executor.continuation?.resume()
        executor.continuation = nil
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(preferences.actionError, "new state")
    }
}
