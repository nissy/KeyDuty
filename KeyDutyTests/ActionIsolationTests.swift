import CoreGraphics
import XCTest
@testable import KeyDuty

private final class IsolationTrace {
    var events: [String] = []
}

private final class IsolationPoster: KeyEventPosting {
    let trace: IsolationTrace
    var onKey: (() -> Void)?
    init(_ trace: IsolationTrace) { self.trace = trace }
    func post(_ request: KeyEventRequest, source: CGEventSource) throws {
        if request.isKeyDown {
            trace.events.append("key:\(request.keyCode)")
            onKey?()
        }
    }
}

@MainActor
private final class IsolationExecutor: SystemActionExecuting {
    let trace: IsolationTrace
    var holdSecondPlay = false
    var playCount = 0
    var continuation: CheckedContinuation<Void, Never>?
    var onStart: ((SystemAction) -> Void)?
    init(_ trace: IsolationTrace) { self.trace = trace }
    func execute(_ action: SystemAction) async throws {
        if action == .mediaPlay { playCount += 1 }
        if action == .startScreensaver || (holdSecondPlay && playCount == 2) {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onStart?(action)
            }
        }
        trace.events.append("system:\(action.rawValue)")
        if continuation == nil { onStart?(action) }
    }
}

@MainActor
final class ActionIsolationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var trace: IsolationTrace!
    private var poster: IsolationPoster!
    private var executor: IsolationExecutor!
    private var monitor: KeyMonitor!

    override func setUp() async throws {
        suite = "ActionIsolationTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
        trace = IsolationTrace()
        poster = IsolationPoster(trace)
        executor = IsolationExecutor(trace)
        let devices = KeyboardDeviceManager(sourceResolver: KeyboardEventSourceResolver { "device\($0)" })
        monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(poster: poster, canPostEvents: { true }),
            actionExecutor: executor, keyboardDeviceManager: devices,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] }, onError: { XCTFail($0.localizedDescription) }
        )
    }

    override func tearDown() async throws {
        executor.onStart = nil
        executor.continuation?.resume()
        executor.continuation = nil
        monitor.stop()
        monitor = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func pair(
        _ code: CGKeyCode, press: SystemAction = .mediaPlay, release: KeyAction = .kana
    ) -> KeyAssignment {
        var row = KeyAssignment(sourceKeyCode: code, action: .none)
        row.separatesPressAndRelease = true
        row.pressReleaseActions = PressReleaseActions(onPress: .system(press), onRelease: release)
        return row
    }

    private func send(_ code: CGKeyCode, down: Bool, device: Int64 = 1) throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
        event.flags = []
        event.setIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 87)), value: device)
        _ = monitor.handle(type: event.type, event: event)
    }

    private func press(_ code: CGKeyCode, action: SystemAction, device: Int64 = 1) async throws {
        let started = expectation(description: "System action started")
        executor.onStart = { observed in if observed == action { started.fulfill() } }
        try send(code, down: true, device: device)
        await fulfillment(of: [started], timeout: 2)
        executor.onStart = nil
    }

    func testReleaseDoesNotWaitForAnotherKeysAction() async throws {
        preferences.keyAssignments = [pair(105), pair(107, press: .startScreensaver, release: .none)]
        try await press(105, action: .mediaPlay)
        try await press(107, action: .startScreensaver)
        let sent = expectation(description: "Release key before unrelated action finishes")
        poster.onKey = { sent.fulfill() }
        try send(105, down: false)
        await fulfillment(of: [sent], timeout: 0.5)
        XCTAssertEqual(trace.events, ["system:mediaPlay", "key:104"])
    }

    func testReleaseDoesNotWaitForSameKeyOnAnotherKeyboard() async throws {
        preferences.keyAssignments = [pair(105)]
        executor.holdSecondPlay = true
        try await press(105, action: .mediaPlay, device: 1)
        try await press(105, action: .mediaPlay, device: 2)
        let sent = expectation(description: "Release key while other keyboard action is pending")
        poster.onKey = { sent.fulfill() }
        try send(105, down: false, device: 1)
        await fulfillment(of: [sent], timeout: 0.5)
        XCTAssertEqual(trace.events, ["system:mediaPlay", "key:104"])
    }

    func testRepeatedPressesOfSameInputKeepAllEdgesInOrder() async throws {
        preferences.keyAssignments = [pair(105)]
        let sent = expectation(description: "Both release keys")
        sent.expectedFulfillmentCount = 2
        poster.onKey = { sent.fulfill() }
        for _ in 0..<2 {
            try send(105, down: true)
            try send(105, down: false)
        }
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(trace.events, ["system:mediaPlay", "key:104", "system:mediaPlay", "key:104"])
    }
}
