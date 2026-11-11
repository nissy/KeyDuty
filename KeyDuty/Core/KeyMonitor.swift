@preconcurrency import CoreGraphics
import AppKit
import Carbon
import Combine
import Foundation

@MainActor
final class KeyMonitor: NSObject {
    typealias ErrorHandler = @MainActor (Error) -> Void
    typealias StatusHandler = @MainActor (Bool) -> Void
    private static let eventMask: CGEventMask = [
        CGEventType.flagsChanged,
        .keyDown,
        .keyUp,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .scrollWheel,
        SystemKeyInput.eventType
    ].reduce(CGEventMask(0)) { result, type in
        result | (CGEventMask(1) << type.rawValue)
    }

    private let preferences: Preferences
    private let sender: KeySender
    private let actionExecutor: any SystemActionExecuting
    private let keyboardDeviceManager: KeyboardDeviceManager
    private let isSecureInputEnabled: () -> Bool
    private let currentModifierFlags: () -> CGEventFlags
    private let now: () -> TimeInterval
    private let onError: ErrorHandler
    private let onStatusChange: StatusHandler

    private var stateMachine = DeviceModifierState()
    private var keyRemapper = DeviceKeyRemapper()
    private var functionKeyState = FunctionKeyState()
    private var capsLockEnabled: Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startupSuppressedMasks: CGEventFlags = []
    private var healthTimer: Timer?
    private var idleTimer: Timer?
    private var lastKeyPressAt: TimeInterval?
    private var keyPressTracker = KeyPressTracker()
    private var hasIdleFired = false
    private var suspensionState = MonitorSuspensionState()
    private var wasSecureInput = false
    private var recordingObservation: AnyCancellable?
    private var deviceRemovalObservation: AnyCancellable?
    private lazy var actionQueue = KeyActionQueue(
        sender: sender, executor: actionExecutor, preferences: preferences,
        isSuspended: { [weak self] in self?.isInputSuspended ?? true }, onError: onError
    )

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    // suspensionState の secureInput は5秒間隔のポーリング更新のため、
    // 検出遅延を直接チェックで補う
    private var isInputSuspended: Bool {
        preferences.isRecordingKey || suspensionState.isSuspended || isSecureInputEnabled()
    }

