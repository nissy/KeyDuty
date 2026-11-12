import Foundation

enum TypingSound: String, CaseIterable, Identifiable {
    case kacha
    case koto
    case saku
    case piko
    case poko
    case kira

    var id: String { rawValue }
    var displayName: String { L10n.text("typingSound.\(rawValue)") }

    func resourceURL(deep: Bool) -> URL? {
        let suffix = deep ? "-deep" : ""
        return Bundle.main.url(forResource: "typing-\(rawValue)\(suffix)", withExtension: "wav")
    }
}
