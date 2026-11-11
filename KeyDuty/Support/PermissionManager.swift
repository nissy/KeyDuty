import Combine
import CoreGraphics

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var canListen = false
    @Published private(set) var canPost = false

    init() {
        refresh()
    }

    func refresh() {
        canListen = CGPreflightListenEventAccess()
        canPost = CGPreflightPostEventAccess()
        Logger.permissions.debug(
            "Listen=\(self.canListen, privacy: .public) Post=\(self.canPost, privacy: .public)"
        )
    }

    func requestListenAccess() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    func requestPostAccess() {
        _ = CGRequestPostEventAccess()
        refresh()
    }

    func requestMissingAccess() {
        refresh()
        if !canListen {
            requestListenAccess()
            return
        }
        if !canPost {
            requestPostAccess()
        }
    }

    var isReady: Bool {
        canListen && canPost
    }
}
