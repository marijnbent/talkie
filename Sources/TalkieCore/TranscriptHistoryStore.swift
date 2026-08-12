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
