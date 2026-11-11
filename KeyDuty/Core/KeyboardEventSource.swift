import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

struct KeyboardEventOrigin: Equatable {
    let senderID: UInt64
    let keyboardID: String?
}

@MainActor
final class KeyboardEventSourceResolver {
    private let lookup: (UInt64) -> String?
    private var cache: [UInt64: String] = [:]

    init(lookup: @escaping (UInt64) -> String? = KeyboardEventSourceResolver.keyboardID) {
        self.lookup = lookup
    }

    func origin(for event: CGEvent) -> KeyboardEventOrigin {
        // 非公開の送信元IORegistry ID。OS変更や合成イベントで欠落する場合は識別不明として扱う。
        // 参考: mac-mouse-fix/Helper/Utility/EventUtility.m の CGEventGetSendingDevice。
        guard let field = CGEventField(rawValue: 87) else {
            return KeyboardEventOrigin(senderID: 0, keyboardID: nil)
        }
        let senderID = UInt64(bitPattern: event.getIntegerValueField(field))
        guard senderID != 0 else { return KeyboardEventOrigin(senderID: 0, keyboardID: nil) }
        let keyboardID = cache[senderID] ?? lookup(senderID)
        if let keyboardID { cache[senderID] = keyboardID }
        return KeyboardEventOrigin(senderID: senderID, keyboardID: keyboardID)
    }

    func reset() { cache.removeAll() }

    nonisolated private static func keyboardID(for senderID: UInt64) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(senderID))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        func property(_ key: String) -> Int? {
            let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options
            ) as? NSNumber
            return value?.intValue
        }
        guard let vendor = property(kIOHIDVendorIDKey), let product = property(kIOHIDProductIDKey) else { return nil }
        return String(format: "%04X:%04X", vendor, product)
    }
}
