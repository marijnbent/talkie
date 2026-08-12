import Foundation
import XCTest
@testable import TalkieCore

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testUnrelatedSessionChangesDoNotRefreshHistoryViewModel() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let sessionState = SessionState()
        let viewModel = HistoryViewModel(
            settingsStore: SettingsStore(defaults: defaults),
            sessionState: sessionState
        )
        var updateCount = 0
        let cancellable = viewModel.objectWillChange.sink { updateCount += 1 }

        sessionState.audioLevel = 0.5

        XCTAssertEqual(updateCount, 0)

        sessionState.transcriptHistory = [
            TranscriptHistoryEntry(timestamp: Date(), text: "History changed")
        ]

        XCTAssertEqual(updateCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRetryTranscriptionUsesChosenLanguageAndUpdatesSameEntry() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let recordingURL = temporaryDirectoryURL.appendingPathComponent("recording.wav")
        try Data([0]).write(to: recordingURL)

        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        defaults.set("deepgram-key", forKey: SettingsStore.apiKeyKey)
        defaults.set(EnhancementProvider.celeris.rawValue, forKey: SettingsStore.enhancementProviderKey)
        defaults.set("celeris-key", forKey: SettingsStore.celerisApiKeyKey)

        let entry = TranscriptHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 1_234),
            text: "Incorrect Dutch output",
            enhancedText: "Old enhanced output",
            transcriptionError: "Old transcription warning",
            promptName: "Clean up",
            enhancementPromptText: "Rewrite this carefully.",
            rawRecordingFileURL: recordingURL,
            transcriptionLanguage: .dutch
        )
        let sessionState = SessionState(initialTranscriptHistory: [entry])
        let transcriber = TranscriberSpy(result: .success("Correct English transcript"))
        let viewModel = HistoryViewModel(
            settingsStore: SettingsStore(defaults: defaults),
            sessionState: sessionState,
            enhancer: { transcript, _, _ in "Enhanced: \(transcript)" },
            transcriber: { fileURL, apiKey, language in
                try await transcriber.transcribe(
                    fileURL: fileURL,
                    apiKey: apiKey,
                    languageRawValue: language.rawValue
                )
            }
        )

        viewModel.retryTranscription(for: entry, language: .english)
        await waitForRetryToFinish(entry.id, in: viewModel)

        let calls = await transcriber.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.fileURL, recordingURL)
        XCTAssertEqual(call.apiKey, "deepgram-key")
        XCTAssertEqual(call.languageRawValue, DeepgramLanguage.english.rawValue)

        let updated = try XCTUnwrap(sessionState.transcriptHistory.first)
        XCTAssertEqual(sessionState.transcriptHistory.count, 1)
        XCTAssertEqual(updated.id, entry.id)
        XCTAssertEqual(updated.timestamp, entry.timestamp)
        XCTAssertEqual(updated.text, "Correct English transcript")
        XCTAssertEqual(updated.enhancedText, "Enhanced: Correct English transcript")
        XCTAssertNil(updated.transcriptionError)
        XCTAssertEqual(updated.transcriptionLanguage, .english)
        XCTAssertEqual(updated.rawRecordingFileURL, recordingURL)
    }

    func testThrownErrorRetryPreservesExistingEntry() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let recordingURL = temporaryDirectoryURL.appendingPathComponent("recording.wav")
        try Data([0]).write(to: recordingURL)

        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        defaults.set("deepgram-key", forKey: SettingsStore.apiKeyKey)

        let entry = TranscriptHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 5_678),
            text: "Existing transcript",
            enhancedText: "Existing enhancement",
            transcriptionError: "Existing transcription warning",
            enhancementError: "Existing enhancement warning",
            promptName: "Clean up",
            enhancementPromptText: "Rewrite this carefully.",
            rawRecordingFileURL: recordingURL,
            transcriptionLanguage: .dutch,
            usedActiveAppPrompt: true
        )
        let sessionState = SessionState(initialTranscriptHistory: [entry])
        let transcriber = TranscriberSpy(result: .failure)
        let viewModel = HistoryViewModel(
            settingsStore: SettingsStore(defaults: defaults),
            sessionState: sessionState,
            enhancer: { _, _, _ in "Unexpected enhancement" },
            transcriber: { fileURL, apiKey, language in
                try await transcriber.transcribe(
                    fileURL: fileURL,
                    apiKey: apiKey,
                    languageRawValue: language.rawValue
                )
            }
        )

        viewModel.retryTranscription(for: entry, language: .english)
        await waitForRetryToFinish(entry.id, in: viewModel)

        let calls = await transcriber.calls()
        XCTAssertEqual(calls.count, 1)
        try assertHistoryPreserved(in: sessionState, expected: entry)
        XCTAssertNotNil(viewModel.retryError(for: entry.id))
    }

    func testWhitespaceRetryPreservesExistingEntry() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let recordingURL = temporaryDirectoryURL.appendingPathComponent("recording.wav")
        try Data([0]).write(to: recordingURL)

        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        defaults.set("deepgram-key", forKey: SettingsStore.apiKeyKey)

        let entry = TranscriptHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 9_012),
            text: "Existing transcript",
            enhancedText: "Existing enhancement",
            transcriptionError: "Existing transcription warning",
            enhancementError: "Existing enhancement warning",
            promptName: "Clean up",
            enhancementPromptText: "Rewrite this carefully.",
            rawRecordingFileURL: recordingURL,
            transcriptionLanguage: .dutch,
            usedActiveAppPrompt: true
        )
        let sessionState = SessionState(initialTranscriptHistory: [entry])
        let transcriber = TranscriberSpy(result: .success(" \n\t "))
        let viewModel = HistoryViewModel(
            settingsStore: SettingsStore(defaults: defaults),
            sessionState: sessionState,
            enhancer: { _, _, _ in "Unexpected enhancement" },
            transcriber: { fileURL, apiKey, language in
                try await transcriber.transcribe(
                    fileURL: fileURL,
                    apiKey: apiKey,
                    languageRawValue: language.rawValue
                )
            }
        )

        viewModel.retryTranscription(for: entry, language: .english)
        await waitForRetryToFinish(entry.id, in: viewModel)

        let calls = await transcriber.calls()
        XCTAssertEqual(calls.count, 1)
        try assertHistoryPreserved(in: sessionState, expected: entry)
        XCTAssertEqual(viewModel.retryError(for: entry.id), "Deepgram returned no transcript.")
    }

    private func waitForRetryToFinish(
        _ entryID: UUID,
        in viewModel: HistoryViewModel
    ) async {
        for _ in 0..<100 {
            if !viewModel.isRetrying(entryID) {
                return
            }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("History retry did not finish")
    }

    private func assertHistoryPreserved(
        in sessionState: SessionState,
        expected entry: TranscriptHistoryEntry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(sessionState.transcriptHistory.count, 1, file: file, line: line)
        let preserved = try XCTUnwrap(
            sessionState.transcriptHistory.first,
            file: file,
            line: line
        )
        XCTAssertEqual(preserved.id, entry.id, file: file, line: line)
        XCTAssertEqual(preserved.timestamp, entry.timestamp, file: file, line: line)
        XCTAssertEqual(preserved.text, entry.text, file: file, line: line)
        XCTAssertEqual(preserved.enhancedText, entry.enhancedText, file: file, line: line)
        XCTAssertEqual(preserved.transcriptionError, entry.transcriptionError, file: file, line: line)
        XCTAssertEqual(preserved.enhancementError, entry.enhancementError, file: file, line: line)
        XCTAssertEqual(preserved.promptName, entry.promptName, file: file, line: line)
        XCTAssertEqual(preserved.enhancementPromptText, entry.enhancementPromptText, file: file, line: line)
        XCTAssertEqual(preserved.rawRecordingFileURL, entry.rawRecordingFileURL, file: file, line: line)
        XCTAssertEqual(preserved.transcriptionLanguage, entry.transcriptionLanguage, file: file, line: line)
        XCTAssertEqual(preserved.usedActiveAppPrompt, entry.usedActiveAppPrompt, file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "TalkieTests.HistoryViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(name, forKey: Self.defaultsSuiteNameKey)
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: Self.defaultsSuiteNameKey)!
    }

    private static let defaultsSuiteNameKey = "TalkieTests.DefaultsSuiteName"
}

private actor TranscriberSpy {
    struct Call: Sendable {
        let fileURL: URL
        let apiKey: String
        let languageRawValue: String
    }

    enum Result: Sendable {
        case success(String)
        case failure
    }

    private let result: Result
    private var recordedCalls: [Call] = []

    init(result: Result) {
        self.result = result
    }

    func transcribe(
        fileURL: URL,
        apiKey: String,
        languageRawValue: String
    ) throws -> String {
        recordedCalls.append(
            Call(fileURL: fileURL, apiKey: apiKey, languageRawValue: languageRawValue)
        )

        switch result {
        case let .success(transcript):
            return transcript
        case .failure:
            throw TranscriberTestError.failed
        }
    }

    func calls() -> [Call] {
        recordedCalls
    }
}

private enum TranscriberTestError: Error {
    case failed
}
