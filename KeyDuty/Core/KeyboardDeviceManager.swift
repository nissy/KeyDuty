import CoreGraphics
import Combine
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

    private func configureManagerIfNeeded() {
        guard !isConfigured else { return }

        let matching = [
            kIOHIDDeviceUsagePageKey: NSNumber(value: kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey: NSNumber(value: kHIDUsage_GD_Keyboard)
        ] as NSDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        isConfigured = true
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

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let deviceManager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
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
