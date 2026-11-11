@preconcurrency import CoreGraphics

@MainActor
final class KeyActionQueue {
    struct Input: Hashable {
        let senderID: UInt64
        let keyCode: CGKeyCode
    }

    private let sender: KeySender
    private let executor: any SystemActionExecuting
    private let preferences: Preferences
    private let isSuspended: @MainActor () -> Bool
    private let onError: @MainActor (Error) -> Void
    private var generation = 0
    private var systemTask: Task<Void, Never>?
    private var inputTasks: [Input: Task<Void, Never>] = [:]

    init(sender: KeySender, executor: any SystemActionExecuting, preferences: Preferences,
         isSuspended: @escaping @MainActor () -> Bool, onError: @escaping @MainActor (Error) -> Void) {
        self.sender = sender
        self.executor = executor
        self.preferences = preferences
        self.isSuspended = isSuspended
        self.onError = onError
    }

    func perform(_ action: KeyAction, triggeringEvent: CGEvent, input: Input? = nil) throws {
        if action.systemAction != nil || input.flatMap({ inputTasks[$0] }) != nil {
            enqueue(action, input: input)
        } else {
            try sender.send(action, triggeringEvent: triggeringEvent)
        }
    }

    func cancel() {
        generation += 1
        systemTask?.cancel()
        systemTask = nil
        for task in inputTasks.values { task.cancel() }
        inputTasks.removeAll()
    }

    private func enqueue(_ action: KeyAction, input: Input?) {
        let generation = generation
        let previousInput = input.flatMap { inputTasks[$0] }
        let previousSystem = action.systemAction != nil ? systemTask : nil
        // OS操作の順序と、同じ入力の押下・解放の順序をそれぞれ保持する。
        // 解放側のキーは、別の入力のOS操作を待たない。
        let task = Task { @MainActor [weak self] in
            await previousSystem?.value
            await previousInput?.value
            guard let self, !Task.isCancelled, generation == self.generation, !isSuspended() else { return }
            do {
                if let systemAction = action.systemAction {
                    try await executor.execute(systemAction)
                } else {
                    try sender.send(action)
                }
                guard !Task.isCancelled, generation == self.generation else { return }
                preferences.actionError = nil
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                preferences.reportActionError(for: action, error: error)
                let message = preferences.actionError ?? error.localizedDescription
                Logger.keyMonitor.error("\(message, privacy: .public)")
                onError(error)
            }
        }
        if action.systemAction != nil { systemTask = task }
        if let input { inputTasks[input] = task }
    }
}
