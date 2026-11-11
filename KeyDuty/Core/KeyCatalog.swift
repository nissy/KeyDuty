import CoreGraphics
import Foundation

enum KeyCatalog {
    struct Key: Identifiable, Sendable {
        let id: CGKeyCode
        private let nameKey: String
        var name: String { L10n.text(nameKey) }
        let aliases: [String]

        init(_ id: CGKeyCode, _ name: String, aliases: [String] = []) {
            self.id = id
            nameKey = name
            self.aliases = aliases + L10n.searchNames(for: name)
        }

        func matches(_ query: String) -> Bool {
            let normalized = Self.normalize(query)
            return normalized.isEmpty || String(id) == normalized ||
                ([name] + aliases).contains { Self.normalize($0).contains(normalized) }
        }

        private static func normalize(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
                .filter { !$0.isWhitespace }
        }
    }

    struct Group: Identifiable, Sendable {
        let id: String
        let keys: [Key]
        var name: String { L10n.text(id) }
    }

    static let groups: [Group] = [
        Group(id: "group.characters", keys: [
            Key(0, "A"), Key(11, "B"), Key(8, "C"), Key(2, "D"), Key(14, "E"),
            Key(3, "F"), Key(5, "G"), Key(4, "H"), Key(34, "I"), Key(38, "J"),
            Key(40, "K"), Key(37, "L"), Key(46, "M"), Key(45, "N"), Key(31, "O"),
            Key(35, "P"), Key(12, "Q"), Key(15, "R"), Key(1, "S"), Key(17, "T"),
            Key(32, "U"), Key(9, "V"), Key(13, "W"), Key(7, "X"), Key(16, "Y"), Key(6, "Z")
        ]),
        Group(id: "group.symbols", keys: [
            Key(29, "0"), Key(18, "1"), Key(19, "2"), Key(20, "3"), Key(21, "4"),
            Key(23, "5"), Key(22, "6"), Key(26, "7"), Key(28, "8"), Key(25, "9"),
            Key(27, "-"), Key(24, "key.equal", aliases: ["キャレット"]),
            Key(33, "key.leftBracket", aliases: ["アットマーク"]),
            Key(30, "key.rightBracket"), Key(42, "key.backslash", aliases: ["バックスラッシュ"]),
            Key(41, ";", aliases: ["セミコロン"]), Key(39, "key.quote", aliases: ["コロン"]),
            Key(43, ","), Key(47, "."), Key(44, "/", aliases: ["スラッシュ"])
        ]),
        Group(id: "group.navigation", keys: [
            Key(36, "Return", aliases: ["Enter", "エンター"]), Key(48, "Tab", aliases: ["タブ"]),
            Key(49, "Space", aliases: ["スペース"]), Key(53, "Escape", aliases: ["Esc", "エスケープ"]),
            Key(51, "key.backspace", aliases: ["Backspace", "バックスペース"]), Key(117, "key.forwardDelete"),
            Key(123, "←"), Key(124, "→"), Key(125, "↓"), Key(126, "↑"),
            Key(115, "Home"), Key(119, "End"), Key(116, "Page Up"), Key(121, "Page Down"),
            Key(114, "Insert / Help", aliases: ["Ins", "挿入"]),
            Key(110, "key.menu", aliases: ["Menu", "Context Menu", "アプリケーション"])
        ]),
        Group(id: "group.japanese", keys: [
            Key(50, "key.hankaku", aliases: [
                "半角全角", "全角半角", "全角/半角", "半角・全角", "漢字", "バッククォート", "Backquote", "Grave", "~"
            ]),
            Key(102, "key.eisu", aliases: ["Eisu"]), Key(104, "key.kana", aliases: ["Kana", "カナ"]),
            Key(93, "key.yen", aliases: ["円マーク", "Yen", "￥"]),
            Key(94, "key.underscore", aliases: ["アンダースコア", "Underscore"]),
            Key(10, "key.iso")
        ]),
        Group(id: "group.function", keys: [
            Key(122, "F1"), Key(120, "F2"), Key(99, "F3"), Key(118, "F4"),
            Key(96, "F5"), Key(97, "F6"), Key(98, "F7"), Key(100, "F8"),
            Key(101, "F9"), Key(109, "F10"), Key(103, "F11"), Key(111, "F12"),
            Key(105, "F13 / Print Screen", aliases: ["PrintScreen", "PrtSc", "プリントスクリーン"]),
            Key(107, "F14 / Scroll Lock", aliases: ["ScrollLock", "ScrLk", "スクロールロック"]),
            Key(113, "F15 / Pause", aliases: ["Break", "ポーズ"]), Key(106, "F16"),
            Key(64, "F17"), Key(79, "F18"), Key(80, "F19"), Key(90, "F20")
        ]),
        Group(id: "group.keypad", keys: [
            Key(82, "key.keypad.0"), Key(83, "key.keypad.1"), Key(84, "key.keypad.2"),
            Key(85, "key.keypad.3"), Key(86, "key.keypad.4"), Key(87, "key.keypad.5"),
            Key(88, "key.keypad.6"), Key(89, "key.keypad.7"), Key(91, "key.keypad.8"), Key(92, "key.keypad.9"),
            Key(65, "key.keypad.10"), Key(95, "key.keypad.comma"), Key(67, "key.keypad.11"),
            Key(69, "key.keypad.12"), Key(75, "key.keypad.13"), Key(78, "key.keypad.14"),
            Key(81, "key.keypad.15"), Key(76, "key.keypad.16"),
            Key(71, "key.keypad.clear", aliases: ["NumLock", "NumLk", "ナムロック"])
        ])
    ]

    static let keys = groups.flatMap(\.keys)

    static let systemKeyGroup = Group(
        id: "group.system", keys: SystemKey.allCases.map(\.catalogKey)
    )

    static let inputGroups = [Group(id: "group.modifiers", keys: ModifierKey.allCases.map {
        Key($0.keyCode, $0.localizationKey, aliases: $0 == .function ? ["Function", "地球儀", "Globe"] : [])
    }), Group(id: "group.lock", keys: [Key(57, "Caps Lock", aliases: ["CapsLock", "キャプスロック"])])] +
        groups + [systemKeyGroup]

    static func name(for code: CGKeyCode) -> String {
        ModifierKey.from(keyCode: Int64(code))?.displayName ??
            (code == 57 ? "Caps Lock" : nil) ?? SystemKey.from(keyCode: code)?.catalogKey.name ??
            keys.first { $0.id == code }?.name ?? L10n.text("key.code", String(code))
    }

    static func symbol(for code: CGKeyCode) -> String? {
        guard let key = ModifierKey.from(keyCode: Int64(code)) else { return nil }
        switch key {
        case .leftCommand, .rightCommand: return "command"
        case .leftShift, .rightShift: return "shift"
        case .leftControl, .rightControl: return "control"
        case .leftOption, .rightOption: return "option"
        case .function: return "globe"
        }
    }
}
