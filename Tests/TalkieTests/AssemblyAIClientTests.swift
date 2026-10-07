import Foundation
import XCTest
@testable import TalkieCore

final class AssemblyAIClientTests: XCTestCase {
    func testRequestUsesDutchEnglishSteeringAndHeaderAuthentication() throws {
        let request = AssemblyAIClient.makeRequest(apiKey: "test-key", sampleRate: 48_000, language: .automatic, candidates: [.dutch, .english])
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
        XCTAssertFalse(url.absoluteString.contains("test-key"))
        XCTAssertEqual(values["speech_model"], "universal-3-6-pro")
        XCTAssertEqual(values["sample_rate"], "48000")
        XCTAssertEqual(values["language_codes"], "[\"nl\",\"en\"]")
        XCTAssertEqual(AssemblyAIClient.languageCodes(for: .englishBritish, candidates: [.dutch]), ["en"])
        XCTAssertEqual(AssemblyAIClient.languageCodes(for: .automatic, candidates: []), ["nl", "en"])
    }

    func testFinalizationWaitsForAudioAndFinalTurnBeforeCompletion() {
        let socket = AssemblyAITestSocket()
        let closed = expectation(description: "Closed after final")
        let terminated = expectation(description: "Terminate sent")
        socket.onTerminate = { terminated.fulfill() }
        let events = AssemblyAITestEvents()
        let client = AssemblyAIClient(onTranscriptEvent: { text, final in events.append(text, final) }, makeSocket: { _ in socket })
        client.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 16_000, channels: 2), language: .automatic, automaticLanguageCandidates: [.dutch, .english])
        let samples: [Int16] = [100, 300, 200, 400]
        client.sendAudio(data: samples.withUnsafeBufferPointer { Data(buffer: $0) })
        client.closeStream { closed.fulfill() }
        XCTAssertTrue(socket.messages.isEmpty)
        socket.deliver(#"{"type":"Begin"}"#)
        wait(for: [terminated], timeout: 2)
        socket.deliver(#"{"type":"Turn","turn_order":0,"transcript":"Hallo","end_of_turn":false}"#)
        socket.deliver(#"{"type":"Turn","turn_order":0,"transcript":"Hallo world.","end_of_turn":true}"#)
        socket.deliver(#"{"type":"Turn","turn_order":0,"transcript":"Hallo world.","end_of_turn":true}"#)
        socket.deliver(#"{"type":"Termination"}"#)
        wait(for: [closed], timeout: 2)
        XCTAssertEqual(events.texts, ["Hallo", "Hallo world."])
        XCTAssertEqual(events.finals, [false, true])
        guard case .data(let audio) = socket.messages.first else { return XCTFail("Audio must precede termination") }
        XCTAssertEqual(audio.count, 3_200)
        XCTAssertEqual(Array(audio.prefix(4)), [200, 0, 44, 1])
        XCTAssertEqual(socket.messages.count, 2)
        client.disconnect()
    }

    func testHandshakeAndFinalizationTimeoutsReportFailure() {
        let dropped = expectation(description: "Handshake failed")
        let first = AssemblyAITestSocket()
        let client = AssemblyAIClient(onConnectionDropped: { _ in dropped.fulfill() }, handshakeTimeout: 0.02, makeSocket: { _ in first })
        client.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 16_000, channels: 1), language: .automatic, automaticLanguageCandidates: [])
        wait(for: [dropped], timeout: 2)
        client.disconnect()

        let error = expectation(description: "Finalization failed")
        let closed = expectation(description: "Completion still called")
        let second = AssemblyAITestSocket()
        let closing = AssemblyAIClient(onTranscriptionError: { _ in error.fulfill() }, closeTimeout: 0.02, makeSocket: { _ in second })
        closing.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 16_000, channels: 1), language: .automatic, automaticLanguageCandidates: [])
        closing.closeStream { closed.fulfill() }
        wait(for: [error, closed], timeout: 2)
        closing.disconnect()
    }

    func testProviderErrorStopsSessionWithoutReconnection() {
        let failed = expectation(description: "Authentication failed")
        let socket = AssemblyAITestSocket()
        let client = AssemblyAIClient(onTranscriptionError: { _ in failed.fulfill() }, onConnectionDropped: { _ in XCTFail("Do not retry provider errors") }, makeSocket: { _ in socket })
        client.connect(apiKey: "test", format: AudioStreamFormat(sampleRate: 16_000, channels: 1), language: .automatic, automaticLanguageCandidates: [])
        socket.deliver(#"{"type":"Error","error":"Invalid API key"}"#)
        wait(for: [failed], timeout: 2)
        client.disconnect()
        XCTAssertTrue(socket.cancelled)
    }

    func testPrerecordedLanguageOptionsAndRouter() throws {
        let data = try AssemblyAIPrerecordedClient.makeRequestBody(audioURL: "https://example.com/audio.wav", language: .automatic, candidates: [.dutch, .english])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let options = try XCTUnwrap(body["language_detection_options"] as? [String: Any])
        XCTAssertEqual(options["expected_languages"] as? [String], ["nl", "en"])
        XCTAssertEqual(body["language_detection"] as? Bool, true)
        let stream = FakeTranscriptionStreamPort()
        let router = TranscriptionStreamRouter(assemblyAI: stream)
        router.connect(settings: TranscriptionProviderSettings(provider: .assemblyAI, apiKey: "test"), format: AudioStreamFormat(sampleRate: 16_000, channels: 1), language: .automatic)
        router.sendAudio(data: Data([0, 1]))
        XCTAssertEqual(stream.connectCalls.first?.provider, .assemblyAI)
        XCTAssertEqual(stream.sentAudio, [Data([0, 1])])
        router.disconnect()
    }
}

private final class AssemblyAITestEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(String, Bool)] = []
    var texts: [String] { lock.withLock { events.map(\.0) } }
    var finals: [Bool] { lock.withLock { events.map(\.1) } }
    func append(_ text: String, _ final: Bool) { lock.withLock { events.append((text, final)) } }
}

private final class AssemblyAITestSocket: AssemblyAISocket, @unchecked Sendable {
    private let condition = NSCondition()
    private var handler: (@Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    private var sent: [URLSessionWebSocketTask.Message] = []
    private var didCancel = false
    var onTerminate: (() -> Void)?
    var messages: [URLSessionWebSocketTask.Message] { condition.withLock { sent } }
    var cancelled: Bool { condition.withLock { didCancel } }
    func resume() {}
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { condition.withLock { didCancel = true } }
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        condition.withLock { sent.append(message) }
        completionHandler(nil)
        if case .string(let text) = message, text.contains("Terminate") { onTerminate?() }
    }
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        condition.withLock { handler = completionHandler; condition.signal() }
    }
    func deliver(_ text: String) {
        condition.lock()
        let deadline = Date().addingTimeInterval(2)
        while handler == nil {
            if !condition.wait(until: deadline) { condition.unlock(); XCTFail("No receiver"); return }
        }
        let callback = handler
        handler = nil
        condition.unlock()
        callback?(.success(.string(text)))
    }
}
