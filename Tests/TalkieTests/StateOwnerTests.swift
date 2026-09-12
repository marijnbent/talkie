import XCTest
@testable import TalkieCore

@MainActor
final class StateOwnerTests: XCTestCase {
    private let apiKeyDefaultsKey = "Talkie.ApiKey"
    private let transcriptionProviderDefaultsKey = "Talkie.TranscriptionProvider"
    private let elevenLabsApiKeyDefaultsKey = "Talkie.ElevenLabsApiKey"
    private let museApiKeyDefaultsKey = "Talkie.MuseApiKey"
    private let languageDefaultsKey = "Talkie.DeepgramLanguage"
    private let automaticLanguageCandidatesDefaultsKey = "Talkie.AutomaticLanguageCandidates"
    private let starredLanguagesDefaultsKey = "Talkie.StarredDeepgramLanguages"
    private let shortcutsDefaultsKey = "Talkie.Shortcuts"
    private let escToCancelDefaultsKey = "Talkie.EscToCancelRecording"
    private let playSoundEffectsDefaultsKey = "Talkie.PlaySoundEffects"
    private let restoreClipboardAfterPasteDefaultsKey = "Talkie.RestoreClipboardAfterPaste"
    private let showSelectedLanguageInMenuBarDefaultsKey = "Talkie.ShowSelectedLanguageInMenuBar"
    private let showLanguageInRecorderWidgetDefaultsKey = "Talkie.ShowLanguageInRecorderWidget"
    private let showLiveTranscriptInRecorderWidgetDefaultsKey = "Talkie.ShowLiveTranscriptInRecorderWidget"
    private let audioInputSelectionDefaultsKey = "Talkie.AudioInputSelection"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: transcriptionProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: elevenLabsApiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: museApiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: automaticLanguageCandidatesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: restoreClipboardAfterPasteDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showSelectedLanguageInMenuBarDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showLanguageInRecorderWidgetDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showLiveTranscriptInRecorderWidgetDefaultsKey)
        UserDefaults.standard.removeObject(forKey: audioInputSelectionDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: transcriptionProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: elevenLabsApiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: museApiKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: automaticLanguageCandidatesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: escToCancelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: playSoundEffectsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: restoreClipboardAfterPasteDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showSelectedLanguageInMenuBarDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showLanguageInRecorderWidgetDefaultsKey)
        UserDefaults.standard.removeObject(forKey: showLiveTranscriptInRecorderWidgetDefaultsKey)
        UserDefaults.standard.removeObject(forKey: audioInputSelectionDefaultsKey)
        super.tearDown()
    }

    func testHandleTranscriptBuildsFinalTranscript() {
        let state = SessionState()
        state.resetTranscript()

        state.handleTranscript(" hello ", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello")

        state.handleTranscript("hello", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello")

        state.handleTranscript("world", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "hello world")
    }

    func testHandleTranscriptIgnoresEmptyFinalText() {
        let state = SessionState()
        state.resetTranscript()

        state.handleTranscript(" ", isFinal: true)
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testNonFinalTranscriptUpdatesLastOnly() {
        let state = SessionState()
        state.resetTranscript()

        state.handleTranscript("partial", isFinal: false)
        XCTAssertEqual(state.lastTranscript, "partial")
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testFinalizeLatestInterimTranscriptPromotesLastTranscript() {
        let state = SessionState()
        state.resetTranscript()

        state.handleTranscript("this is interim", isFinal: false)
        state.finalizeLatestInterimTranscript()

        XCTAssertEqual(state.finalTranscript, "this is interim")
    }

    func testFinalizeLatestInterimTranscriptAvoidsDuplicateSegment() {
        let state = SessionState()
        state.resetTranscript()

        state.handleTranscript("segment", isFinal: true)
        state.handleTranscript("segment", isFinal: false)
        state.finalizeLatestInterimTranscript()

        XCTAssertEqual(state.finalTranscript, "segment")
    }

    func testResetTranscriptClearsState() {
        let state = SessionState()
        state.handleTranscript("hello", isFinal: true)

        state.resetTranscript()
        XCTAssertEqual(state.lastTranscript, "")
        XCTAssertEqual(state.finalTranscript, "")
    }

    func testDeepgramLanguageDefaultsToAutomatic() {
        let state = SettingsStore()
        XCTAssertEqual(state.deepgramLanguage, .automatic)
    }

    func testTranscriptionProviderDefaultsToDeepgram() {
        let state = SettingsStore()

        XCTAssertEqual(state.transcriptionProvider, .deepgram)
    }

    func testElevenLabsProviderAndKeyPersistSeparatelyFromDeepgram() {
        let state = SettingsStore()
        state.apiKey = "deepgram-key"
        state.elevenLabsApiKey = "eleven-key"
        state.transcriptionProvider = .elevenLabs

        let restored = SettingsStore()

        XCTAssertEqual(restored.transcriptionProvider, .elevenLabs)
        XCTAssertEqual(restored.apiKey, "deepgram-key")
        XCTAssertEqual(restored.elevenLabsApiKey, "eleven-key")
        XCTAssertEqual(
            restored.transcriptionProviderSettings,
            TranscriptionProviderSettings(provider: .elevenLabs, apiKey: "eleven-key")
        )
    }

    func testMuseProviderAndKeyPersistSeparately() {
        let state = SettingsStore()
        state.apiKey = "deepgram-key"
        state.elevenLabsApiKey = "eleven-key"
        state.museApiKey = "muse-key"
        state.transcriptionProvider = .muse

        let restored = SettingsStore()

        XCTAssertEqual(restored.transcriptionProvider, .muse)
        XCTAssertEqual(restored.apiKey, "deepgram-key")
        XCTAssertEqual(restored.elevenLabsApiKey, "eleven-key")
        XCTAssertEqual(restored.museApiKey, "muse-key")
        XCTAssertEqual(
            restored.transcriptionProviderSettings,
            TranscriptionProviderSettings(provider: .muse, apiKey: "muse-key")
        )
    }

    func testDeepgramLanguagePersists() {
        let state = SettingsStore()
        state.deepgramLanguage = .french

        let restored = SettingsStore()
        XCTAssertEqual(restored.deepgramLanguage, .french)
    }

    func testAutomaticLanguageCandidatesDefaultToDutchAndEnglish() {
        let state = SettingsStore()

        XCTAssertEqual(
            state.automaticLanguageCandidates,
            [.dutch, .english]
        )
    }

    func testAutomaticLanguageCandidatesPersistAndNormalize() {
        let state = SettingsStore()
        state.automaticLanguageCandidates = [.russian, .english, .russian, .automatic]

        let restored = SettingsStore()
        XCTAssertEqual(
            restored.automaticLanguageCandidates,
            [.english, .russian]
        )
    }

    func testStarredDeepgramLanguagesDefaultToAutomaticAndEnglish() {
        let state = SettingsStore()
        XCTAssertEqual(state.starredDeepgramLanguages, [.automatic, .english])
    }

    func testStarredDeepgramLanguagesPersistDeduplicatedValues() {
        let state = SettingsStore()
        state.starredDeepgramLanguages = [.french, .english, .french]

        let restored = SettingsStore()
        XCTAssertEqual(restored.starredDeepgramLanguages, [.french, .english])
    }

    func testStarredDeepgramLanguagesIgnoreInvalidStoredValues() {
        UserDefaults.standard.set(
            [DeepgramLanguage.french.rawValue, "invalid-language", DeepgramLanguage.english.rawValue, DeepgramLanguage.french.rawValue],
            forKey: starredLanguagesDefaultsKey
        )

        let state = SettingsStore()
        XCTAssertEqual(state.starredDeepgramLanguages, [.french, .english])
    }

    func testStarredDeepgramLanguagesMigrationKeepsCurrentLanguage() {
        UserDefaults.standard.set(DeepgramLanguage.french.rawValue, forKey: languageDefaultsKey)
        UserDefaults.standard.removeObject(forKey: starredLanguagesDefaultsKey)

        let state = SettingsStore()
        XCTAssertEqual(state.deepgramLanguage, .french)
        XCTAssertEqual(state.starredDeepgramLanguages, [.automatic, .english])
    }

    func testStarredDeepgramLanguagesCannotBecomeEmpty() {
        let state = SettingsStore()
        state.starredDeepgramLanguages = [.english]
        state.starredDeepgramLanguages = []

        XCTAssertEqual(state.starredDeepgramLanguages, [.english])
    }

    // MARK: - Shortcuts Persistence

    func testShortcutsDefaultToSingleRightOptionBoth() {
        let state = SettingsStore()
        XCTAssertEqual(state.shortcuts.count, 1)
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
        XCTAssertEqual(state.shortcuts[0].mode, .both)
    }

    func testShortcutsPersist() {
        let state = SettingsStore()
        let id = state.shortcuts[0].id
        state.shortcuts[0].key = .fn
        state.shortcuts[0].mode = .hold
        state.shortcuts.append(ShortcutConfig(id: UUID(), key: .leftControl, mode: .click))

        let restored = SettingsStore()
        XCTAssertEqual(restored.shortcuts.count, 2)
        XCTAssertEqual(restored.shortcuts[0].id, id)
        XCTAssertEqual(restored.shortcuts[0].key, .fn)
        XCTAssertEqual(restored.shortcuts[0].mode, .hold)
        XCTAssertEqual(restored.shortcuts[1].key, .leftControl)
        XCTAssertEqual(restored.shortcuts[1].mode, .click)
    }

    func testShortcutsEmptyArrayFallsBackToDefault() {
        // Manually store an empty array
        let data = try! JSONEncoder().encode([ShortcutConfig]())
        UserDefaults.standard.set(data, forKey: shortcutsDefaultsKey)

        let state = SettingsStore()
        XCTAssertEqual(state.shortcuts.count, 1, "Empty persisted array should fall back to default")
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
    }

    func testShortcutsCorruptedDataFallsBackToDefault() {
        UserDefaults.standard.set(Data([0xFF, 0xFE]), forKey: shortcutsDefaultsKey)

        let state = SettingsStore()
        XCTAssertEqual(state.shortcuts.count, 1)
        XCTAssertEqual(state.shortcuts[0].key, .rightOption)
    }

    // MARK: - ESC to Cancel Recording

    func testEscToCancelRecordingDefaultsToTrue() {
        let state = SettingsStore()
        XCTAssertTrue(state.escToCancelRecording)
    }

    func testEscToCancelRecordingPersists() {
        let state = SettingsStore()
        state.escToCancelRecording = false

        let restored = SettingsStore()
        XCTAssertFalse(restored.escToCancelRecording)
    }

    // MARK: - Sound Effects

    func testPlaySoundEffectsDefaultsToFalse() {
        let state = SettingsStore()
        XCTAssertFalse(state.playSoundEffects)
    }

    func testPlaySoundEffectsPersists() {
        let state = SettingsStore()
        state.playSoundEffects = true

        let restored = SettingsStore()
        XCTAssertTrue(restored.playSoundEffects)
    }

    func testShowSelectedLanguageInMenuBarDefaultsToFalse() {
        let state = SettingsStore()
        XCTAssertFalse(state.showSelectedLanguageInMenuBar)
    }

    func testShowSelectedLanguageInMenuBarPersists() {
        let state = SettingsStore()
        state.showSelectedLanguageInMenuBar = true

        let restored = SettingsStore()
        XCTAssertTrue(restored.showSelectedLanguageInMenuBar)
    }

    func testShowLanguageInRecorderWidgetDefaultsToTrue() {
        let state = SettingsStore()
        XCTAssertTrue(state.showLanguageInRecorderWidget)
    }

    func testShowLanguageInRecorderWidgetPersists() {
        let state = SettingsStore()
        state.showLanguageInRecorderWidget = false

        let restored = SettingsStore()
        XCTAssertFalse(restored.showLanguageInRecorderWidget)
    }

    func testShowLiveTranscriptInRecorderWidgetDefaultsToTrue() {
        let state = SettingsStore()
        XCTAssertTrue(state.showLiveTranscriptInRecorderWidget)
    }

    func testShowLiveTranscriptInRecorderWidgetPersists() {
        let state = SettingsStore()
        state.showLiveTranscriptInRecorderWidget = false

        let restored = SettingsStore()
        XCTAssertFalse(restored.showLiveTranscriptInRecorderWidget)
    }

    // MARK: - Clipboard Restore

    func testRestoreClipboardAfterPasteDefaultsToFalse() {
        let state = SettingsStore()
        XCTAssertFalse(state.restoreClipboardAfterPaste)
    }

    func testRestoreClipboardAfterPastePersists() {
        let state = SettingsStore()
        state.restoreClipboardAfterPaste = true

        let restored = SettingsStore()
        XCTAssertTrue(restored.restoreClipboardAfterPaste)
    }

    func testAudioInputSelectionDefaultsToSystemDefault() {
        let state = SettingsStore()
        XCTAssertEqual(state.audioInputSelection, .systemDefault)
    }

    func testAudioInputSelectionPersistsSelectedDevice() {
        let state = SettingsStore()
        state.audioInputSelection = .device("usb-mic-123")

        let restored = SettingsStore()
        XCTAssertEqual(restored.audioInputSelection, .device("usb-mic-123"))
    }
}
