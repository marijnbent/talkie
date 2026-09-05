import AppKit
import Foundation
import SwiftUI

@MainActor
final class AudioMeterState: ObservableObject {
    @Published private(set) var level: CGFloat = 0

    func update(_ level: CGFloat) {
        guard self.level != level else { return }
        self.level = level
    }
}

@MainActor
final class SessionState: ObservableObject {
    static let maxLogEntries = 1_000

    private let historyStore: (any TranscriptHistoryPersisting)?
    private var pendingHistorySnapshot: [TranscriptHistoryEntry]?
    private var pendingRemovedHistoryEntries: [TranscriptHistoryEntry] = []

    @Published var recordingPhase: RecordingPhase = .idle
    @Published var appStatus: AppStatus = .idle
    @Published var lastTranscript = ""
    @Published var finalTranscript = ""
    @Published var logs: [LogEntry] = []
    @Published var transcriptHistory: [TranscriptHistoryEntry] = [] {
        didSet {
            historyDidChange(from: oldValue)
        }
    }
    @Published var overlayPulseID = UUID()
    @Published var overlayVisible = false
    @Published var overlayLabel = "Listening"
    @Published var overlayAppIcon: NSImage?
    let audioMeter = AudioMeterState()
    var onHistoryEntriesRemoved: (([TranscriptHistoryEntry]) -> Void)?
    var onHistoryPersistenceError: ((String) -> Void)?
    private(set) var historyPersistenceError: String?
    private(set) var isHistoryPersisted = true

    var isRecording: Bool {
        recordingPhase == .recording
    }

    var statusMessage: String {
        appStatus.message
    }

    private var transcriptSegments: [String] = []

    init(
        historyStore: (any TranscriptHistoryPersisting)? = nil,
        initialTranscriptHistory: [TranscriptHistoryEntry] = [],
        initialHistoryIsPersisted: Bool = true
    ) {
        self.historyStore = historyStore
        self._transcriptHistory = Published(initialValue: initialTranscriptHistory)
        self.isHistoryPersisted = historyStore == nil || initialHistoryIsPersisted
    }

    func resetTranscript() {
        lastTranscript = ""
        finalTranscript = ""
        transcriptSegments.removeAll()
    }

    func handleTranscript(_ text: String, isFinal: Bool) {
        lastTranscript = text
        guard isFinal else { return }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func finalizeLatestInterimTranscript() {
        let trimmed = lastTranscript.trimmed
        guard !trimmed.isEmpty else { return }
        if transcriptSegments.last != trimmed {
            transcriptSegments.append(trimmed)
            finalTranscript = transcriptSegments.joined(separator: " ")
        }
    }

    func addLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func storeTranscriptHistoryEntry(_ entry: TranscriptHistoryEntry, limit: HistoryLimit) {
        guard limit != .none else {
            onHistoryEntriesRemoved?([entry])
            return
        }

        let retainedExistingEntries = transcriptHistory.prefix(max(0, limit.rawValue - 1))
        transcriptHistory = [entry] + retainedExistingEntries
    }

    func addTranscriptToHistory(
        _ text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        enhancementPromptText: String? = nil,
        enhancementProvider: EnhancementProvider? = nil,
        enhancementModel: String? = nil,
        rawRecordingFileURL: URL? = nil,
        transcriptionLanguage: DeepgramLanguage? = nil,
        usedActiveAppPrompt: Bool = false,
        limit: HistoryLimit
    ) {
        guard limit != .none else {
            let discardedEntry = TranscriptHistoryEntry(
                timestamp: Date(),
                text: text,
                enhancedText: enhancedText,
                transcriptionError: transcriptionError,
                enhancementError: enhancementError,
                promptName: promptName,
                enhancementPromptText: enhancementPromptText,
                enhancementProvider: enhancementProvider,
                enhancementModel: enhancementModel,
                rawRecordingFileURL: rawRecordingFileURL,
                transcriptionLanguage: transcriptionLanguage,
                usedActiveAppPrompt: usedActiveAppPrompt
            )
            onHistoryEntriesRemoved?([discardedEntry])
            return
        }
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: text,
            enhancedText: enhancedText,
            transcriptionError: transcriptionError,
            enhancementError: enhancementError,
            promptName: promptName,
            enhancementPromptText: enhancementPromptText,
            enhancementProvider: enhancementProvider,
            enhancementModel: enhancementModel,
            rawRecordingFileURL: rawRecordingFileURL,
            transcriptionLanguage: transcriptionLanguage,
            usedActiveAppPrompt: usedActiveAppPrompt
        )
        storeTranscriptHistoryEntry(entry, limit: limit)
    }

    func addTranscriptionFailureToHistory(reason: String, partialText: String = "", limit: HistoryLimit) {
        addTranscriptToHistory(
            partialText,
            transcriptionError: reason,
            limit: limit
        )
    }

    func applyHistoryLimit(_ limit: HistoryLimit) {
        let max = limit.rawValue
        guard transcriptHistory.count > max else { return }
        transcriptHistory = Array(transcriptHistory.prefix(max))
    }

    func updateTranscriptHistoryEntry(
        id: UUID,
        transform: (TranscriptHistoryEntry) -> TranscriptHistoryEntry
    ) {
        guard let index = transcriptHistory.firstIndex(where: { $0.id == id }) else { return }
        transcriptHistory[index] = transform(transcriptHistory[index])
    }

