import AppKit
import SwiftUI

struct AcceleratingStepper: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(value: Binding<Double>, in range: ClosedRange<Double>) {
        _value = value
        self.range = range
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range)
    }

    func makeNSView(context: Context) -> PressAndHoldStepper {
        let stepper = PressAndHoldStepper()
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        stepper.onStep = { [weak coordinator = context.coordinator] direction in
            coordinator?.step(direction)
        }
        configure(stepper)
        return stepper
    }

    func updateNSView(_ stepper: PressAndHoldStepper, context: Context) {
        context.coordinator.update(value: $value, range: range)
        configure(stepper)
    }

    private func configure(_ stepper: PressAndHoldStepper) {
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = false
        stepper.doubleValue = min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var value: Binding<Double>
        private var range: ClosedRange<Double>

        init(value: Binding<Double>, range: ClosedRange<Double>) {
            self.value = value
            self.range = range
        }

        func update(value: Binding<Double>, range: ClosedRange<Double>) {
            self.value = value
            self.range = range
        }

        func step(_ direction: Int) {
            value.wrappedValue = clamped(value.wrappedValue.rounded() + Double(direction))
        }

        @objc
        func valueChanged(_ sender: NSStepper) {
            value.wrappedValue = clamped(sender.doubleValue.rounded())
        }

        private func clamped(_ value: Double) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }
}

enum AcceleratingStepperTiming {
    static let initialRepeatDelay: TimeInterval = 0.4
    static let initialRepeatInterval: TimeInterval = 0.1
    static let minimumRepeatInterval: TimeInterval = 0.015
    private static let accelerationRate = 0.6

    static func repeatInterval(for heldDuration: TimeInterval) -> TimeInterval {
        let acceleratingDuration = max(heldDuration - initialRepeatDelay, 0)
        return max(
            minimumRepeatInterval,
            initialRepeatInterval * pow(accelerationRate, acceleratingDuration)
        )
    }
}

@MainActor
final class PressAndHoldStepper: NSStepper {
    var onStep: ((Int) -> Void)?

    private var activeDirection = 0
    private var pressStartedAt: TimeInterval = 0
    private var repeatTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        activeDirection = location.y >= bounds.midY ? 1 : -1
        pressStartedAt = ProcessInfo.processInfo.systemUptime
        onStep?(activeDirection)
        scheduleRepeat(after: AcceleratingStepperTiming.initialRepeatDelay)

        let previousTarget = target
        let previousAction = action
        target = nil
        action = nil
        super.mouseDown(with: event)
        target = previousTarget
        action = previousAction

        stopRepeating()
    }

    @objc
    private func repeatTimerDidFire() {
        guard activeDirection != 0 else { return }

        if isPointerInsideActiveSegment {
            onStep?(activeDirection)
        }

        let heldDuration = ProcessInfo.processInfo.systemUptime - pressStartedAt
        scheduleRepeat(after: AcceleratingStepperTiming.repeatInterval(for: heldDuration))
    }

    private var isPointerInsideActiveSegment: Bool {
        guard let window else { return false }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(location) else { return false }
        return activeDirection > 0 ? location.y >= bounds.midY : location.y < bounds.midY
    }

    private func scheduleRepeat(after interval: TimeInterval) {
        repeatTimer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(repeatTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        activeDirection = 0
    }
}
