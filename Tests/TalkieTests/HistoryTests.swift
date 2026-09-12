import XCTest
@testable import TalkieCore

@MainActor
final class HistoryTests: XCTestCase {
    private let historyLimitKey = "Talkie.HistoryLimit"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: historyLimitKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: historyLimitKey)
        super.tearDown()
    }

    // MARK: - Adding Entries

    func testAddTranscriptInsertsAtFront() {
        let state = SessionState()
        state.addTranscriptToHistory("first", limit: .ten)
        state.addTranscriptToHistory("second", limit: .ten)

        XCTAssertEqual(state.transcriptHistory.count, 2)
        XCTAssertEqual(state.transcriptHistory[0].text, "second")
        XCTAssertEqual(state.transcriptHistory[1].text, "first")
    }

    func testAddTranscriptSetsTimestamp() {
        let state = SessionState()
        let before = Date()
        state.addTranscriptToHistory("test", limit: .ten)
        let after = Date()

        let entry = state.transcriptHistory.first
        XCTAssertNotNil(entry)
        XCTAssertGreaterThanOrEqual(entry!.timestamp, before)
        XCTAssertLessThanOrEqual(entry!.timestamp, after)
    }

    func testAddTranscriptGeneratesUniqueIDs() {
        let state = SessionState()
        state.addTranscriptToHistory("a", limit: .ten)
        state.addTranscriptToHistory("b", limit: .ten)

        let ids = state.transcriptHistory.map(\.id)
        XCTAssertEqual(Set(ids).count, 2)
    }

    // MARK: - History Limit

    func testHistoryLimitDefaultsToTen() throws {
        let suiteName = "TalkieTests.HistoryLimit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = SettingsStore(defaults: defaults)

        XCTAssertEqual(settingsStore.historyLimit, .ten)
    }

    func testHistoryLimitNonePreventsAdding() {
        let state = SessionState()
        state.applyHistoryLimit(.none)

        state.addTranscriptToHistory("should not appear", limit: .none)
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testHistoryLimitTenTrimsExcess() {
        let state = SessionState()
        state.applyHistoryLimit(.ten)

        for i in 0..<15 {
            state.addTranscriptToHistory("entry \(i)", limit: .ten)
        }

        XCTAssertEqual(state.transcriptHistory.count, 10)
        // Most recent should be first
        XCTAssertEqual(state.transcriptHistory[0].text, "entry 14")
    }

    func testHistoryLimitHundredAllowsMoreEntries() {
        let state = SessionState()
        state.applyHistoryLimit(.hundred)

        for i in 0..<50 {
            state.addTranscriptToHistory("entry \(i)", limit: .hundred)
        }

        XCTAssertEqual(state.transcriptHistory.count, 50)
    }

    func testChangingLimitToNoneClearsHistory() {
        let state = SessionState()
        state.applyHistoryLimit(.ten)
        state.addTranscriptToHistory("a", limit: .ten)
        state.addTranscriptToHistory("b", limit: .ten)
        XCTAssertEqual(state.transcriptHistory.count, 2)

        state.applyHistoryLimit(.none)
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testReducingLimitTrimsExistingEntries() {
        let state = SessionState()
        state.applyHistoryLimit(.hundred)

        for i in 0..<20 {
            state.addTranscriptToHistory("entry \(i)", limit: .hundred)
        }
        XCTAssertEqual(state.transcriptHistory.count, 20)

        state.applyHistoryLimit(.ten)
        XCTAssertEqual(state.transcriptHistory.count, 10)
        // Most recent entries should be kept
        XCTAssertEqual(state.transcriptHistory[0].text, "entry 19")
    }

    func testHistoryLimitPersists() {
        let state = SettingsStore()
        state.historyLimit = .hundred

        let restored = SettingsStore()
        XCTAssertEqual(restored.historyLimit, .hundred)
    }

    func testTranscriptHistoryStorePersistsEntries() throws {
        let temporaryDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        let recordingURL = temporaryDirectoryURL.appendingPathComponent("test.wav")
        FileManager.default.createFile(atPath: recordingURL.path, contents: Data(), attributes: nil)

        let store = TranscriptHistoryStore(
            fileURL: temporaryDirectoryURL.appendingPathComponent("history.json")
        )
        let entry = TranscriptHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 1_234),
            text: "hello world",
            enhancedText: "Hello world.",
            transcriptionError: nil,
            enhancementError: nil,
            promptName: "Clean up",
            enhancementPromptText: "Prompt",
            enhancementProvider: .openRouter,
            enhancementModel: "anthropic/claude-sonnet-4.5",
            rawRecordingFileURL: recordingURL,
            transcriptionLanguage: .english,
            usedActiveAppPrompt: true
        )

        try store.saveEntries([entry])
        let restored = try store.loadEntries()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, entry.id)
        XCTAssertEqual(restored[0].timestamp, entry.timestamp)
        XCTAssertEqual(restored[0].text, entry.text)
        XCTAssertEqual(restored[0].enhancedText, entry.enhancedText)
        XCTAssertEqual(restored[0].promptName, entry.promptName)
        XCTAssertEqual(restored[0].enhancementPromptText, entry.enhancementPromptText)
        XCTAssertEqual(restored[0].enhancementProvider, entry.enhancementProvider)
        XCTAssertEqual(restored[0].enhancementModel, entry.enhancementModel)
        XCTAssertEqual(restored[0].rawRecordingFileURL, recordingURL)
        XCTAssertEqual(restored[0].transcriptionLanguage, .english)
        XCTAssertTrue(restored[0].usedActiveAppPrompt)
    }

    func testTranscriptHistoryStoreDropsMissingRecordingURLs() throws {
        let temporaryDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        let missingRecordingURL = temporaryDirectoryURL.appendingPathComponent("missing.wav")
        let store = TranscriptHistoryStore(
            fileURL: temporaryDirectoryURL.appendingPathComponent("history.json")
        )
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "hello world",
            rawRecordingFileURL: missingRecordingURL,
            transcriptionLanguage: .english
        )

        try store.saveEntries([entry])
        let restored = try store.loadEntries()

        XCTAssertEqual(restored.count, 1)
        XCTAssertNil(restored[0].rawRecordingFileURL)
        XCTAssertEqual(restored[0].transcriptionLanguage, .english)
    }

    func testTranscriptHistoryStoreTreatsMissingFileAsEmptyHistory() throws {
        let temporaryDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        let store = TranscriptHistoryStore(
            fileURL: temporaryDirectoryURL.appendingPathComponent("missing-history.json")
        )

        XCTAssertTrue(try store.loadEntries().isEmpty)
    }

    func testTranscriptHistoryStoreReportsInvalidHistoryFile() throws {
        let temporaryDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        let fileURL = temporaryDirectoryURL.appendingPathComponent("history.json")
        try Data("not valid history JSON".utf8).write(to: fileURL)
        let store = TranscriptHistoryStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.loadEntries())
    }

    func testFailedHistorySaveIsObservableAndFlushRetriesLatestSnapshot() async {
        let store = ControlledHistoryStore(failuresRemaining: 1)
        let state = SessionState(historyStore: store)
        var reportedErrors: [String] = []
        let failed = expectation(description: "History write failed")
        state.onHistoryPersistenceError = {
            reportedErrors.append($0)
            failed.fulfill()
        }

        state.storeTranscriptHistoryEntry(
            TranscriptHistoryEntry(timestamp: Date(), text: "Newest"),
            limit: .ten
        )

        XCTAssertFalse(state.isHistoryPersisted)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertNotNil(state.historyPersistenceError)
        XCTAssertEqual(reportedErrors.count, 1)
        XCTAssertEqual(store.attemptedSnapshots.count, 1)

        XCTAssertTrue(state.flushHistory())
        XCTAssertTrue(state.isHistoryPersisted)
        XCTAssertNil(state.historyPersistenceError)
        XCTAssertEqual(store.attemptedSnapshots.count, 2)
        XCTAssertEqual(store.savedSnapshots.last?.map(\.text), ["Newest"])
        XCTAssertFalse(store.wroteOnMainThread)
    }

    func testAddingAtLimitPersistsFinalSnapshotOnceBeforeDeletingRemovedRecording() {
        let store = ControlledHistoryStore()
        let oldestRecordingURL = URL(fileURLWithPath: "/tmp/oldest.wav")
        let initialEntries = (0..<10).map { index in
            TranscriptHistoryEntry(
                timestamp: Date(),
                text: "Entry \(index)",
                rawRecordingFileURL: index == 9 ? oldestRecordingURL : nil
            )
        }
        let state = SessionState(historyStore: store, initialTranscriptHistory: initialEntries)
        var removedEntries: [TranscriptHistoryEntry] = []
        state.onHistoryEntriesRemoved = { removedEntries.append(contentsOf: $0) }

        state.storeTranscriptHistoryEntry(
            TranscriptHistoryEntry(timestamp: Date(), text: "Newest"),
            limit: .ten
        )

        XCTAssertTrue(state.flushHistory())
        XCTAssertEqual(store.attemptedSnapshots.count, 1)
        XCTAssertEqual(store.savedSnapshots.first?.count, 10)
        XCTAssertEqual(store.savedSnapshots.first?.first?.text, "Newest")
        XCTAssertFalse(store.savedSnapshots.first?.contains(where: { $0.text == "Entry 9" }) ?? true)
        XCTAssertEqual(removedEntries.map(\.rawRecordingFileURL), [oldestRecordingURL])
    }

    func testFailedLimitSaveDefersRecordingDeletionUntilFlushSucceeds() {
        let store = ControlledHistoryStore(failuresRemaining: 1)
        let removedRecordingURL = URL(fileURLWithPath: "/tmp/removed.wav")
        let initialEntries = (0..<11).map { index in
            TranscriptHistoryEntry(
                timestamp: Date(),
                text: "Entry \(index)",
                rawRecordingFileURL: index == 10 ? removedRecordingURL : nil
            )
        }
        let state = SessionState(historyStore: store, initialTranscriptHistory: initialEntries)
        var removedEntries: [TranscriptHistoryEntry] = []
        state.onHistoryEntriesRemoved = { removedEntries.append(contentsOf: $0) }

        state.applyHistoryLimit(.ten)

        XCTAssertFalse(state.isHistoryPersisted)
        XCTAssertTrue(removedEntries.isEmpty)

        XCTAssertTrue(state.flushHistory())
        XCTAssertEqual(removedEntries.map(\.rawRecordingFileURL), [removedRecordingURL])
    }

    func testSlowHistoryWriteDoesNotBlockEditsAndFlushSavesLatestBeforeCleanup() {
        let store = BlockingHistoryStore()
        let removed = TranscriptHistoryEntry(timestamp: Date(), text: "Removed", rawRecordingFileURL: URL(fileURLWithPath: "/tmp/removed.wav"))
        let state = SessionState(historyStore: store, initialTranscriptHistory: [removed])
        var removedEntries: [TranscriptHistoryEntry] = []
        state.onHistoryEntriesRemoved = { removedEntries.append(contentsOf: $0) }
        state.transcriptHistory = [TranscriptHistoryEntry(timestamp: Date(), text: "First")]
        XCTAssertEqual(store.started.wait(timeout: .now() + 2), .success)
        state.transcriptHistory = [TranscriptHistoryEntry(timestamp: Date(), text: "Second")]
        state.transcriptHistory = [TranscriptHistoryEntry(timestamp: Date(), text: "Latest")]
        XCTAssertTrue(removedEntries.isEmpty)
        store.allowWrite.signal()
        XCTAssertTrue(state.flushHistory())
        XCTAssertEqual(store.savedSnapshots.map { $0.map(\.text) }, [["First"], ["Latest"]])
        XCTAssertFalse(store.wroteOnMainThread)
        XCTAssertEqual(removedEntries.compactMap(\.rawRecordingFileURL), [removed.rawRecordingFileURL!])
    }

    func testUnconfirmedInitialHistoryCannotBeFlushedWithoutAPendingSnapshot() {
        let store = ControlledHistoryStore()
        let state = SessionState(
            historyStore: store,
            initialTranscriptHistory: [],
            initialHistoryIsPersisted: false
        )

        XCTAssertFalse(state.isHistoryPersisted)
        XCTAssertFalse(state.flushHistory())
        XCTAssertTrue(store.attemptedSnapshots.isEmpty)
    }

    // MARK: - Display Text

    func testDisplayTextShortTranscript() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "Hello world.")
        XCTAssertEqual(entry.displayText, "Hello world.")
    }

    func testDisplayTextThreeSentencesShownInFull() {
        let text = "First sentence. Second sentence. Third sentence."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: text)
        XCTAssertEqual(entry.displayText, text)
    }

    func testDisplayTextMoreThanThreeSentencesTruncates() {
        let text = "One. Two. Three. Four. Five."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: text)
        XCTAssertTrue(entry.displayText.hasSuffix("…"))
        XCTAssertFalse(entry.displayText.contains("Four"))
    }

    // MARK: - Enhanced Text

    func testAddTranscriptWithEnhancedText() {
        let state = SessionState()
        state.addTranscriptToHistory("raw text", enhancedText: "enhanced text", limit: .ten)

        XCTAssertEqual(state.transcriptHistory.count, 1)
        XCTAssertEqual(state.transcriptHistory[0].text, "raw text")
        XCTAssertEqual(state.transcriptHistory[0].enhancedText, "enhanced text")
    }

    func testAddTranscriptWithoutEnhancedText() {
        let state = SessionState()
        state.addTranscriptToHistory("raw text", limit: .ten)

        XCTAssertEqual(state.transcriptHistory.count, 1)
        XCTAssertEqual(state.transcriptHistory[0].text, "raw text")
        XCTAssertNil(state.transcriptHistory[0].enhancedText)
    }

    func testAddTranscriptStoresPromptMetadata() {
        let state = SessionState()
        let recordingURL = URL(fileURLWithPath: "/tmp/history-test.wav")
        state.addTranscriptToHistory(
            "raw text",
            promptName: "Clean up",
            enhancementPromptText: "MPA3\nRewrite this carefully.",
            rawRecordingFileURL: recordingURL,
            transcriptionLanguage: .english,
            usedActiveAppPrompt: true, limit: .ten)

        XCTAssertEqual(state.transcriptHistory[0].promptName, "Clean up")
        XCTAssertEqual(state.transcriptHistory[0].enhancementPromptText, "MPA3\nRewrite this carefully.")
        XCTAssertEqual(state.transcriptHistory[0].rawRecordingFileURL, recordingURL)
        XCTAssertEqual(state.transcriptHistory[0].transcriptionLanguage, .english)
        XCTAssertEqual(state.transcriptHistory[0].savedEnhancementPromptLabel, "MPA3")
        XCTAssertTrue(state.transcriptHistory[0].usedActiveAppPrompt)
        XCTAssertEqual(state.transcriptHistory[0].promptSourceLabel, "Active app")
    }

    func testDisplayTextPrefersEnhancedText() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw", enhancedText: "enhanced")
        XCTAssertEqual(entry.displayText, "enhanced")
    }

    func testDisplayTextFallsBackToRawWhenNoEnhancement() {
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw only")
        XCTAssertEqual(entry.displayText, "raw only")
    }

    func testDisplayTextTruncatesEnhancedText() {
        let enhanced = "One. Two. Three. Four. Five."
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "raw", enhancedText: enhanced)
        XCTAssertTrue(entry.displayText.hasSuffix("…"))
        XCTAssertFalse(entry.displayText.contains("Four"))
    }

    func testSavedEnhancementPromptLabelUsesFirstNonEmptyLine() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "raw",
            enhancementPromptText: "\n  MPA3  \nRewrite this carefully."
        )

        XCTAssertEqual(entry.savedEnhancementPromptLabel, "MPA3")
    }

    func testCanRetryEnhancementWhenRawTextAndSavedPromptExist() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "raw transcript",
            enhancementPromptText: "MPA3\nRewrite this carefully."
        )

        XCTAssertTrue(entry.canRetryEnhancement)
    }

    func testCanRetryEnhancementIsFalseAfterEnhancementExists() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "raw transcript",
            enhancedText: "enhanced transcript",
            enhancementPromptText: "MPA3\nRewrite this carefully."
        )

        XCTAssertFalse(entry.canRetryEnhancement)
    }

    func testCanRetryTranscriptionWhenSavedRecordingAndLanguageExist() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: "Deepgram failed.",
            rawRecordingFileURL: URL(fileURLWithPath: "/tmp/test.wav"),
            transcriptionLanguage: .automatic
        )

        XCTAssertTrue(entry.canRetryTranscription)
    }

    func testCanRetryTranscriptionWhenExistingTranscriptIsIncorrect() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "Incorrect Dutch output",
            enhancedText: "Incorrect enhanced output",
            rawRecordingFileURL: URL(fileURLWithPath: "/tmp/test.wav"),
            transcriptionLanguage: .dutch
        )

        XCTAssertTrue(entry.canRetryTranscription)
    }

    func testCanRetryTranscriptionIsFalseWithoutSavedRecording() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: "Deepgram failed.",
            transcriptionLanguage: .automatic
        )

        XCTAssertFalse(entry.canRetryTranscription)
    }

    func testEmptyTranscriptionNoticeHidesWarningIcon() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: TranscriptHistoryEntry.emptyTranscriptionMessage
        )
        XCTAssertFalse(entry.shouldShowTranscriptionWarningIcon)
    }

    func testTranscriptionErrorShowsWarningIcon() {
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "",
            transcriptionError: "WebSocket receive error."
        )
        XCTAssertTrue(entry.shouldShowTranscriptionWarningIcon)
    }

    // MARK: - HistoryLimit Enum

    func testHistoryLimitDisplayNames() {
        XCTAssertEqual(HistoryLimit.none.displayName, "None")
        XCTAssertEqual(HistoryLimit.ten.displayName, "10")
        XCTAssertEqual(HistoryLimit.hundred.displayName, "100")
    }

    func testHistoryLimitRawValues() {
        XCTAssertEqual(HistoryLimit.none.rawValue, 0)
        XCTAssertEqual(HistoryLimit.ten.rawValue, 10)
        XCTAssertEqual(HistoryLimit.hundred.rawValue, 100)
    }

    func testHistoryLimitAllCases() {
        XCTAssertEqual(HistoryLimit.allCases.count, 3)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ControlledHistoryStore: TranscriptHistoryPersisting {
    private(set) var wroteOnMainThread = false
    private(set) var failuresRemaining: Int
    private(set) var attemptedSnapshots: [[TranscriptHistoryEntry]] = []
    private(set) var savedSnapshots: [[TranscriptHistoryEntry]] = []

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func saveEntries(_ entries: [TranscriptHistoryEntry]) throws {
        wroteOnMainThread = wroteOnMainThread || Thread.isMainThread
        attemptedSnapshots.append(entries)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ControlledHistoryStoreError.saveFailed
        }
        savedSnapshots.append(entries)
    }
}

private enum ControlledHistoryStoreError: Error {
    case saveFailed
}

private final class BlockingHistoryStore: TranscriptHistoryPersisting {
    let started = DispatchSemaphore(value: 0)
    let allowWrite = DispatchSemaphore(value: 0)
    private(set) var savedSnapshots: [[TranscriptHistoryEntry]] = []
    private(set) var wroteOnMainThread = false

    func saveEntries(_ entries: [TranscriptHistoryEntry]) throws {
        wroteOnMainThread = wroteOnMainThread || Thread.isMainThread
        if savedSnapshots.isEmpty {
            started.signal()
            guard allowWrite.wait(timeout: .now() + 5) == .success else {
                throw ControlledHistoryStoreError.saveFailed
            }
        }
        savedSnapshots.append(entries)
    }
}
