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

    func testRoutesMuseRecordingToMuse() {
        let deepgram = FakeTranscriptionStreamPort()
        let elevenLabs = FakeTranscriptionStreamPort()
        let muse = FakeTranscriptionStreamPort()
        let router = TranscriptionStreamRouter(
            deepgram: deepgram,
            elevenLabs: elevenLabs,
            muse: muse
        )
        let settings = TranscriptionProviderSettings(provider: .muse, apiKey: "muse-key")

        router.connect(
            settings: settings,
            format: AudioStreamFormat(sampleRate: 48_000, channels: 2),
            language: .dutch
        )

        XCTAssertTrue(deepgram.connectCalls.isEmpty)
        XCTAssertTrue(elevenLabs.connectCalls.isEmpty)
        XCTAssertEqual(muse.connectCalls.first?.provider, .muse)
        XCTAssertEqual(muse.connectCalls.first?.apiKey, "muse-key")
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
