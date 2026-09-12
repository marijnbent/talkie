import Foundation
import XCTest
@testable import TalkieCore

final class MuseClientTests: XCTestCase {
    func testMissingHandshakeStopsAtTheAudioBudget() {
        let socket = TestMuseSocket()
        let dropped = expectation(description: "Audio budget reached")
        let client = MuseClient(
            onConnectionDropped: { _ in dropped.fulfill() },
            maximumPendingAudioBytes: 4,
            makeSocket: { _ in socket }
        )
        client.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 24_000, channels: 1), language: .english, automaticLanguageCandidates: [])
        client.sendAudio(data: Data([1, 0, 2, 0]))
        client.sendAudio(data: Data([3, 0]))
        wait(for: [dropped], timeout: 2)
        client.disconnect()
        XCTAssertEqual(socket.cancelCount, 1)
        XCTAssertTrue(socket.audio.isEmpty)
    }

    func testMissingHandshakeTimesOutWithoutAudio() {
        let socket = TestMuseSocket()
        let dropped = expectation(description: "Handshake timed out")
        let client = MuseClient(
            onConnectionDropped: { _ in dropped.fulfill() },
            handshakeTimeout: 0.02,
            makeSocket: { _ in socket }
        )
        client.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 24_000, channels: 1), language: .english, automaticLanguageCandidates: [])
        wait(for: [dropped], timeout: 2)
        client.disconnect()
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testHandshakeFlushesAudioInOrderAndOldSocketCannotAcknowledgeNewSession() {
        let first = TestMuseSocket()
        let second = TestMuseSocket()
        let sockets = TestMuseSocketPool([first, second])
        var transcripts: [String] = []
        let client = MuseClient(onTranscriptEvent: { text, _ in transcripts.append(text) }, makeSocket: { _ in sockets.next() })
        let format = AudioStreamFormat(sampleRate: 24_000, channels: 1)
        client.connect(apiKey: "test", format: format, language: .english, automaticLanguageCandidates: [])
        client.sendAudio(data: Data([1, 0]))
        client.connect(apiKey: "test", format: format, language: .english, automaticLanguageCandidates: [])
        client.sendAudio(data: Data([2, 0]))
        first.deliver("{\"sessionId\":\"old\"}")
        XCTAssertTrue(second.audio.isEmpty)
        second.deliver("{\"sessionId\":\"new\"}")
        client.sendAudio(data: Data([3, 0]))
        second.deliver("{\"type\":\"transcript\",\"transcript\":\"current\",\"final\":true}")
        client.disconnect()
        XCTAssertEqual(second.audio, [Data([2, 0]), Data([3, 0])])
        XCTAssertEqual(transcripts, ["current"])
    }

    func testHandshakeUsesFirstFrameAuthenticationAndDutchBias() throws {
        let text = try MuseClient.makeHandshake(
            apiKey: "test-key",
            audioEncoding: "PCM_24KHZ",
            language: .dutch
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let authorization = try XCTUnwrap(object["authorization"] as? [String: String])

        XCTAssertEqual(authorization["accessToken"], "Bearer test-key")
        XCTAssertEqual(object["audioEncoding"] as? String, "PCM_24KHZ")
        XCTAssertEqual(object["model"] as? String, "muse-voice-transcribe-1.0")
        XCTAssertEqual(object["mode"] as? String, "PUSH_TO_TALK")
        XCTAssertEqual(object["partialMode"] as? String, "CUMULATIVE")
        XCTAssertEqual(object["emitAudioProgress"] as? Bool, false)
        XCTAssertEqual(object["languageBias"] as? [String], ["Dutch"])
    }

    func testAutomaticLanguageUsesSelectedBiases() throws {
        let text = try MuseClient.makeHandshake(
            apiKey: "test-key",
            audioEncoding: "PCM_16KHZ",
            language: .automatic,
            automaticLanguageCandidates: [.dutch, .english]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["languageBias"] as? [String], ["Dutch", "English"])
    }

    func testServerMessagesDecodeHandshakeTranscriptAndError() throws {
        let decoder = JSONDecoder()
        let handshake = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"sessionId\":\"session-1\"}".utf8)
        )
        let transcript = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"type\":\"transcript\",\"transcript\":\"Hallo\",\"final\":true}".utf8)
        )
        let error = try decoder.decode(
            MuseServerMessage.self,
            from: Data("{\"type\":\"error\",\"message\":\"Invalid request\"}".utf8)
        )

        XCTAssertEqual(handshake.sessionId, "session-1")
        XCTAssertEqual(transcript.transcript, "Hallo")
        XCTAssertEqual(transcript.final, true)
        XCTAssertEqual(error.message, "Invalid request")
    }

    func testConverterDownmixesAndResamplesAcrossChunks() {
        let frames: [Int16] = (0..<480).flatMap { frame in
            [Int16(frame), Int16(frame + 2)]
        }
        let data = frames.withUnsafeBufferPointer { Data(buffer: $0) }

        let complete = MusePCMConverter(
            format: AudioStreamFormat(sampleRate: 48_000, channels: 2)
        )
        var completeOutput = complete.convert(data)
        completeOutput.append(complete.finish())

        let chunked = MusePCMConverter(
            format: AudioStreamFormat(sampleRate: 48_000, channels: 2)
        )
        let midpoint = data.count / 2
        var chunkedOutput = chunked.convert(Data(data[..<midpoint]))
        chunkedOutput.append(chunked.convert(Data(data[midpoint...])))
        chunkedOutput.append(chunked.finish())

        XCTAssertEqual(complete.audioEncoding, "PCM_24KHZ")
        XCTAssertEqual(completeOutput.count, 240 * MemoryLayout<Int16>.size)
        XCTAssertEqual(chunkedOutput, completeOutput)
    }

    func testConverterRetainsOnlyTheNeededSampleAcrossSingleFrameChunks() {
        for sourceRate in [12_000, 16_000, 24_000, 48_000, 96_000] {
            let frames: [Int16] = (0..<48).flatMap { frame -> [Int16] in
                let sample = Int16(frame * 100)
                return [sample, sample + 2]
            }
            let data = frames.withUnsafeBufferPointer { Data(buffer: $0) }
            let format = AudioStreamFormat(sampleRate: sourceRate, channels: 2)
            let complete = MusePCMConverter(format: format)
            var expected = complete.convert(data)
            expected.append(complete.finish())

            let chunked = MusePCMConverter(format: format)
            var actual = Data()
            for offset in stride(from: 0, to: data.count, by: 4) {
                actual.append(chunked.convert(data[offset..<(offset + 4)]))
                actual.append(chunked.convert(Data()))
            }
            actual.append(chunked.finish())
            XCTAssertEqual(actual, expected, "Source rate: \(sourceRate)")
            XCTAssertEqual(chunked.finish(), Data())
        }
    }

    func testConverterPassesThroughCompleteMonoSamples() {
        let converter = MusePCMConverter(format: AudioStreamFormat(sampleRate: 24_000, channels: 1))
        XCTAssertEqual(converter.convert(Data([0, 128, 255, 127, 42])), Data([0, 128, 255, 127]))
        XCTAssertEqual(converter.finish(), Data())
    }
}

private final class TestMuseSocket: MuseSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var receiveHandler: (@Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    private var sentAudio: [Data] = []
    private var cancellations = 0
    var audio: [Data] { lock.withLock { sentAudio } }
    var cancelCount: Int { lock.withLock { cancellations } }

    func resume() {}

    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        if case .data(let data) = message {
            lock.withLock { sentAudio.append(data) }
        }
        completionHandler(nil)
    }

    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        lock.withLock { receiveHandler = completionHandler }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.withLock { cancellations += 1 }
    }

    func deliver(_ text: String) {
        let handler = lock.withLock {
            defer { receiveHandler = nil }
            return receiveHandler
        }
        handler?(.success(.string(text)))
    }
}

private final class TestMuseSocketPool: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [TestMuseSocket]

    init(_ sockets: [TestMuseSocket]) { self.sockets = sockets }
    func next() -> TestMuseSocket { lock.withLock { sockets.removeFirst() } }
}
