import AppKit

// NX_KEYTYPE_*。通常の仮想キーと衝突しないIDを設定のsourceKeyCodeに保存する。
// 音量3キーは既存のmacOS仮想キーコードと同じIDに正規化する。
enum SystemKey: Int, CaseIterable, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case contrastUp = 11
    case contrastDown = 12
    case eject = 14
    case displayMirror = 15
    case playPause = 16
    case next = 17
    case previous = 18
    case fastForward = 19
    case rewind = 20
    case illuminationUp = 21
    case illuminationDown = 22
    case illuminationToggle = 23

    var keyCode: CGKeyCode {
        switch self {
        case .volumeUp: 72
        case .volumeDown: 73
        case .mute: 74
        default: CGKeyCode(0x1000 + rawValue)
        }
    }

    static func from(keyCode: CGKeyCode) -> Self? {
        allCases.first { $0.keyCode == keyCode }
    }

    var catalogKey: KeyCatalog.Key {
        switch self {
        case .volumeUp: .init(keyCode, "key.volumeUp", aliases: ["Volume Up", "音量＋"])
        case .volumeDown: .init(keyCode, "key.volumeDown", aliases: ["Volume Down", "音量−"])
        case .mute: .init(keyCode, "key.mute", aliases: ["Mute", "消音"])
        case .brightnessUp: .init(keyCode, "key.brightnessUp", aliases: ["Brightness Up", "輝度", "明るさ"])
        case .brightnessDown: .init(keyCode, "key.brightnessDown", aliases: ["Brightness Down", "輝度", "明るさ"])
        case .contrastUp: .init(keyCode, "key.contrastUp", aliases: ["Contrast Up"])
        case .contrastDown: .init(keyCode, "key.contrastDown", aliases: ["Contrast Down"])
        case .eject: .init(keyCode, "key.eject", aliases: ["Eject", "イジェクト", "⏏"])
        case .displayMirror: .init(keyCode, "key.mirror", aliases: ["Video Mirror"])
        case .playPause: .init(keyCode, "key.playPause", aliases: ["Play", "Pause", "メディア"])
        case .next: .init(keyCode, "key.next", aliases: ["Next", "曲送り", "メディア"])
        case .previous: .init(keyCode, "key.previous", aliases: ["Previous", "曲戻し", "メディア"])
        case .fastForward: .init(keyCode, "key.fastForward", aliases: ["Fast Forward", "メディア"])
        case .rewind: .init(keyCode, "key.rewind", aliases: ["Rewind", "メディア"])
        case .illuminationUp: .init(keyCode, "key.illuminationUp", aliases: ["Illumination Up", "バックライト"])
        case .illuminationDown: .init(keyCode, "key.illuminationDown", aliases: ["Illumination Down", "バックライト"])
        case .illuminationToggle: .init(keyCode, "key.illuminationToggle", aliases: ["Illumination Toggle", "バックライト"])
        }
    }
}

struct SystemKeyInput {
    static let eventType = CGEventType(rawValue: 14)!
    let keyCode: CGKeyCode
    let isKeyDown: Bool
    let isRepeat: Bool

    init?(_ event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let data = UInt32(truncatingIfNeeded: event.data1)
        let rawKey = Int(data >> 16)
        let state = (data >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        if let key = SystemKey(rawValue: rawKey) {
            keyCode = key.keyCode
        } else if rawKey == 5 || rawKey == 10 {
            keyCode = rawKey == 5 ? 114 : 71 // Help / Num Lock
        } else {
            return nil
        }
        isKeyDown = state == 0x0a
        isRepeat = data & 1 != 0
    }

    // 既存の押下・リピート・解放処理を共用する。未割り当てなら元イベントを返す。
    static func normalizedEvent(_ event: CGEvent) throws -> CGEvent? {
        guard event.type == eventType, let cocoaEvent = NSEvent(cgEvent: event),
              let input = Self(cocoaEvent) else { return nil }
        guard let normalized = CGEvent(
            keyboardEventSource: CGEventSource(event: event), virtualKey: input.keyCode, keyDown: input.isKeyDown
        ) else { throw KeySenderError.eventCreationFailed }
        normalized.flags = event.flags
        normalized.timestamp = event.timestamp
        normalized.setIntegerValueField(.keyboardEventAutorepeat, value: input.isRepeat ? 1 : 0)
        normalized.setIntegerValueField(.eventSourceUserData, value: event.getIntegerValueField(.eventSourceUserData))
        return normalized
    }
}

struct RecordedKeyPress {
    let keyCode: CGKeyCode
    let isKeyDown: Bool
    let isRepeat: Bool

    init?(_ event: NSEvent) {
        if event.type == .keyDown || event.type == .keyUp {
            keyCode = event.keyCode
            isKeyDown = event.type == .keyDown
            isRepeat = event.type == .keyDown && event.isARepeat
        } else if let input = SystemKeyInput(event) {
            keyCode = input.keyCode
            isKeyDown = input.isKeyDown
            isRepeat = input.isRepeat
        } else {
            return nil
        }
    }
}
