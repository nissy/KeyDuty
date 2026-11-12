import CoreGraphics
import Combine
import Darwin
import Foundation
import IOKit.hid

struct KeyboardDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let transport: String

    var detail: String {
        let identifiers = String(format: "VID %04X · PID %04X", vendorID, productID)
        return transport.isEmpty ? identifiers : "\(identifiers) · \(transport)"
    }
}

@MainActor
final class KeyboardDeviceManager: ObservableObject {
    static let shared = KeyboardDeviceManager()

    @Published private(set) var devices: [KeyboardDevice] = []
    @Published private var errorMessageProvider: (() -> String)?
    var errorMessage: String? { errorMessageProvider?() }
    let removals = PassthroughSubject<Void, Never>()
    let keyPresses = PassthroughSubject<Bool, Never>()

    private struct HeldKey: Hashable {
        let deviceID: ObjectIdentifier
        let usagePage: Int
        let usage: Int
    }

    private var heldKeys: Set<HeldKey> = []
    private var commandReleaseTimes: [HeldKey: TimeInterval] = [:]
    private static let languageTapWindow: TimeInterval = 0.01
    private static let hidSecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    private let manager: IOHIDManager
    private let sourceResolver: KeyboardEventSourceResolver
    private var isConfigured = false
    private var isStarted = false

    init(devices: [KeyboardDevice] = [], sourceResolver: KeyboardEventSourceResolver = KeyboardEventSourceResolver()) {
        self.devices = devices
        self.sourceResolver = sourceResolver
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        guard !isStarted else {
            refresh()
            return
        }
        guard CGPreflightListenEventAccess() else {
            errorMessageProvider = { L10n.text("error.identifyPermission") }
            return
        }
        configureManagerIfNeeded()

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            errorMessageProvider = { L10n.text("error.keyboardInfo", String(result)) }
            return
        }

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        isStarted = true
        errorMessageProvider = nil
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = false
        devices = []
        heldKeys.removeAll()
        commandReleaseTimes.removeAll()
        resetInputState()
    }

    func refresh() {
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as NSSet? else {
            devices = []
            resetInputState()
            return
        }

        let connected: [KeyboardDevice] = deviceSet.compactMap { object in
            guard CFGetTypeID(object as CFTypeRef) == IOHIDDeviceGetTypeID() else { return nil }
            let device = unsafeDowncast(object as AnyObject, to: IOHIDDevice.self)
            return descriptor(for: device)
        }

        var uniqueDevices: [String: KeyboardDevice] = [:]
        for descriptor in connected { uniqueDevices[descriptor.id] = descriptor }
        devices = uniqueDevices.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        resetInputState()
    }

    func origin(for event: CGEvent) -> KeyboardEventOrigin {
        sourceResolver.origin(for: event)
    }

    func resetInputState() {
        sourceResolver.reset()
    }

    // Only HID input values can trigger typing sounds. KeySender's Quartz events do not enter here.
    func receiveKeyInput(usagePage: Int, usage: Int, value: Int, deviceID: ObjectIdentifier,
                         timestamp: TimeInterval) {
        let isKeyboardKey = usagePage == kHIDPage_KeyboardOrKeypad && usage >= kHIDUsage_KeyboardA
        let isConsumerKey = usagePage == kHIDPage_Consumer && usage != 0
        let isFunctionKey = (usagePage == 0xff || usagePage == 0xff01) && usage == 0x03
        guard isKeyboardKey || isConsumerKey || isFunctionKey else { return }

        let key = HeldKey(deviceID: deviceID, usagePage: usagePage, usage: usage)
        if value == 0 {
            if heldKeys.remove(key) != nil, isKeyboardKey, let languageUsage = Self.languageUsage(for: usage) {
                // 一部のキーボードは、Commandの解放直後に英数／かなを別の押下として通知する。
                let languageKey = HeldKey(deviceID: deviceID, usagePage: usagePage, usage: languageUsage)
                commandReleaseTimes[languageKey] = timestamp
            }
            return
        }
        guard value == 1, heldKeys.insert(key).inserted else { return }
        if let releasedAt = commandReleaseTimes.removeValue(forKey: key),
           timestamp >= releasedAt, timestamp - releasedAt <= Self.languageTapWindow { return }

        let deep = isKeyboardKey && [kHIDUsage_KeyboardReturnOrEnter, kHIDUsage_KeyboardSpacebar,
                                     kHIDUsage_KeypadEnter].contains(usage)
        keyPresses.send(deep)
    }

    private static func languageUsage(for commandUsage: Int) -> Int? {
        switch commandUsage {
        case kHIDUsage_KeyboardLeftGUI: kHIDUsage_KeyboardLANG2 // Eisu
        case kHIDUsage_KeyboardRightGUI: kHIDUsage_KeyboardLANG1 // Kana
        default: nil
        }
    }

    private func configureManagerIfNeeded() {
        guard !isConfigured else { return }

        let matching = [
            kIOHIDDeviceUsagePageKey: NSNumber(value: kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey: NSNumber(value: kHIDUsage_GD_Keyboard)
        ] as NSDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueReceived, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        isConfigured = true
    }

    private static let inputValueReceived: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let deviceManager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let input = IOHIDValueGetIntegerValue(value)
        let deviceID = ObjectIdentifier(device)
        let ticks = IOHIDValueGetTimeStamp(value)
        MainActor.assumeIsolated {
            let timestamp = Double(ticks) * KeyboardDeviceManager.hidSecondsPerTick
            deviceManager.receiveKeyInput(usagePage: page, usage: usage, value: input,
                                          deviceID: deviceID, timestamp: timestamp)
        }
    }

    private static let deviceChanged: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let deviceManager = Unmanaged<KeyboardDeviceManager>
            .fromOpaque(context)
            .takeUnretainedValue()
        MainActor.assumeIsolated {
            deviceManager.refresh()
        }
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let deviceManager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()
        let deviceID = ObjectIdentifier(device)
        MainActor.assumeIsolated {
            deviceManager.heldKeys = deviceManager.heldKeys.filter { $0.deviceID != deviceID }
            deviceManager.commandReleaseTimes = deviceManager.commandReleaseTimes.filter { $0.key.deviceID != deviceID }
            deviceManager.refresh()
            deviceManager.removals.send()
        }
    }

    private func descriptor(for device: IOHIDDevice) -> KeyboardDevice? {
        guard let vendorID = integerProperty(kIOHIDVendorIDKey, device: device),
              let productID = integerProperty(kIOHIDProductIDKey, device: device)
        else {
            return nil
        }

        let rawName = stringProperty(kIOHIDProductKey, device: device) ?? L10n.text("keyboards.unknown")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = stringProperty(kIOHIDTransportKey, device: device) ?? ""
        let id = String(format: "%04X:%04X", vendorID, productID)

        return KeyboardDevice(
            id: id,
            name: name.isEmpty ? L10n.text("keyboards.unknown") : name,
            vendorID: vendorID,
            productID: productID,
            transport: transport
        )
    }

    private func integerProperty(_ key: String, device: IOHIDDevice) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
