import Foundation

enum L10n {
    static func bundle(in defaults: UserDefaults = .standard) -> Bundle {
        AppLanguage.saved(in: defaults).bundle
    }

    static func text(_ key: String, bundle: Bundle? = nil, _ arguments: CVarArg...) -> String {
        let bundle = bundle ?? self.bundle()
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        let locale = Locale(identifier: bundle.preferredLocalizations.first ?? "en")
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static let searchBundles: [Bundle] = ["en", "ja"].compactMap { language in
        Bundle.main.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:))
    }

    // Key searches accept both languages, regardless of the display language.
    static func searchNames(for key: String) -> [String] {
        searchBundles.map { $0.localizedString(forKey: key, value: key, table: nil) }
    }
}
