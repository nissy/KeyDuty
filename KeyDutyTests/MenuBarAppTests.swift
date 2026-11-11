import XCTest
@testable import KeyDuty

@MainActor
final class MenuBarAppTests: XCTestCase {
    func testUnitTestProcessIsDetected() {
        XCTAssertTrue(MenuBarApp.isRunningUnitTests)
    }

    func testStepperRepeatIntervalAcceleratesWithHeldDuration() {
        let initial = AcceleratingStepperTiming.repeatInterval(for: 0.4)
        let later = AcceleratingStepperTiming.repeatInterval(for: 1.4)
        let muchLater = AcceleratingStepperTiming.repeatInterval(for: 2.4)

        XCTAssertEqual(initial, 0.1, accuracy: 0.000_1)
        XCTAssertLessThan(later, initial)
        XCTAssertLessThan(muchLater, later)
    }

    func testStepperRepeatIntervalStopsAtMinimum() {
        XCTAssertEqual(
            AcceleratingStepperTiming.repeatInterval(for: 60),
            AcceleratingStepperTiming.minimumRepeatInterval,
            accuracy: 0.000_1
        )
    }
}
