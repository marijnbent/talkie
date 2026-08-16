import Foundation
import XCTest
@testable import TalkieCore

final class TranscriptionStreamRouterTests: XCTestCase {
    func testRoutesARecordingToTheSelectedProvider() {
        let deepgram = FakeTranscriptionStreamPort()
        let elevenLabs = FakeTranscriptionStreamPort()
        let router = TranscriptionStreamRouter(deepgram: deepgram, elevenLabs: elevenLabs)
        let settings = TranscriptionProviderSettings(provider: .elevenLabs, apiKey: "eleven-key")
        let format = AudioStreamFormat(sampleRate: 16_000, channels: 1)
        let audio = Data([0x01, 0x02])

        router.connect(settings: settings, format: format, language: .english)
        router.sendAudio(data: audio)

        XCTAssertTrue(deepgram.connectCalls.isEmpty)
        XCTAssertTrue(deepgram.sentAudio.isEmpty)
        XCTAssertEqual(elevenLabs.connectCalls.first?.provider, .elevenLabs)
        XCTAssertEqual(elevenLabs.connectCalls.first?.apiKey, "eleven-key")
        XCTAssertEqual(elevenLabs.sentAudio, [audio])
    }

    func testIgnoresEventsFromAnInactiveProvider() {
        let deepgram = FakeTranscriptionStreamPort()
        let elevenLabs = FakeTranscriptionStreamPort()
        let router = TranscriptionStreamRouter(deepgram: deepgram, elevenLabs: elevenLabs)
        var transcripts: [String] = []
        router.onTranscriptEvent = { text, _ in transcripts.append(text) }

        router.connect(
            settings: TranscriptionProviderSettings(provider: .elevenLabs, apiKey: "key"),
            format: AudioStreamFormat(sampleRate: 16_000, channels: 1),
            language: .automatic
        )
        deepgram.emitTranscript("inactive", isFinal: true)
        elevenLabs.emitTranscript("active", isFinal: true)

        XCTAssertEqual(transcripts, ["active"])
    }
}
