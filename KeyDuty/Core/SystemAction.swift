import Foundation

enum SystemAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case displayOff
    case lockScreen
    case sleep
    case startScreensaver
    case mediaPlay
    case mediaPause

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .displayOff: L10n.text("action.displayOff")
        case .lockScreen: L10n.text("action.lock")
        case .sleep: L10n.text("action.sleep")
        case .startScreensaver: L10n.text("action.screensaver")
        case .mediaPlay: L10n.text("action.play")
        case .mediaPause: L10n.text("action.pause")
        }
    }

    var symbol: String {
        switch self {
        case .displayOff: "display"
        case .lockScreen: "lock"
        case .sleep: "moon"
        case .startScreensaver: "sparkles.tv"
        case .mediaPlay: "play.fill"
        case .mediaPause: "pause.fill"
        }
    }

    // MediaRemote の独立した命令。TogglePlayPause (2) は使わない。
    var mediaCommand: UInt32? {
        switch self {
        case .mediaPlay: 0
        case .mediaPause: 1
        default: nil
        }
    }
}
