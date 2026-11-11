import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case japanese = "ja"
    case english = "en"

    static let defaultsKey = "appLanguage"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.text("language.system")
        case .japanese: "日本語"
        case .english: "English"
        }
    }

    static func saved(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .system
    }

    var locale: Locale {
        Locale(identifier: bundle.preferredLocalizations.first ?? "en")
    }

    var bundle: Bundle {
        guard self != .system else { return .main }
        return Bundle.main.url(forResource: rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .main
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    private let defaults: UserDefaults
    let changes = PassthroughSubject<AppLanguage, Never>()

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: AppLanguage.defaultsKey)
            changes.send(selection)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = AppLanguage.saved(in: defaults)
        selection = saved
    }
}