    init(
        preferences: Preferences,
        sender: KeySender,
        actionExecutor: any SystemActionExecuting = SystemActionExecutor(),
        keyboardDeviceManager: KeyboardDeviceManager = .shared,
        isSecureInputEnabled: @escaping () -> Bool = { IsSecureEventInputEnabled() },
        currentModifierFlags: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onError: @escaping ErrorHandler = { _ in },
        onStatusChange: @escaping StatusHandler = { _ in }
    ) {
        self.preferences = preferences
        self.sender = sender
        self.actionExecutor = actionExecutor
        self.keyboardDeviceManager = keyboardDeviceManager
        self.isSecureInputEnabled = isSecureInputEnabled
        self.currentModifierFlags = currentModifierFlags
        self.now = now
        capsLockEnabled = currentModifierFlags().contains(.maskAlphaShift)
        self.onError = onError
        self.onStatusChange = onStatusChange
        super.init()
        keyPressTracker.reset(flags: currentModifierFlags())
        registerLifecycleObservers()
        recordingObservation = preferences.$isRecordingKey.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.resetState()
        }
        deviceRemovalObservation = keyboardDeviceManager.removals.sink { [weak self] in
            // 切断した実キーの解放が届かない場合も、変換先の押下状態を残さない。
            self?.resetState(preservingOriginalKeys: false)
        }
    }

    func start() {
        guard eventTap == nil else { return }
        stateMachine.reset()
        keyboardDeviceManager.resetInputState()
        updateStartupSuppression()
        lastKeyPressAt = nil
        hasIdleFired = false
        wasSecureInput = isSecureInputEnabled()
        suspensionState.set(.secureInput, active: wasSecureInput)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                guard let output = monitor.handle(type: type, event: event) else { return nil }
                return output === event ? Unmanaged.passUnretained(event) : Unmanaged.passRetained(output)
            }
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.keyMonitor.error("Failed to create CGEventTap")
            onStatusChange(false)
            onError(KeyMonitorError.eventTapCreationFailed)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        Logger.keyMonitor.info("CGEventTap started")
        onStatusChange(true)
        startTimers()
    }

    func stop() {
        releaseRemappedKeys()
        stateMachine.reset()
        keyboardDeviceManager.resetInputState()
        startupSuppressedMasks = []
        lastKeyPressAt = nil
        stopTimers()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    func resetState(preservingOriginalKeys: Bool = true) {
        releaseRemappedKeys(preservingOriginalKeys: preservingOriginalKeys)
        stateMachine.reset()
        keyboardDeviceManager.resetInputState()
        updateStartupSuppression()
    }

    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetState()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return event
        }

        guard !sender.isOwnEvent(event) else { return event }

        if keyPressTracker.isPress(
            type: type, event: event,
            senderID: type == .flagsChanged ? keyboardDeviceManager.origin(for: event).senderID : 0
        ) {
            lastKeyPressAt = now()
            hasIdleFired = false
        }

        if captureRecordedInput(type: type, event: event) { return nil }
        if isInputSuspended {
            resetState()
            capsLockEnabled = event.flags.contains(.maskAlphaShift)
            functionKeyState.update(event)
            return event
        }

        functionKeyState.update(event)
        return handleInput(type: type, event: event)
    }

    private func handleInput(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == SystemKeyInput.eventType {
            stateMachine.cancel()
            return remapKeyEvent(event)
        }

        switch type {
        case .flagsChanged:
            if event.getIntegerValueField(.keyboardEventKeycode) == 57 {
                handleCapsLock(event)
                return event
            }
            if handleFlagsChanged(event) { return nil }
        case .keyDown:
            stateMachine.cancel()
            return remapKeyEvent(event)
        case .keyUp:
            return remapKeyEvent(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            stateMachine.cancel()
        default:
            break
        }

        return event
    }

    private func remapKeyEvent(_ event: CGEvent) -> CGEvent? {
        do {
            let origin = keyboardDeviceManager.origin(for: event)
            let input = try SystemKeyInput.normalizedEvent(event) ?? event
            let source = CGKeyCode(exactly: input.getIntegerValueField(.keyboardEventKeycode))
            if origin.senderID == 0, input.type == .keyUp, let source,
               keyRemapper.hasKnownPress(source) {
                // 送信元が欠けた解放を別キーボードへ推測で結び付けず、未解放状態を取り消す。
                resetState(preservingOriginalKeys: false)
            }
            let result = try keyRemapper.remap(
                input, assignments: preferences.assignments(for: origin.keyboardID), origin: origin,
                modifiers: functionKeyState.modifiers(for: event)
            )
            sender.heldKeyCodes = keyRemapper.heldOutputKeyCodes
            if let action = result.action {
                let actionInput = source.flatMap { source in
                    result.isPressRelease ? KeyActionQueue.Input(senderID: origin.senderID, keyCode: source) : nil
                }
                try actionQueue.perform(action, triggeringEvent: event, input: actionInput)
            }
            return result.event === input ? event : result.event
        } catch {
            releaseRemappedKeys()
            onError(error)
            return event
        }
    }

    private func releaseRemappedKeys(preservingOriginalKeys: Bool = true) {
        actionQueue.cancel()
        let released = keyRemapper.reset(preservingOriginalKeys: preservingOriginalKeys)
        sender.heldKeyCodes = []
        for keyCode in released {
            do {
                try sender.release(keyCode: keyCode)
            } catch {
                onError(error)
            }
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let key = ModifierKey.from(keyCode: keyCode) else {
            stateMachine.cancel()
            return false
        }

        if startupSuppressedMasks.contains(key.flagMask) {
            if !event.flags.contains(key.flagMask) {
                startupSuppressedMasks.remove(key.flagMask)
            }
            return false
        }

        let origin = keyboardDeviceManager.origin(for: event)
        if origin.senderID == 0, stateMachine.hasKnownPress(key) {
            resetState(preservingOriginalKeys: false)
            return false
        }
        let result = stateMachine.handle(
            key, flags: event.flags, origin: origin, assignments: preferences.assignments(for: origin.keyboardID)
        )
        for action in result.actions {
            do {
                let actionInput = result.isPressRelease
                    ? KeyActionQueue.Input(senderID: origin.senderID, keyCode: key.keyCode) : nil
                try actionQueue.perform(action, triggeringEvent: event, input: actionInput)
            } catch {
                Logger.keyMonitor.error("Failed to send action: \(error.localizedDescription, privacy: .public)")
                onError(error)
            }
        }
        return result.suppressEvent
    }

    private func startTimers() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(checkEventTapHealth),
            userInfo: nil,
            repeats: true
        )

        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(checkIdleTimeout),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func checkEventTapHealth() {
        let secureInput = isSecureInputEnabled()
        if secureInput != wasSecureInput {
            wasSecureInput = secureInput
            updateSuspensionReason(.secureInput, active: secureInput)
        }

        guard let eventTap else { return }
        guard CGPreflightListenEventAccess() else {
            resetState()
            destroyEventTap()
            onError(KeyMonitorError.listenAccessDenied)
            return
        }
        guard !CGEvent.tapIsEnabled(tap: eventTap) else { return }

        resetState()
        CGEvent.tapEnable(tap: eventTap, enable: true)
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            Logger.keyMonitor.warning("CGEventTap re-enable failed; recreating")
            recreateEventTap()
        }
    }

    @objc
    func checkIdleTimeout() {
        guard preferences.idleEnabled,
              !hasIdleFired,
              !isInputSuspended,
              let lastKeyPressAt,
              now() - lastKeyPressAt >= preferences.idleTimeoutSeconds
        else { return }

        // 送信失敗時も再試行しない（次のキー押下でリセットされるまで1回のみ）
        hasIdleFired = true
        do {
            try sender.send(preferences.idleAction)
        } catch {
            onError(error)
        }
    }

    private func recreateEventTap() {
        destroyEventTap()
        stateMachine.reset()
        start()
    }

    private func stopTimers() {
        healthTimer?.invalidate()
        healthTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func destroyEventTap() {
        stopTimers()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        onStatusChange(false)
    }
}

