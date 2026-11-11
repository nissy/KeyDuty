import CoreGraphics
import XCTest
@testable import KeyDuty

final class ModifierEditingRegressionTests: XCTestCase {
    private let origin = KeyboardEventOrigin(senderID: 1, keyboardID: "test")

    func testTurningSplitOffWhileHeldExecutesOnlyTheOriginalSplitRelease() {
        var state = DeviceModifierState()
        var assignment = KeyAssignment(sourceKeyCode: 55, action: .f13)
        assignment.setSeparatesPressAndRelease(true)
        assignment.pressReleaseActions = PressReleaseActions(onPress: .eisu, onRelease: .kana)
        XCTAssertEqual(state.handle(
            .leftCommand, flags: .maskCommand, origin: origin, assignments: [assignment]
        ).actions, [.eisu])
        assignment.setSeparatesPressAndRelease(false)
        XCTAssertEqual(state.handle(
            .leftCommand, flags: [], origin: origin, assignments: [assignment]
        ).actions, [.kana], "The automatic F13 action must not run for a press that started in split mode")
    }

    func testEditingAutomaticActionWhileHeldDoesNotExecuteNewAction() {
        var state = DeviceModifierState()
        var assignment = KeyAssignment(sourceKeyCode: 55, action: .eisu)
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: origin, assignments: [assignment])
        assignment.action = .system(.sleep)
        XCTAssertTrue(state.handle(
            .leftCommand, flags: [], origin: origin, assignments: [assignment]
        ).actions.isEmpty, "An edit while holding Command must not execute the newly selected sleep action")
    }

    func testTurningSplitOnWhileHeldDoesNotExecuteAnUnstartedSplitRelease() {
        var state = DeviceModifierState()
        var assignment = KeyAssignment(sourceKeyCode: 55, action: .eisu)
        _ = state.handle(.leftCommand, flags: .maskCommand, origin: origin, assignments: [assignment])
        assignment.setSeparatesPressAndRelease(true)
        assignment.pressReleaseActions.onRelease = .system(.sleep)
        XCTAssertTrue(state.handle(.leftCommand, flags: [], origin: origin, assignments: [assignment]).actions.isEmpty)
    }
}
