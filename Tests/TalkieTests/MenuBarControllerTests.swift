import XCTest
@testable import TalkieCore

final class MenuBarControllerTests: XCTestCase {
    func testLanguageMenuTitleUsesCurrentLanguageDisplayName() {
        XCTAssertEqual(
            MenuBarLanguageModel.title(for: .french),
            "Language: French"
        )
    }

    func testLanguageSubmenuItemsIncludeOnlyStarredLanguagesInMenuOrder() {
        let items = MenuBarLanguageModel.submenuItems(
            currentLanguage: .english,
            starredLanguages: [.spanish, .automatic, .english, .french]
        )

        XCTAssertEqual(items.map(\.language), [.automatic, .english, .french, .spanish])
    }

    func testLanguageSubmenuItemsMarkSelectedStarredLanguage() {
        let items = MenuBarLanguageModel.submenuItems(
            currentLanguage: .french,
            starredLanguages: [.english, .french]
        )

        XCTAssertEqual(items.first(where: { $0.language == .french })?.isSelected, true)
        XCTAssertEqual(items.first(where: { $0.language == .english })?.isSelected, false)
    }

    func testLanguageSubmenuItemsLeaveNonStarredCurrentLanguageUnchecked() {
        let items = MenuBarLanguageModel.submenuItems(
            currentLanguage: .french,
            starredLanguages: [.automatic, .english]
        )

        XCTAssertEqual(items.map(\.language), [.automatic, .english])
        XCTAssertFalse(items.contains(where: { $0.isSelected }))
    }

    func testLanguageSubmenuFiltersStarredLanguagesForProvider() {
        let items = MenuBarLanguageModel.submenuItems(
            currentLanguage: .english,
            starredLanguages: [.automatic, .englishBritish, .cantonese, .english],
            availableLanguages: TranscriptionProvider.elevenLabs.languageOptions
        )

        XCTAssertEqual(items.map(\.language), [.automatic, .cantonese, .english])
    }

    func testStatusItemTitleIsEmptyWhenLanguageDisplayIsDisabled() {
        XCTAssertEqual(
            MenuBarLanguageModel.statusItemTitle(for: .english, showsSelectedLanguage: false),
            ""
        )
    }

    func testStatusItemTitleUsesUppercaseBaseLanguageCode() {
        XCTAssertEqual(
            MenuBarLanguageModel.statusItemTitle(for: .dutch, showsSelectedLanguage: true),
            "NL"
        )
        XCTAssertEqual(
            MenuBarLanguageModel.statusItemTitle(for: .englishBritish, showsSelectedLanguage: true),
            "EN"
        )
    }

    func testStatusItemTitleIsEmptyForAutomaticLanguage() {
        XCTAssertEqual(
            MenuBarLanguageModel.statusItemTitle(for: .automatic, showsSelectedLanguage: true),
            ""
        )
    }
}
