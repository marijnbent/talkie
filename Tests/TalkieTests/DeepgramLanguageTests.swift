import XCTest
@testable import TalkieCore

final class DeepgramLanguageTests: XCTestCase {
    func testNextStarredLanguageCyclesInMenuOrder() {
        let starred: [DeepgramLanguage] = [.french, .automatic, .english]

        XCTAssertEqual(
            DeepgramLanguage.nextStarredLanguage(after: .automatic, starredLanguages: starred),
            .english
        )
        XCTAssertEqual(
            DeepgramLanguage.nextStarredLanguage(after: .english, starredLanguages: starred),
            .french
        )
        XCTAssertEqual(
            DeepgramLanguage.nextStarredLanguage(after: .french, starredLanguages: starred),
            .automatic
        )
    }

    func testNextStarredLanguageStartsAtFirstWhenCurrentIsNotStarred() {
        XCTAssertEqual(
            DeepgramLanguage.nextStarredLanguage(after: .spanish, starredLanguages: [.french, .english]),
            .english
        )
    }
}
