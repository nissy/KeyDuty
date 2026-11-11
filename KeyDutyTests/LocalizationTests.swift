import CoreGraphics
import XCTest
@testable import KeyDuty

final class LocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    private func translations(_ language: String) throws -> [String: String] {
        let bundle = try languageBundle(language)
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testBothLanguagesArePackagedWithMatchingKeysAndFormatArguments() throws {
        XCTAssertEqual(Set(Bundle.main.localizations), Set(["en", "ja"]))
        let english = try translations("en")
        let japanese = try translations("ja")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        let format = try NSRegularExpression(pattern: "%(?:[0-9]+\\$)?(?:@|ld)")
        func placeholders(_ string: String) -> [String] {
            format.matches(in: string, range: NSRange(string.startIndex..., in: string)).map {
                String(string[Range($0.range, in: string)!])
            }.sorted()
        }
        for (key, value) in english {
            let translated = try XCTUnwrap(japanese[key])
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(placeholders(value), placeholders(translated), key)
        }
    }

    func testEnglishMenusKeysAndFormattedMessages() throws {
        let bundle = try languageBundle("en")
        XCTAssertEqual(L10n.text("menu.settings", bundle: bundle), "Settings…")
        XCTAssertEqual(L10n.text("key.leftCommand", bundle: bundle), "Left Command")
        XCTAssertEqual(L10n.text("key.eisu", bundle: bundle), "Eisu")
        XCTAssertEqual(L10n.text("assignments.count", bundle: bundle, 2), "Assignments: 2")
        XCTAssertEqual(L10n.text("error.action", bundle: bundle, "Play media", "Unavailable"),
                       "Could not run “Play media”. Unavailable")
        XCTAssertEqual(L10n.text("keyboards.splitSummary", bundle: bundle, "Eisu", "Kana"),
                       "On press: Eisu\nOn release: Kana")
    }

    func testJapaneseMenusKeysAndFormattedMessages() throws {
        let bundle = try languageBundle("ja")
        XCTAssertEqual(L10n.text("menu.settings", bundle: bundle), "設定…")
        XCTAssertEqual(L10n.text("key.leftCommand", bundle: bundle), "左 Command")
        XCTAssertEqual(L10n.text("key.eisu", bundle: bundle), "英数")
        XCTAssertEqual(L10n.text("assignments.count", bundle: bundle, 2), "2件")
        XCTAssertEqual(L10n.text("error.action", bundle: bundle, "再生", "利用不可"),
                       "「再生」を実行できませんでした。利用不可")
        XCTAssertEqual(L10n.text("keyboards.splitSummary", bundle: bundle, "英数", "かな"),
                       "押したとき：英数\n離したとき：かな")
    }

    func testKeySearchAcceptsBothLanguagesInEitherDisplayLanguage() {
        let inputs = KeyCatalog.inputGroups.flatMap(\.keys)
        for (code, queries): (CGKeyCode, [String]) in [
            (55, ["Left Command", "左 Command"]),
            (102, ["Eisu", "英数"]),
            (104, ["Kana", "かな"]),
            (82, ["Keypad 0", "テンキー 0"]),
            (72, ["Volume Up", "音量を上げる"])
        ] {
            for query in queries {
                XCTAssertTrue(inputs.contains { $0.id == code && $0.matches(query) }, query)
            }
        }
    }

    func testEveryKeyAndGroupHasResolvedDisplayNames() throws {
        let keys = Set(try translations("en").keys)
        for group in KeyCatalog.inputGroups {
            XCTAssertFalse(keys.contains(group.name), group.id)
            for key in group.keys {
                XCTAssertFalse(keys.contains(key.name), String(key.id))
            }
        }
        for key in ModifierKey.allCases {
            XCTAssertTrue(keys.contains(key.localizationKey))
            XCTAssertFalse(keys.contains(key.displayName))
        }
    }
}
