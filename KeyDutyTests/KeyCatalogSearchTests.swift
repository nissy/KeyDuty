import Carbon
import XCTest
@testable import KeyDuty

final class KeyCatalogSearchTests: XCTestCase {
    private func codes(matching query: String) -> Set<CGKeyCode> {
        Set(KeyCatalog.keys.filter { $0.matches(query) }.map(\.id))
    }

    func testJapaneseKeySearchAcceptsCommonSpellingsWithoutDuplicateEntries() {
        for query in ["半角全角", "半角／全角", "半角 全角", "全角/半角", "漢字", "`", "Backquote", "50"] {
            XCTAssertEqual(codes(matching: query), [CGKeyCode(kVK_ANSI_Grave)], query)
        }
        XCTAssertEqual(codes(matching: "アットマーク"), [CGKeyCode(kVK_ANSI_LeftBracket)])
        XCTAssertEqual(codes(matching: "ろ"), [CGKeyCode(kVK_JIS_Underscore)])
        XCTAssertEqual(codes(matching: "￥"), [CGKeyCode(kVK_JIS_Yen)])
        XCTAssertEqual(KeyCatalog.keys.filter { $0.id == CGKeyCode(kVK_ANSI_Grave) }.count, 1)
    }

    func testPCNamesResolveToMacEventCodes() {
        XCTAssertEqual(codes(matching: "ＰｒｔＳｃ"), [CGKeyCode(kVK_F13)])
        XCTAssertEqual(codes(matching: "printscreen"), [CGKeyCode(kVK_F13)])
        XCTAssertEqual(codes(matching: "ScrollLock"), [CGKeyCode(kVK_F14)])
        XCTAssertEqual(codes(matching: "Pause"), [CGKeyCode(kVK_F15)])
        XCTAssertEqual(codes(matching: "Insert"), [CGKeyCode(kVK_Help)])
        XCTAssertEqual(codes(matching: "アプリケーション"), [CGKeyCode(kVK_ContextualMenu)])
    }

    func testSymbolQueriesAreNotTreatedAsEmptyAndUnknownKeyCodesArePreserved() {
        let slash = codes(matching: "/")
        XCTAssertTrue(slash.contains(CGKeyCode(kVK_ANSI_Slash)))
        XCTAssertFalse(slash.contains(CGKeyCode(kVK_ANSI_A)))
        XCTAssertEqual(codes(matching: "\t  ").count, KeyCatalog.keys.count)
        XCTAssertEqual(KeyCatalog.name(for: 200), L10n.text("key.code", "200"))
        XCTAssertTrue(codes(matching: "存在しないキー").isEmpty)
    }
}
