import XCTest
@testable import KeyDuty

final class MonitorSuspensionStateTests: XCTestCase {
    func testOverlappingReasonsRemainSuspendedUntilAllReasonsAreRemoved() {
        var state = MonitorSuspensionState()

        state.set(.screenLock, active: true)
        state.set(.systemSleep, active: true)
        state.set(.systemSleep, active: false)

        XCTAssertTrue(state.isSuspended)
        XCTAssertEqual(state.activeReasons, [.screenLock])

        state.set(.screenLock, active: false)

        XCTAssertFalse(state.isSuspended)
    }

    func testSecureInputIsTrackedIndependently() {
        var state = MonitorSuspensionState()

        XCTAssertTrue(state.set(.secureInput, active: true))
        XCTAssertFalse(state.set(.secureInput, active: true))
        XCTAssertTrue(state.isSuspended)

        XCTAssertTrue(state.set(.secureInput, active: false))
        XCTAssertFalse(state.isSuspended)
    }

    func testSettingSameReasonTwiceDoesNotReportChange() {
        var state = MonitorSuspensionState()

        XCTAssertTrue(state.set(.screenLock, active: true))
        XCTAssertFalse(state.set(.screenLock, active: true))
        XCTAssertTrue(state.isSuspended)

        XCTAssertTrue(state.set(.screenLock, active: false))
        XCTAssertFalse(state.set(.screenLock, active: false))
        XCTAssertFalse(state.isSuspended)
    }
}
