import CoreGraphics
import XCTest
@testable import KeyDuty

@MainActor
private final class ShortcutTestExecutor: SystemActionExecuting {
    var actions: [SystemAction] = []
    var onExecute: (() -> Void)?

    func execute(_ action: SystemAction) async throws {
        actions.append(action)
        onExecute?()
    }
}

private final class ShortcutEventPoster: KeyEventPosting {
    var requests: [KeyEventRequest] = []
    func post(_ request: KeyEventRequest, source: CGEventSource) throws { requests.append(request) }
}

@MainActor
final class ShortcutMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ShortcutMonitorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suiteName) }

    private func event(_ code: CGKeyCode, type: CGEventType, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        return event
    }

    func testShortcutSuppressesModifierTapsAndRunsOnlyItsActionAfterRelease() async throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments.append(KeyAssignment(
            sourceKeyCode: 0, action: .system(.mediaPause), sourceModifiers: [.command, .shift]
        ))
        let executor = ShortcutTestExecutor()
        let executed = expectation(description: "Shortcut action")
        executor.onExecute = { executed.fulfill() }
        let poster = ShortcutEventPoster()
        let monitor = KeyMonitor(
            preferences: preferences, sender: try KeySender(poster: poster, canPostEvents: { true }),
            actionExecutor: executor, isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
        for input in [
            try event(55, type: .flagsChanged, flags: .maskCommand),
            try event(56, type: .flagsChanged, flags: [.maskCommand, .maskShift]),
            try event(0, type: .keyDown, flags: [.maskCommand, .maskShift]),
            try event(56, type: .flagsChanged, flags: .maskCommand),
            try event(55, type: .flagsChanged),
            try event(0, type: .keyUp)
        ] {
            let result = monitor.handle(type: input.type, event: input)
            if input.type == .keyDown || input.type == .keyUp { XCTAssertNil(result) }
        }
        XCTAssertTrue(executor.actions.isEmpty)
        await fulfillment(of: [executed], timeout: 2)
        XCTAssertEqual(executor.actions, [.mediaPause])
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testShortcutCanSendUnmodifiedKeyWithoutRecursionOrModifierTap() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.keyAssignments.append(KeyAssignment(
            sourceKeyCode: 0, destinationKeyCode: 0, sourceModifiers: [.command]
        ))
        let poster = ShortcutEventPoster()
        let sender = try KeySender(poster: poster, sessionToken: 123, canPostEvents: { true })
        let monitor = KeyMonitor(
            preferences: preferences, sender: sender,
            isSecureInputEnabled: { false }, currentModifierFlags: { [] },
            onError: { XCTFail($0.localizedDescription) }
        )
        _ = monitor.handle(type: .flagsChanged, event: try event(55, type: .flagsChanged, flags: .maskCommand))
        XCTAssertNil(monitor.handle(type: .keyDown, event: try event(0, type: .keyDown, flags: .maskCommand)))
        XCTAssertNil(monitor.handle(type: .keyUp, event: try event(0, type: .keyUp, flags: .maskCommand)))
        _ = monitor.handle(type: .flagsChanged, event: try event(55, type: .flagsChanged))
        XCTAssertEqual(poster.requests, [
            KeyEventRequest(keyCode: 0, isKeyDown: true, userData: 123),
            KeyEventRequest(keyCode: 0, isKeyDown: false, userData: 123)
        ])
        let ownEvent = try event(0, type: .keyDown, flags: .maskCommand)
        ownEvent.setIntegerValueField(.eventSourceUserData, value: 123)
        XCTAssertTrue(monitor.handle(type: .keyDown, event: ownEvent) === ownEvent)
        XCTAssertEqual(poster.requests.count, 2)
    }
}
