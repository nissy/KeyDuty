import Foundation
import os

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.nissy.KeyDuty"

    static let keyMonitor = os.Logger(subsystem: subsystem, category: "key-monitor")
    static let keySender = os.Logger(subsystem: subsystem, category: "key-sender")
    static let permissions = os.Logger(subsystem: subsystem, category: "permissions")
}
