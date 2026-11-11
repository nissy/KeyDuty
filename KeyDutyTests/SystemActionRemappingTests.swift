import CoreGraphics
import XCTest
@testable import KeyDuty

final class SystemActionRemappingTests: XCTestCase {
    private func event(down: Bool = true, repeating: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        return event
    }

    func testAllActionsSuppressOriginalKeyAndRepeatsThenFireOnceOnRelease() throws {
        for action in SystemAction.allCases {
            var remapper = KeyRemapper()
            for input in [try event(), try event(repeating: true), try event(repeating: true)] {
                let result = try remapper.remap(input, mappings: [:], actions: [0: action])
                XCTAssertNil(result.event)
                XCTAssertNil(result.action)
            }
            let release = try remapper.remap(event(down: false), mappings: [:], actions: [0: action])
            XCTAssertNil(release.event)
            XCTAssertEqual(release.action, .system(action))
            let duplicateRelease = try remapper.remap(event(down: false), mappings: [:], actions: [0: action])
            XCTAssertNotNil(duplicateRelease.event)
            XCTAssertNil(duplicateRelease.action)
            XCTAssertTrue(remapper.reset().isEmpty)
        }
    }

    func testChangedOrRemovedActionIsCancelledButItsReleaseIsStillSuppressed() throws {
        for actions: [CGKeyCode: SystemAction] in [[:], [0: .mediaPause]] {
            var remapper = KeyRemapper()
            _ = try remapper.remap(event(), mappings: [:], actions: [0: .sleep])
            let release = try remapper.remap(event(down: false), mappings: [:], actions: actions)
            XCTAssertNil(release.event)
            XCTAssertNil(release.action)
        }
    }

    func testKeyToActionChangeWhileHeldKeepsMatchedKeyRelease() throws {
        var remapper = KeyRemapper()
        _ = try remapper.remap(event(), mappings: [0: 11])
        let repeated = try remapper.remap(event(repeating: true), mappings: [:], actions: [0: .sleep])
        let release = try remapper.remap(event(down: false), mappings: [:], actions: [0: .sleep])
        XCTAssertEqual(repeated.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertEqual(release.event?.getIntegerValueField(.keyboardEventKeycode), 11)
        XCTAssertNil(release.action)
        let nextDown = try remapper.remap(event(), mappings: [:], actions: [0: .sleep])
        XCTAssertNil(nextDown.event)
    }

    func testActionToKeyChangeWhileHeldWaitsUntilNextPress() throws {
        var remapper = KeyRemapper()
        _ = try remapper.remap(event(), mappings: [:], actions: [0: .sleep])
        let repeated = try remapper.remap(event(repeating: true), mappings: [0: 11])
        let release = try remapper.remap(event(down: false), mappings: [0: 11])
        XCTAssertNil(repeated.event)
        XCTAssertNil(release.event)
        XCTAssertNil(release.action)
        let nextDown = try remapper.remap(event(), mappings: [0: 11])
        XCTAssertEqual(nextDown.event?.getIntegerValueField(.keyboardEventKeycode), 11)
    }

    func testKeysHeldBeforeStartupOrBeforeAssignmentNeverTriggerAnAction() throws {
        for firstIsRepeat in [true, false] {
            var remapper = KeyRemapper()
            _ = try remapper.remap(event(repeating: firstIsRepeat), mappings: [:],
                                   actions: firstIsRepeat ? [0: .sleep] : [:])
            let repeated = try remapper.remap(event(repeating: true), mappings: [:], actions: [0: .sleep])
            let release = try remapper.remap(event(down: false), mappings: [:], actions: [0: .sleep])
            XCTAssertNotNil(repeated.event)
            XCTAssertNotNil(release.event)
            XCTAssertNil(release.action)
        }
    }

    func testResetCancelsHeldActionsWithoutPostingAnyKeyReleases() throws {
        var remapper = KeyRemapper()
        _ = try remapper.remap(event(), mappings: [:], actions: [0: .sleep])
        XCTAssertTrue(remapper.reset().isEmpty)
        let release = try remapper.remap(event(down: false), mappings: [:], actions: [0: .sleep])
        XCTAssertNil(release.action)
    }
}
