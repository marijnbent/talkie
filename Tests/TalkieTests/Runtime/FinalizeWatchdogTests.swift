import XCTest
@testable import TalkieCore

@MainActor
final class FinalizeWatchdogTests: XCTestCase {
    func testElevenLabsFinalizationAllowsTimeForCommittedTranscript() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let audio = FakeAudioCapturePort()
        let elevenLabs = FakeTranscriptionStreamPort()
        let sound = FakeSoundPort()

        var finalizationCount = 0

        let runtime = RecordingRuntime(
            audioCapture: audio,
            transcriptionStream: elevenLabs,
            scheduler: scheduler,
            clock: clock,
            activeApplicationProvider: { nil },
            audioInputSelectionProvider: {
                ResolvedAudioInputSelection(
                    selection: .systemDefault,
                    selectedDevice: nil,
                    systemDefaultDevice: nil
                )
            },
            resolvedTranscriptionLanguageProvider: { _ in .automatic },
            transcriptionSettingsProvider: {
                TranscriptionProviderSettings(provider: .elevenLabs, apiKey: "eleven_key")
            },
            resolvedEnhancementPromptProvider: { _, _ in nil },
            playSoundEffectsEnabledProvider: { false },
            muteDuringRecordingProvider: { false },
            soundPort: sound
        )

        runtime.onFinalizeRequested = { _ in
            finalizationCount += 1
        }

        runtime.handle(action: .start(ownerShortcutID: UUID(), ownerMode: .click, latched: true))
        await waitUntil { elevenLabs.connectCalls.count == 1 }
        runtime.handle(action: .stop)
        await waitUntil { elevenLabs.closeStreamCallCount == 1 }

        scheduler.advance(by: 1.2)
        await Task.yield()
        XCTAssertEqual(finalizationCount, 0)

        scheduler.advance(by: 2.3)
        await waitUntil { finalizationCount == 1 }
    }

    func testWatchdogFinalizesOnceAndIgnoresLateCloseCallback() async {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let audio = FakeAudioCapturePort()
        let deepgram = FakeTranscriptionStreamPort()
        let sound = FakeSoundPort()

        var finalizationCount = 0

        let runtime = RecordingRuntime(
            audioCapture: audio,
            transcriptionStream: deepgram,
            scheduler: scheduler,
            clock: clock,
            activeApplicationProvider: { nil },
            audioInputSelectionProvider: {
                ResolvedAudioInputSelection(
                    selection: .systemDefault,
                    selectedDevice: nil,
                    systemDefaultDevice: nil
                )
            },
            resolvedTranscriptionLanguageProvider: { _ in .automatic },
            transcriptionSettingsProvider: {
                TranscriptionProviderSettings(provider: .deepgram, apiKey: "dg_key")
            },
            resolvedEnhancementPromptProvider: { _, _ in
                EnhancementPromptContext(
                    name: "Clean",
                    content: "clean this",
                    isForActiveApp: false
                )
            },
            playSoundEffectsEnabledProvider: { false },
            muteDuringRecordingProvider: { false },
            soundPort: sound
        )

        runtime.onFinalizeRequested = { _ in
            finalizationCount += 1
        }

        let ownerID = UUID()
        runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .click, latched: true))
        await waitUntil { deepgram.connectCalls.count == 1 }
        runtime.handle(action: .stop)
        XCTAssertEqual(runtime.phase, .finalizing)
        await waitUntil { deepgram.closeStreamCallCount == 1 }

        scheduler.advance(by: 1.2)
        await waitUntil { finalizationCount == 1 }

        XCTAssertEqual(finalizationCount, 1)
        XCTAssertEqual(runtime.phase, .idle)

        deepgram.completeClose()
        await Task.yield()

        XCTAssertEqual(finalizationCount, 1, "Late close callback must not double-finalize")
    }

    private func waitUntil(condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous runtime work.")
    }
}