extension KeyMonitor {
    private func captureRecordedInput(type: CGEventType, event: CGEvent) -> Bool {
        guard preferences.isRecordingKey, !suspensionState.isSuspended, !isSecureInputEnabled(),
              [.keyDown, .keyUp, .flagsChanged, SystemKeyInput.eventType].contains(type),
              let handler = preferences.recordingHandler, let input = NSEvent(cgEvent: event) else { return false }
        // 音量キーなどはアプリに届く前にOSが処理するため、イベントタップから記録へ渡す。
        return handler(input)
    }

    private func updateStartupSuppression() {
        startupSuppressedMasks = []
        let currentFlags = currentModifierFlags()
        keyPressTracker.reset(flags: currentFlags)
        functionKeyState.isPressed = currentFlags.contains(.maskSecondaryFn)
        capsLockEnabled = currentFlags.contains(.maskAlphaShift)
        for key in ModifierKey.allCases where currentFlags.contains(key.flagMask) {
            startupSuppressedMasks.insert(key.flagMask)
        }
    }

    private func handleCapsLock(_ event: CGEvent) {
        stateMachine.cancel()
        let enabled = event.flags.contains(.maskAlphaShift)
        guard enabled != capsLockEnabled else { return }
        capsLockEnabled = enabled
        let origin = keyboardDeviceManager.origin(for: event)
        guard let action = preferences.assignments(for: origin.keyboardID).first(where: {
            $0.sourceKeyCode == 57 && $0.sourceModifiers.isEmpty
        })?.action else { return }
        do {
            try actionQueue.perform(action, triggeringEvent: event)
        } catch {
            onError(error)
        }
    }

    private func registerLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(suspendForSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(resumeFromSystemSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(suspendForScreenLock),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(resumeFromScreenLock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc
    private func suspendForSystemSleep() {
        updateSuspensionReason(.systemSleep, active: true)
    }

    @objc
    private func resumeFromSystemSleep() {
        updateSuspensionReason(.systemSleep, active: false)
    }

    @objc
    private func suspendForScreenLock() {
        updateSuspensionReason(.screenLock, active: true)
    }

    @objc
    private func resumeFromScreenLock() {
        updateSuspensionReason(.screenLock, active: false)
    }

    private func updateSuspensionReason(_ reason: MonitorSuspensionState.Reason, active: Bool) {
        guard suspensionState.set(reason, active: active) else { return }
        resetState()
        lastKeyPressAt = nil
        hasIdleFired = false
    }
}
