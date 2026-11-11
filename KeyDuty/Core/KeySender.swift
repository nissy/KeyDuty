import CoreGraphics
import Foundation

enum KeySenderError: LocalizedError, Equatable {
    case eventSourceCreationFailed
    case eventCreationFailed
    case postAccessDenied
    case modifierKeyNotAllowed(CGKeyCode)
    case systemActionNotSupported
    case inputOnlyKey(CGKeyCode)

    var errorDescription: String? {
        switch self {
        case .eventSourceCreationFailed:
            L10n.text("error.eventSource")
        case .eventCreationFailed:
            L10n.text("error.event")
        case .postAccessDenied:
            L10n.text("error.postDenied")
        case let .modifierKeyNotAllowed(keyCode):
            L10n.text("error.modifierOutput", String(keyCode))
        case .systemActionNotSupported:
            L10n.text("error.systemAsKey")
        case let .inputOnlyKey(keyCode):
            L10n.text("error.inputOnly", KeyCatalog.name(for: keyCode))
        }
    }
}

struct KeyEventRequest: Equatable, Sendable {
    let keyCode: CGKeyCode
    let isKeyDown: Bool
    let userData: Int64
    let preservesModifiers: Bool

    init(keyCode: CGKeyCode, isKeyDown: Bool, userData: Int64, preservesModifiers: Bool = false) {
        self.keyCode = keyCode
        self.isKeyDown = isKeyDown
        self.userData = userData
        self.preservesModifiers = preservesModifiers
    }
}

protocol KeyEventPosting: AnyObject {
    func post(_ request: KeyEventRequest, source: CGEventSource) throws
}

final class CGEventPoster: KeyEventPosting {
    func post(_ request: KeyEventRequest, source: CGEventSource) throws {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: request.keyCode,
            keyDown: request.isKeyDown
        ) else {
            throw KeySenderError.eventCreationFailed
        }

        if !request.preservesModifiers {
            event.flags = event.flags.subtracting(KeySender.modifierBits)
        }
        event.setIntegerValueField(.eventSourceUserData, value: request.userData)
        event.post(tap: .cghidEventTap)
    }
}

final class KeySender {
    struct EventMetadata: Equatable, Sendable {
        let userData: Int64
    }

    static let modifierBits: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskControl,
        .maskAlternate,
        .maskSecondaryFn
    ]

    let sessionToken: Int64

    /// 置き換えで押下を保持している出力キー。KeyMonitorが入力処理ごとに更新する。
    var heldKeyCodes: Set<CGKeyCode> = []

    private let fallbackSource: CGEventSource
    private let poster: KeyEventPosting
    private let canPostEvents: () -> Bool

    init(
        poster: KeyEventPosting = CGEventPoster(),
        fallbackSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState),
        sessionToken: Int64 = Int64.random(in: 1 ... Int64.max),
        canPostEvents: @escaping () -> Bool = { CGPreflightPostEventAccess() }
    ) throws {
        guard let fallbackSource else { throw KeySenderError.eventSourceCreationFailed }
        self.poster = poster
        self.fallbackSource = fallbackSource
        self.sessionToken = sessionToken
        self.canPostEvents = canPostEvents
    }

    func send(_ action: KeyAction, triggeringEvent: CGEvent? = nil) throws {
        switch action {
        case .none:
            return
        case let .sendKey(keyCode):
            try send(keyCode: keyCode, triggeringEvent: triggeringEvent)
        case .system:
            throw KeySenderError.systemActionNotSupported
        }
    }

    func send(keyCode: CGKeyCode, triggeringEvent: CGEvent? = nil) throws {
        guard canPostEvents() else {
            Logger.keySender.error("Key event post access is denied")
            throw KeySenderError.postAccessDenied
        }
        guard !ModifierKey.isModifierKeyCode(keyCode) else {
            throw KeySenderError.modifierKeyNotAllowed(keyCode)
        }
        guard SystemKey.from(keyCode: keyCode) == nil else { throw KeySenderError.inputOnlyKey(keyCode) }

        Logger.keySender.info("Sending key code \(keyCode, privacy: .public)")
        let source = triggeringEvent.flatMap(CGEventSource.init(event:)) ?? fallbackSource

        try poster.post(
            KeyEventRequest(keyCode: keyCode, isKeyDown: true, userData: sessionToken),
            source: source
        )
        // 保持中のキーへ解放を送ると、物理キーを離す前に受信側で保持が解除される。
        // 押下だけを送り、解放は保持している入力を離したときの1回に任せる。
        guard !heldKeyCodes.contains(keyCode) else {
            Logger.keySender.info("Skipping key up for held key code \(keyCode, privacy: .public)")
            return
        }
        try poster.post(
            KeyEventRequest(keyCode: keyCode, isKeyDown: false, userData: sessionToken),
            source: source
        )
    }

    func isOwnEvent(_ event: CGEvent) -> Bool {
        isOwnEvent(
            EventMetadata(
                userData: event.getIntegerValueField(.eventSourceUserData)
            )
        )
    }

    func release(keyCode: CGKeyCode) throws {
        guard canPostEvents() else { throw KeySenderError.postAccessDenied }
        guard !ModifierKey.isModifierKeyCode(keyCode) else {
            throw KeySenderError.modifierKeyNotAllowed(keyCode)
        }
        guard SystemKey.from(keyCode: keyCode) == nil else { throw KeySenderError.inputOnlyKey(keyCode) }
        try poster.post(
            KeyEventRequest(
                keyCode: keyCode,
                isKeyDown: false,
                userData: sessionToken,
                preservesModifiers: true
            ),
            source: fallbackSource
        )
    }

    func isOwnEvent(_ metadata: EventMetadata) -> Bool {
        metadata.userData == sessionToken
    }
}
