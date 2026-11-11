import AppKit
import IOKit.pwr_mgt

@MainActor
protocol SystemActionExecuting {
    func execute(_ action: SystemAction) async throws
}

enum SystemActionError: LocalizedError {
    case unavailable
    case rejected
    case commandFailed(Int32)
    case powerFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.text("error.systemUnavailable")
        case .rejected:
            L10n.text("error.systemRejected")
        case let .commandFailed(status):
            L10n.text("error.displayOff", String(status))
        case let .powerFailed(status):
            L10n.text("error.sleep", String(status))
        }
    }
}

@MainActor
final class SystemActionExecutor: SystemActionExecuting {
    private typealias LockScreenFunction = @convention(c) () -> Void
    private typealias MediaCommandFunction = @convention(c) (UInt32, CFDictionary?) -> UInt8

    // 非公開APIは実行時に解決する。OS更新で利用できなくなった場合はエラーを返す。
    // CFBundleを保持し、取得した関数の利用中にフレームワークが解放されないようにする。
    private lazy var loginFramework = Self.framework(named: "login")
    private lazy var mediaFramework = Self.framework(named: "MediaRemote")

    func execute(_ action: SystemAction) async throws {
        switch action {
        case .displayOff:
            try await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["displaysleepnow"]
                try process.run()
                process.waitUntilExit()
                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    throw SystemActionError.commandFailed(process.terminationStatus)
                }
            }.value
        case .lockScreen:
            let lock = try function(
                in: loginFramework, named: "SACLockScreenImmediate", as: LockScreenFunction.self
            )
            lock()
        case .sleep:
            try await Task.detached(priority: .userInitiated) {
                let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
                guard port != IO_OBJECT_NULL else { throw SystemActionError.unavailable }
                defer { IOServiceClose(port) }
                let result = IOPMSleepSystem(port)
                guard result == kIOReturnSuccess else { throw SystemActionError.powerFailed(result) }
            }.value
        case .startScreensaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .mediaPlay, .mediaPause:
            guard let command = action.mediaCommand else { throw SystemActionError.unavailable }
            let send = try function(
                in: mediaFramework, named: "MRMediaRemoteSendCommand", as: MediaCommandFunction.self
            )
            guard send(command, nil) != 0 else { throw SystemActionError.rejected }
        }
    }

    private static func framework(named name: String) -> CFBundle? {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/\(name).framework")
        return CFBundleCreate(kCFAllocatorDefault, url as CFURL)
    }

    private func function<Function>(
        in bundle: CFBundle?, named name: String, as type: Function.Type
    ) throws -> Function {
        guard let bundle, let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
            throw SystemActionError.unavailable
        }
        return unsafeBitCast(pointer, to: type)
    }
}
