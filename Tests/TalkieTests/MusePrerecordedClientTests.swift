import Foundation
import XCTest
@testable import TalkieCore

final class MusePrerecordedClientTests: XCTestCase {
    func testNormalizesSavedRecordingToMono24KHzWAV() throws {
        let source = makeWAV(sampleRate: 48_000, channels: 2, frameCount: 480)
        let normalized = try MusePrerecordedClient.normalizedWAV(source)

        XCTAssertEqual(readUInt16(normalized, at: 22), 1)
        XCTAssertEqual(readUInt32(normalized, at: 24), 24_000)
        XCTAssertEqual(readUInt16(normalized, at: 34), 16)
        XCTAssertEqual(readUInt32(normalized, at: 40), 480)
        XCTAssertEqual(normalized.count, 44 + 480)
    }

    func testMultipartBodyContainsRequestAndAudioParts() throws {
        let body = try MusePrerecordedClient.makeMultipartBody(
            wavData: Data("RIFF-test".utf8),
            language: .dutch,
            boundary: "test-boundary"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("name=\"request\""))
        XCTAssertTrue(text.contains("muse-voice-transcribe-1.0"))
        XCTAssertTrue(text.contains("\"languageBias\":[\"Dutch\"]"))
        XCTAssertTrue(text.contains("name=\"audio\""))
        XCTAssertTrue(text.contains("Content-Type: audio/wav"))
        XCTAssertTrue(text.hasSuffix("\r\n--test-boundary--\r\n"))
    }

    func testAutomaticMultipartRequestUsesSelectedBiases() throws {
        let body = try MusePrerecordedClient.makeMultipartBody(
            wavData: Data("RIFF-test".utf8),
            language: .automatic,
            automaticLanguageCandidates: [.dutch, .english],
            boundary: "test-boundary"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("\"languageBias\":[\"Dutch\",\"English\"]"))
    }

    private func makeWAV(sampleRate: UInt32, channels: UInt16, frameCount: Int) -> Data {
        let pcmByteCount = UInt32(frameCount * Int(channels) * 2)
        var data = Data()
        data.append(Data("RIFF".utf8))
        appendLittleEndian(UInt32(36) + pcmByteCount, to: &data)
        data.append(Data("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(channels) * 2, to: &data)
        appendLittleEndian(channels * 2, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        appendLittleEndian(pcmByteCount, to: &data)
        let samples = [Int16](repeating: 1_000, count: Int(pcmByteCount) / 2)
        data.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
        return data
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
