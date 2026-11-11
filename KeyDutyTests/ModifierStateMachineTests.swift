import XCTest
@testable import KeyDuty

final class ModifierStateMachineTests: XCTestCase {
    private let leftCommandOnly: Set<ModifierKey> = [.leftCommand]
    private let bothCommands: Set<ModifierKey> = [.leftCommand, .rightCommand]

    func testSinglePressFiresOnRelease() {
        var machine = ModifierStateMachine()

        XCTAssertTrue(machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly).isEmpty)
        XCTAssertEqual(machine.modifierUp(.leftCommand), [.leftCommand])
    }

    func testCancelSuppressesSinglePress() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly)
        machine.cancel()

        XCTAssertTrue(machine.modifierUp(.leftCommand).isEmpty)
    }

    func testSecondAssignedKeyFiresImmediately() {
        var machine = ModifierStateMachine()

        XCTAssertTrue(machine.modifierDown(.leftCommand, assignedKeys: bothCommands).isEmpty)
        XCTAssertEqual(machine.modifierDown(.rightCommand, assignedKeys: bothCommands), [.rightCommand])
        XCTAssertTrue(machine.modifierUp(.rightCommand).isEmpty)
        XCTAssertTrue(machine.modifierUp(.leftCommand).isEmpty)
    }

    func testUnassignedModifierPermanentlySuppressesChord() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly)
        _ = machine.modifierDown(.leftShift, assignedKeys: leftCommandOnly)
        _ = machine.modifierUp(.leftShift)

        XCTAssertTrue(machine.modifierUp(.leftCommand).isEmpty)
    }

    func testAssignedKeyPressedWhileUnassignedModifierIsHeldIsSuppressed() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftShift, assignedKeys: leftCommandOnly)
        _ = machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly)
        _ = machine.modifierUp(.leftShift)

        XCTAssertTrue(machine.modifierUp(.leftCommand).isEmpty)
    }

    func testSecondAssignedKeyCanFireAgainAfterBeingRepressed() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftCommand, assignedKeys: bothCommands)
        XCTAssertEqual(machine.modifierDown(.rightCommand, assignedKeys: bothCommands), [.rightCommand])
        _ = machine.modifierUp(.rightCommand)

        XCTAssertEqual(machine.modifierDown(.rightCommand, assignedKeys: bothCommands), [.rightCommand])
    }

    func testResetDiscardsAllStateWithoutFiring() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly)
        machine.reset()

        XCTAssertTrue(machine.modifierUp(.leftCommand).isEmpty)
        XCTAssertTrue(machine.physicalPressed.isEmpty)
        XCTAssertTrue(machine.keyStates.isEmpty)
    }

    func testDuplicateDownDoesNotFire() {
        var machine = ModifierStateMachine()

        _ = machine.modifierDown(.leftCommand, assignedKeys: bothCommands)

        XCTAssertTrue(machine.modifierDown(.leftCommand, assignedKeys: bothCommands).isEmpty)
    }

    func testPhysicalPressedStateTracksDownAndUp() {
        var machine = ModifierStateMachine()

        XCTAssertFalse(machine.isPhysicallyPressed(.leftCommand))
        _ = machine.modifierDown(.leftCommand, assignedKeys: leftCommandOnly)
        XCTAssertTrue(machine.isPhysicallyPressed(.leftCommand))
        _ = machine.modifierUp(.leftCommand)
        XCTAssertFalse(machine.isPhysicallyPressed(.leftCommand))
    }
}
