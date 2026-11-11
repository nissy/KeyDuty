import XCTest
@testable import KeyDuty

@MainActor
final class LanguageSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "LanguageSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultAndInvalidSelectionFollowSystem() {
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .system)
        defaults.set("unsupported", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .system)
        XCTAssertTrue(AppLanguage.system.bundle === Bundle.main)
    }

    func testEachSelectionPersistsAcrossLaunches() {
        let settings = LanguageSettings(defaults: defaults)
        for language in AppLanguage.allCases {
            settings.selection = language
            let relaunched = LanguageSettings(defaults: defaults)
            XCTAssertEqual(relaunched.selection, language)
        }
    }

    func testLanguageChangesArePublishedAfterSavingAndResolveImmediately() {
        let settings = LanguageSettings(defaults: defaults)
        var names: [String] = []
        let observation = settings.changes.sink { [self] language in
            XCTAssertEqual(AppLanguage.saved(in: defaults), language)
            names.append(L10n.text("key.eisu", bundle: L10n.bundle(in: defaults)))
        }
        settings.selection = .japanese
        settings.selection = .english
        settings.selection = .japanese
        XCTAssertEqual(names, ["英数", "Eisu", "英数"])
        settings.selection = .system
        XCTAssertTrue(L10n.bundle(in: defaults) === Bundle.main)
        withExtendedLifetime(observation) {}
    }

    func testSelectingTheSameLanguageDoesNotSendAChange() {
        let settings = LanguageSettings(defaults: defaults)
        var changes: [AppLanguage] = []
        let observation = settings.changes.sink { changes.append($0) }
        settings.selection = .system
        settings.selection = .english
        settings.selection = .english
        XCTAssertEqual(changes, [.english])
        withExtendedLifetime(observation) {}
    }

    func testLanguageSelectionKeepsOtherPreferencesAndSystemOverrides() {
        defaults.set(Data([1, 2, 3]), forKey: "keyAssignments")
        defaults.set(["ja", "en"], forKey: "AppleLanguages")
        let settings = LanguageSettings(defaults: defaults)
        settings.selection = .english
        settings.selection = .system
        XCTAssertEqual(defaults.data(forKey: "keyAssignments"), Data([1, 2, 3]))
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ja", "en"])
    }

    func testExplicitSelectionsResolveToTheChosenLanguage() {
        XCTAssertEqual(L10n.text("menu.settings", bundle: AppLanguage.english.bundle), "Settings…")
        XCTAssertEqual(L10n.text("menu.settings", bundle: AppLanguage.japanese.bundle), "設定…")

    }
}
