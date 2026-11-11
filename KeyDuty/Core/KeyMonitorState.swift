import Foundation

struct MonitorSuspensionState {
    enum Reason: Hashable {
        case systemSleep
        case screenLock
        case secureInput
    }

    private(set) var activeReasons: Set<Reason> = []

    var isSuspended: Bool { !activeReasons.isEmpty }

    @discardableResult
    mutating func set(_ reason: Reason, active: Bool) -> Bool {
        if active { return activeReasons.insert(reason).inserted }
        return activeReasons.remove(reason) != nil
    }
}

enum KeyMonitorError: LocalizedError {
    case eventTapCreationFailed
    case listenAccessDenied

    var errorDescription: String? {
        switch self {
        case .eventTapCreationFailed:
            L10n.text("error.monitor")
        case .listenAccessDenied:
            L10n.text("error.listenRevoked")
        }
    }
}
