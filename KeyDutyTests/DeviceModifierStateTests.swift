import XCTest
@testable import KeyDuty

final class DeviceModifierStateTests: XCTestCase {
    private let included = KeyboardEventOrigin(senderID: 1, keyboardID: "included")
    private let excluded = KeyboardEventOrigin(senderID: 2, keyboardID: "excluded")
    private let assignment = KeyAssignment(sourceKeyCode: 55, action: .eisu)

    func testExcludedPressAndReleaseDoNotFire() {
        var state = DeviceModifierState()
        XCTAssertTrue(
            state.handle(.leftCommand, flags: .maskCommand, origin: excluded, assignments: []).actions.isEmpty
        )
        XCTAssertTrue(state.handle(.leftCommand, flags: [], origin: excluded, assignments: []).actions.isEmpty)
        XCTAssertTrue(state.handle(.leftCommand, flags: [], origin: excluded, assignments: []).actions.isEmpty)
    }

    func testIncludedDeviceStillFires() {
        var state = DeviceModifierState()
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: included, assignments: [assignment])
        XCTAssertEqual(
            state.handle(.leftCommand, flags: [], origin: included, assignments: [assignment]).actions, [.eisu]
        )
    }

    func testResetClearsPressedState() {
        var state = DeviceModifierState()
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: included, assignments: [assignment])
        state.reset()
        XCTAssertTrue(
            state.handle(.leftCommand, flags: [], origin: included, assignments: [assignment]).actions.isEmpty
        )
    }

    func testSameModifierOnTwoKeyboardsDoesNotFireOnOtherKeyboardsPress() {
        var state = DeviceModifierState()
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: included, assignments: [assignment])
        let otherPress = state.handle(.leftCommand, flags: .maskCommand, origin: excluded, assignments: [])
        XCTAssertTrue(otherPress.actions.isEmpty)
        XCTAssertTrue(
            state.handle(.leftCommand, flags: .maskCommand, origin: included, assignments: [assignment]).actions.isEmpty
        )
        XCTAssertTrue(state.handle(.leftCommand, flags: [], origin: excluded, assignments: []).actions.isEmpty)
    }

    func testExcludedModifierCancelsIncludedTap() {
        var state = DeviceModifierState()
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: included, assignments: [assignment])
        _ = state.handle(.leftShift, flags: [.maskCommand, .maskShift], origin: excluded, assignments: [])
        XCTAssertTrue(
            state.handle(.leftCommand, flags: .maskShift, origin: included, assignments: [assignment]).actions.isEmpty
        )
    }

    func testFnSuppressionIsLatchedUntilReleaseIfExclusionChanges() {
        var state = DeviceModifierState()
        let function = KeyAssignment(sourceKeyCode: 63, action: .eisu)
        XCTAssertTrue(
            state.handle(.function, flags: .maskSecondaryFn, origin: included, assignments: [function]).suppressEvent
        )
        let release = state.handle(.function, flags: [], origin: included, assignments: [])
        XCTAssertTrue(release.suppressEvent)
        XCTAssertTrue(release.actions.isEmpty)
        XCTAssertFalse(
            state.handle(.function, flags: .maskSecondaryFn, origin: excluded, assignments: []).suppressEvent
        )
    }
}
