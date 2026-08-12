import Foundation
import XCTest
@testable import TalkieCore

final class RawRecordingStoreTests: XCTestCase {
    func testCaptureStreamsChunksAndFinalizesAValidWAVFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RawRecordingStore(baseDirectory: root)
        let capture = store.makeCapture(format: AudioStreamFormat(sampleRate: 16_000, channels: 1))
        let firstChunk = Data([0x01, 0x00, 0x02, 0x00])
        let secondChunk = Data([0x03, 0x00, 0x04, 0x00])

        capture.append(data: firstChunk)
        capture.append(data: secondChunk)
        let finishedURL = try await capture.finish()
        let fileURL = try XCTUnwrap(finishedURL)
        let wavData = try Data(contentsOf: fileURL)

        XCTAssertEqual(fileURL.pathExtension, "wav")
        XCTAssertEqual(String(data: wavData[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(readUInt32LE(wavData, at: 4), 36 + UInt32(firstChunk.count + secondChunk.count))
        XCTAssertEqual(String(data: wavData[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wavData[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(readUInt32LE(wavData, at: 16), 16)
        XCTAssertEqual(readUInt16LE(wavData, at: 20), 1)
        XCTAssertEqual(readUInt16LE(wavData, at: 22), 1)
        XCTAssertEqual(readUInt32LE(wavData, at: 24), 16_000)
        XCTAssertEqual(readUInt32LE(wavData, at: 28), 32_000)
        XCTAssertEqual(readUInt16LE(wavData, at: 32), 2)
        XCTAssertEqual(readUInt16LE(wavData, at: 34), 16)
        XCTAssertEqual(String(data: wavData[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(readUInt32LE(wavData, at: 40), 8)
        XCTAssertEqual(Data(wavData.dropFirst(44)), firstChunk + secondChunk)

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.standardizedFileURL), [fileURL.standardizedFileURL])
    }

    func testEmptyCaptureDoesNotCreateAFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RawRecordingStore(baseDirectory: root)
        let capture = store.makeCapture(format: AudioStreamFormat(sampleRate: 16_000, channels: 1))

        let fileURL = try await capture.finish()

        XCTAssertNil(fileURL)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testMigratesReferencedLegacyRecordingWithoutRemovingSource() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let durableDirectory = root.appendingPathComponent("Application Support/HistoryAudio", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("Caches/HistoryAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let sourceURL = legacyDirectory.appendingPathComponent("recording.wav")
        let audioData = Data([0x52, 0x49, 0x46, 0x46])
        try audioData.write(to: sourceURL)
        let entry = TranscriptHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 1_234),
            text: "Transcript",
            rawRecordingFileURL: sourceURL,
            transcriptionLanguage: .dutch
        )
        let store = RawRecordingStore(
            baseDirectory: durableDirectory,
            legacyBaseDirectory: legacyDirectory
        )

        let migratedEntries = store.migrateLegacyRecordings(in: [entry])

        let migratedURL = try XCTUnwrap(migratedEntries.first?.rawRecordingFileURL)
        XCTAssertEqual(migratedURL.deletingLastPathComponent(), durableDirectory)
        XCTAssertEqual(try Data(contentsOf: migratedURL), audioData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(migratedEntries.first?.id, entry.id)
        XCTAssertEqual(migratedEntries.first?.text, entry.text)
        XCTAssertEqual(migratedEntries.first?.transcriptionLanguage, .dutch)
    }

    func testMigrationDoesNotOverwriteARecordingWithTheSameName() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let durableDirectory = root.appendingPathComponent("durable", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: durableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let sourceURL = legacyDirectory.appendingPathComponent("recording.wav")
        let existingURL = durableDirectory.appendingPathComponent("recording.wav")
        try Data([0x01]).write(to: sourceURL)
        try Data([0x02]).write(to: existingURL)
        let entry = TranscriptHistoryEntry(
            timestamp: Date(),
            text: "Transcript",
            rawRecordingFileURL: sourceURL
        )
        let store = RawRecordingStore(
            baseDirectory: durableDirectory,
            legacyBaseDirectory: legacyDirectory
        )

        let migratedURL = try XCTUnwrap(
            store.migrateLegacyRecordings(in: [entry]).first?.rawRecordingFileURL
        )

        XCTAssertNotEqual(migratedURL, existingURL)
        XCTAssertEqual(try Data(contentsOf: existingURL), Data([0x02]))
        XCTAssertEqual(try Data(contentsOf: migratedURL), Data([0x01]))
    }

    func testPrunesUnreferencedRecordingsFromDurableAndLegacyDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let durableDirectory = root.appendingPathComponent("durable", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: durableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let keptDurableURL = durableDirectory.appendingPathComponent("kept.wav")
        let removedDurableURL = durableDirectory.appendingPathComponent("removed.wav")
        let keptLegacyURL = legacyDirectory.appendingPathComponent("kept.wav")
        let removedLegacyURL = legacyDirectory.appendingPathComponent("removed.wav")
        for url in [keptDurableURL, removedDurableURL, keptLegacyURL, removedLegacyURL] {
            try Data([0x01]).write(to: url)
        }
        let store = RawRecordingStore(
            baseDirectory: durableDirectory,
            legacyBaseDirectory: legacyDirectory
        )

        store.pruneRecordings(keeping: [keptDurableURL, keptLegacyURL])

        XCTAssertTrue(FileManager.default.fileExists(atPath: keptDurableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptLegacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedDurableURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedLegacyURL.path))
    }

    func testDeletesRecordingsFromBothManagedDirectoriesOnly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let durableDirectory = root.appendingPathComponent("audio", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy-audio", isDirectory: true)
        let siblingDirectory = root.appendingPathComponent("audio-backup", isDirectory: true)
        for directory in [durableDirectory, legacyDirectory, siblingDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let durableURL = durableDirectory.appendingPathComponent("durable.wav")
        let legacyURL = legacyDirectory.appendingPathComponent("legacy.wav")
        let siblingURL = siblingDirectory.appendingPathComponent("outside.wav")
        for url in [durableURL, legacyURL, siblingURL] {
            try Data([0x01]).write(to: url)
        }
        let store = RawRecordingStore(
            baseDirectory: durableDirectory,
            legacyBaseDirectory: legacyDirectory
        )

        store.deleteRecording(at: durableURL)
        store.deleteRecording(at: legacyURL)
        store.deleteRecording(at: siblingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: durableURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
