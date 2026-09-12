import Foundation

protocol TranscriptHistoryPersisting: AnyObject {
    func saveEntries(_ entries: [TranscriptHistoryEntry]) throws
}

final class TranscriptHistoryStore: TranscriptHistoryPersisting {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadEntries() throws -> [TranscriptHistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        let entries = try decoder.decode([TranscriptHistoryEntry].self, from: data)
        return entries.map { entry in
            guard let rawRecordingFileURL = entry.rawRecordingFileURL else { return entry }
            guard fileManager.fileExists(atPath: rawRecordingFileURL.path) else {
                return TranscriptHistoryEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    text: entry.text,
                    enhancedText: entry.enhancedText,
                    transcriptionError: entry.transcriptionError,
                    enhancementError: entry.enhancementError,
                    promptName: entry.promptName,
                    enhancementPromptText: entry.enhancementPromptText,
                    enhancementProvider: entry.enhancementProvider,
                    enhancementModel: entry.enhancementModel,
                    rawRecordingFileURL: nil,
                    transcriptionLanguage: entry.transcriptionLanguage,
                    usedActiveAppPrompt: entry.usedActiveAppPrompt
                )
            }

            return entry
        }
    }

    func saveEntries(_ entries: [TranscriptHistoryEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("transcript-history.json")
    }
}

struct TranscriptHistoryWriteResult: Sendable {
    let revision: Int
    let sequence: Int
    let errorMessage: String?
}

final class TranscriptHistoryWriter: @unchecked Sendable {
    private struct Snapshot {
        let revision: Int
        let entries: [TranscriptHistoryEntry]
    }

    private let store: any TranscriptHistoryPersisting
    private let completion: @Sendable (TranscriptHistoryWriteResult) -> Void
    private let queue = DispatchQueue(label: "Talkie.History.Persistence", qos: .utility)
    private let lock = NSLock()
    private var latestSnapshot: Snapshot?
    private var pendingSnapshot: Snapshot?
    private var workerRunning = false
    private var lastResult: TranscriptHistoryWriteResult?
    private var sequence = 0

    init(
        store: any TranscriptHistoryPersisting,
        completion: @escaping @Sendable (TranscriptHistoryWriteResult) -> Void
    ) {
        self.store = store
        self.completion = completion
    }

    func submit(_ entries: [TranscriptHistoryEntry], revision: Int) {
        let shouldStart = lock.withLock {
            let snapshot = Snapshot(revision: revision, entries: entries)
            latestSnapshot = snapshot
            pendingSnapshot = snapshot
            guard !workerRunning else { return false }
            workerRunning = true
            return true
        }
        if shouldStart {
            queue.async { [self] in
                while let snapshot = takePendingSnapshot() {
                    completion(write(snapshot))
                }
            }
        }
    }

    func flush() -> TranscriptHistoryWriteResult? {
        queue.async { [self] in
            guard let latestSnapshot = lock.withLock({ latestSnapshot }) else { return }
            if let lastResult, lastResult.revision == latestSnapshot.revision, lastResult.errorMessage == nil {
                return
            }
            _ = write(latestSnapshot)
        }
        return queue.sync { lastResult }
    }

    private func takePendingSnapshot() -> Snapshot? {
        lock.withLock {
            guard let snapshot = pendingSnapshot else {
                workerRunning = false
                return nil
            }
            pendingSnapshot = nil
            return snapshot
        }
    }

    private func write(_ snapshot: Snapshot) -> TranscriptHistoryWriteResult {
        let errorMessage: String?
        do {
            try store.saveEntries(snapshot.entries)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        sequence += 1
        let result = TranscriptHistoryWriteResult(
            revision: snapshot.revision,
            sequence: sequence,
            errorMessage: errorMessage
        )
        lastResult = result
        return result
    }
}