    /// Retries the latest failed history save. Recording cleanup waits for this to succeed.
    @discardableResult
    func flushHistory() -> Bool {
        guard let pendingHistorySnapshot else {
            return isHistoryPersisted
        }
        return persistHistory(pendingHistorySnapshot)
    }

    private func historyDidChange(from previousEntries: [TranscriptHistoryEntry]) {
        let currentIDs = Set(transcriptHistory.map(\.id))
        pendingRemovedHistoryEntries.append(
            contentsOf: previousEntries.filter { !currentIDs.contains($0.id) }
        )

        guard historyStore != nil else {
            isHistoryPersisted = true
            releasePendingHistoryCleanup()
            return
        }

        pendingHistorySnapshot = transcriptHistory
        isHistoryPersisted = false
        _ = persistHistory(transcriptHistory)
    }

    private func persistHistory(_ entries: [TranscriptHistoryEntry]) -> Bool {
        guard let historyStore else {
            isHistoryPersisted = true
            pendingHistorySnapshot = nil
            historyPersistenceError = nil
            releasePendingHistoryCleanup()
            return true
        }

        do {
            try historyStore.saveEntries(entries)
            pendingHistorySnapshot = nil
            historyPersistenceError = nil
            isHistoryPersisted = true
            releasePendingHistoryCleanup()
            return true
        } catch {
            pendingHistorySnapshot = entries
            isHistoryPersisted = false
            let message = error.localizedDescription
            historyPersistenceError = message
            onHistoryPersistenceError?(message)
            return false
        }
    }

    private func releasePendingHistoryCleanup() {
        guard !pendingRemovedHistoryEntries.isEmpty else { return }

        let referencedRecordingPaths = Set(
            transcriptHistory.compactMap { $0.rawRecordingFileURL?.standardizedFileURL.path }
        )
        var seenEntries = Set<UUID>()
        let entriesToRemove = pendingRemovedHistoryEntries.filter { entry in
            guard seenEntries.insert(entry.id).inserted else { return false }
            guard let recordingURL = entry.rawRecordingFileURL else { return true }
            return !referencedRecordingPaths.contains(recordingURL.standardizedFileURL.path)
        }
        pendingRemovedHistoryEntries.removeAll()

        if !entriesToRemove.isEmpty {
            onHistoryEntriesRemoved?(entriesToRemove)
        }
    }
}

struct TranscriptHistoryEntry: Codable, Identifiable {
    static let emptyTranscriptionMessage = "No speech was detected or no final transcript was returned."

    let id: UUID
    let timestamp: Date
    let text: String
    let enhancedText: String?
    let transcriptionError: String?
    let enhancementError: String?
    let promptName: String?
    let enhancementPromptText: String?
    let enhancementProvider: EnhancementProvider?
    let enhancementModel: String?
    let rawRecordingFileURL: URL?
    let transcriptionLanguage: DeepgramLanguage?
    let usedActiveAppPrompt: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        enhancedText: String? = nil,
        transcriptionError: String? = nil,
        enhancementError: String? = nil,
        promptName: String? = nil,
        enhancementPromptText: String? = nil,
        enhancementProvider: EnhancementProvider? = nil,
        enhancementModel: String? = nil,
        rawRecordingFileURL: URL? = nil,
        transcriptionLanguage: DeepgramLanguage? = nil,
        usedActiveAppPrompt: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.enhancedText = enhancedText
        self.transcriptionError = transcriptionError
        self.enhancementError = enhancementError
        self.promptName = promptName
        self.enhancementPromptText = enhancementPromptText
        self.enhancementProvider = enhancementProvider
        self.enhancementModel = enhancementModel
        self.rawRecordingFileURL = rawRecordingFileURL
        self.transcriptionLanguage = transcriptionLanguage
        self.usedActiveAppPrompt = usedActiveAppPrompt
    }

    var displayText: String {
        let source = (enhancedText ?? text).trimmed
        if source.isEmpty {
            if let transcriptionError {
                return "Transcription failed: \(transcriptionError)"
            }
            if let enhancementError {
                return "Enhancement failed: \(enhancementError)"
            }
            return ""
        }
        let sentences = source.splitIntoSentences()
        if sentences.count <= 3 { return source }
        return sentences.prefix(3).joined() + "…"
    }

    var shouldShowTranscriptionWarningIcon: Bool {
        guard let transcriptionError else { return false }
        return !(text.trimmed.isEmpty && transcriptionError == Self.emptyTranscriptionMessage)
    }

    var promptSourceLabel: String {
        usedActiveAppPrompt ? "Active app" : "Default"
    }

    var savedEnhancementPromptLabel: String? {
        enhancementPromptText?
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .first(where: { !$0.isEmpty })
    }

    var canRetryEnhancement: Bool {
        !text.trimmed.isEmpty &&
        (enhancedText?.trimmed ?? "").isEmpty &&
        !(enhancementPromptText?.trimmed ?? "").isEmpty
    }

    var canRetryTranscription: Bool {
        rawRecordingFileURL != nil
    }
}

extension String {
    func splitIntoSentences() -> [String] {
        var sentences: [String] = []
        enumerateSubstrings(in: startIndex..., options: .bySentences) { _, range, _, _ in
            sentences.append(String(self[range]))
        }
        return sentences
    }
}
