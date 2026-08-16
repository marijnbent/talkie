import XCTest
@testable import TalkieCore

final class DeepgramLanguageTests: XCTestCase {
    func testProviderLanguageCatalogsOnlyExposeSupportedChoices() {
        XCTAssertTrue(TranscriptionProvider.deepgram.languageOptions.contains(.chineseCantonese))
        XCTAssertFalse(TranscriptionProvider.deepgram.languageOptions.contains(.cantonese))
        XCTAssertTrue(TranscriptionProvider.deepgram.languageOptions.contains(.thaiThailand))

        XCTAssertTrue(TranscriptionProvider.elevenLabs.languageOptions.contains(.cantonese))
        XCTAssertTrue(TranscriptionProvider.elevenLabs.languageOptions.contains(.filipino))
        XCTAssertTrue(TranscriptionProvider.elevenLabs.languageOptions.contains(.irish))
        XCTAssertTrue(TranscriptionProvider.elevenLabs.languageOptions.contains(.zulu))
        XCTAssertFalse(TranscriptionProvider.elevenLabs.languageOptions.contains(.englishBritish))
        XCTAssertFalse(TranscriptionProvider.elevenLabs.languageOptions.contains(.chineseCantonese))
    }

    func testAutomaticLanguageCandidatesAreConfigurablePerProvider() {
        XCTAssertEqual(
            TranscriptionProvider.elevenLabs.defaultAutomaticLanguageCandidates,
            [.dutch, .english]
        )
        XCTAssertEqual(
            TranscriptionProvider.elevenLabs.normalizedAutomaticLanguageCandidates(
                [.russian, .english, .russian, .automatic]
            ),
            [.english, .russian]
        )
        XCTAssertTrue(TranscriptionProvider.deepgram.automaticLanguageCandidateOptions.isEmpty)
        XCTAssertEqual(
            TranscriptionProvider.elevenLabs.automaticLanguageHelpText,
            "Automatic uses the selected languages only."
        )
    }

    func testProviderNormalizesSharedLanguagesToItsCatalog() {
        XCTAssertEqual(
            TranscriptionProvider.deepgram.normalizedLanguage(.cantonese),
            .chineseCantonese
        )
        XCTAssertEqual(
            TranscriptionProvider.deepgram.normalizedLanguage(.filipino),
            .tagalog
        )
        XCTAssertEqual(
            TranscriptionProvider.elevenLabs.normalizedLanguage(.englishBritish),
            .english
        )
        XCTAssertEqual(
            TranscriptionProvider.elevenLabs.normalizedLanguage(.chineseMandarinTraditional),
            .mandarinChinese
        )
    }

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
