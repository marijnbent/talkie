import AppKit
import XCTest
@testable import TalkieCore

@MainActor
final class RecordingRuntimeTests: XCTestCase {
    private struct RuntimeHarness {
        let runtime: RecordingRuntime
        let audio: FakeAudioCapturePort
        let deepgram: FakeTranscriptionStreamPort
        let scheduler: ManualScheduler
        let statuses: Box<[AppStatus]>
        let finalizations: Box<[RecordingFinalization]>
        let rawRecordingCapture: FakeRawRecordingCapture
    }

    func testReconnectsOnceThenStopsRetryingAndFinalizes() async {
        let harness = makeHarness()

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        XCTAssertEqual(harness.runtime.phase, .recording)
        XCTAssertEqual(harness.deepgram.connectCalls.count, 1)

        harness.deepgram.emitConnectionDropped("first")
        await Task.yield()
        harness.scheduler.advance(by: 0.4)
        await Task.yield()
        XCTAssertEqual(harness.deepgram.connectCalls.count, 2)

        harness.deepgram.emitConnectionDropped("second")
        await Task.yield()
        harness.scheduler.advance(by: 0.4)
        await Task.yield()
        XCTAssertEqual(harness.deepgram.connectCalls.count, 2, "Should not reconnect more than once")
        XCTAssertEqual(harness.statuses.value.last, .connectionLostReleaseToFinalize)

        harness.runtime.handle(action: .stop)
        XCTAssertEqual(harness.runtime.phase, .finalizing)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        XCTAssertEqual(harness.deepgram.closeStreamCallCount, 1)

        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }
        XCTAssertEqual(harness.finalizations.value.count, 1)
        XCTAssertEqual(harness.runtime.phase, .idle)
    }

    func testDoesNotReconnectWhileFinalizing() async {
        let harness = makeHarness()

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        XCTAssertEqual(harness.runtime.phase, .finalizing)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }

        harness.deepgram.emitConnectionDropped("during finalize")
        await Task.yield()
        harness.scheduler.advance(by: 1.0)
        await Task.yield()

        XCTAssertEqual(harness.deepgram.connectCalls.count, 1)
    }

    func testCancelFromEscWhileFinalizingStopsSessionWithoutFinalizing() async {
        let harness = makeHarness()
        var overlayUpdates: [(Bool, String)] = []
        harness.runtime.onOverlayUpdate = { visible, label, _ in
            overlayUpdates.append((visible, label))
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        XCTAssertEqual(harness.runtime.phase, .finalizing)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }

        harness.runtime.cancelFromEsc()
        XCTAssertEqual(harness.runtime.phase, .idle)
        XCTAssertEqual(harness.deepgram.disconnectCallCount, 1)
        XCTAssertEqual(harness.finalizations.value.count, 0)
        XCTAssertEqual(overlayUpdates.last?.0, false)

        harness.deepgram.completeClose()
        await Task.yield()
        XCTAssertEqual(harness.finalizations.value.count, 0)
    }

    func testFinalizeIncludesResolvedEnhancementPromptMetadata() async {
        let enhancement = EnhancementPromptContext(
            name: "Slack tidy",
            content: "clean this",
            isForActiveApp: true
        )
        let harness = makeHarness(
            resolvedEnhancementPromptProvider: { _, _ in enhancement }
        )

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }

        XCTAssertEqual(harness.finalizations.value.first?.enhancementPrompt, enhancement)
    }

    func testFinalizeIncludesSavedRawRecordingAndLanguage() async {
        let recordingURL = URL(fileURLWithPath: "/tmp/test-recording.wav")
        let harness = makeHarness()
        harness.rawRecordingCapture.finishResult = recordingURL

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }

        XCTAssertEqual(harness.finalizations.value.first?.rawRecordingFileURL, recordingURL)
        XCTAssertEqual(harness.finalizations.value.first?.transcriptionLanguage, .automatic)
        XCTAssertEqual(harness.rawRecordingCapture.finishCallCount, 1)
    }

    func testCapturesActiveAppPromptAndIconAtRecordingStart() async {
        let slackIcon = NSImage(size: NSSize(width: 18, height: 18))
        var activeApplication = ActiveApplicationContext(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            icon: slackIcon
        )
        let harness = makeHarness(
            activeApplicationProvider: { activeApplication },
            resolvedEnhancementPromptProvider: { _, bundleIdentifier in
                guard bundleIdentifier == "com.tinyspeck.slackmacgap" else { return nil }
                return EnhancementPromptContext(
                    name: "Slack tidy",
                    content: "clean this",
                    isForActiveApp: true
                )
            }
        )
        var overlayUpdates: [(Bool, String, Bool)] = []
        harness.runtime.onOverlayUpdate = { visible, label, icon in
            overlayUpdates.append((visible, label, icon != nil))
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))

        activeApplication = ActiveApplicationContext(
            bundleIdentifier: "com.apple.TextEdit",
            icon: nil
        )

        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }

        XCTAssertEqual(harness.finalizations.value.first?.enhancementPrompt?.name, "Slack tidy")
        XCTAssertEqual(overlayUpdates.first?.0, true)
        XCTAssertEqual(overlayUpdates.first?.1, "Listening")
        XCTAssertEqual(overlayUpdates.first?.2, true)
        XCTAssertEqual(overlayUpdates.last?.1, "Enhancing")
        XCTAssertEqual(overlayUpdates.last?.2, true)
    }

    func testStopKeepsOverlayVisibleWithoutEnhancementUntilPasteFlowTakesOver() async {
        let harness = makeHarness()
        var overlayUpdates: [(Bool, String, Bool)] = []
        harness.runtime.onOverlayUpdate = { visible, label, icon in
            overlayUpdates.append((visible, label, icon != nil))
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        harness.runtime.handle(action: .stop)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }

        XCTAssertEqual(overlayUpdates.count, 2)
        XCTAssertEqual(overlayUpdates[0].0, true)
        XCTAssertEqual(overlayUpdates[0].1, "Listening")
        XCTAssertEqual(overlayUpdates[1].0, true)
        XCTAssertEqual(overlayUpdates[1].1, "Listening")
    }

    func testChangingLanguageWhileRecordingReconnectsAndFinalizesWithNewLanguage() async {
        var resolvedLanguage = DeepgramLanguage.english
        let harness = makeHarness(
            resolvedTranscriptionLanguageProvider: { _ in resolvedLanguage }
        )
        var finalizedInterimCount = 0
        harness.runtime.onFinalizeLatestInterim = {
            finalizedInterimCount += 1
        }

        let ownerID = UUID()
        harness.runtime.handle(action: .start(ownerShortcutID: ownerID, ownerMode: .hold, latched: false))
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        XCTAssertEqual(harness.deepgram.connectCalls.map(\.language), [.english])

        resolvedLanguage = .french
        harness.runtime.changeTranscriptionLanguage(to: .french)

        XCTAssertEqual(harness.deepgram.connectCalls.map(\.language), [.english, .french])
        XCTAssertEqual(finalizedInterimCount, 1)

        harness.runtime.handle(action: .stop)
        await waitUntil { harness.deepgram.closeStreamCallCount == 1 }
        harness.deepgram.completeClose()
        await waitUntil { harness.finalizations.value.count == 1 }

        XCTAssertEqual(harness.finalizations.value.first?.transcriptionLanguage, .french)
    }

    func testUsesSelectedTranscriptionProviderSettings() async {
        let harness = makeHarness(
            transcriptionSettingsProvider: {
                TranscriptionProviderSettings(provider: .elevenLabs, apiKey: "eleven-key")
            }
        )

        harness.runtime.handle(
            action: .start(ownerShortcutID: UUID(), ownerMode: .hold, latched: false)
        )
        await waitUntil { harness.deepgram.connectCalls.count == 1 }

        XCTAssertEqual(harness.deepgram.connectCalls.first?.provider, .elevenLabs)
        XCTAssertEqual(harness.deepgram.connectCalls.first?.apiKey, "eleven-key")
    }

    func testRoutesOneConvertedChunkToRawCaptureAndTranscriptionStream() async {
        let harness = makeHarness()
        harness.runtime.handle(
            action: .start(ownerShortcutID: UUID(), ownerMode: .hold, latched: false)
        )
        await waitUntil { harness.deepgram.connectCalls.count == 1 }
        let audioData = Data([0x10, 0x00, 0x20, 0x00])

        harness.audio.emit(Linear16AudioChunk(data: audioData, meterLevel: 0.5))

        XCTAssertEqual(harness.rawRecordingCapture.appendedAudio, [audioData])
        XCTAssertEqual(harness.deepgram.sentAudio, [audioData])
    }

    func testCancelDuringPendingCaptureStartCannotOpenAStaleSession() async {
        let harness = makeHarness()
        harness.audio.suspendStart = true
        harness.runtime.handle(
            action: .start(ownerShortcutID: UUID(), ownerMode: .hold, latched: false)
        )
        let sessionID = try! XCTUnwrap(harness.runtime.ownership?.sessionID)
        await waitUntil { harness.audio.hasPendingStart }

        harness.runtime.cancelFromEsc()
        XCTAssertEqual(harness.runtime.phase, .idle)
        harness.audio.completeStart()
        await waitUntil { harness.audio.stoppedSessionIDs.contains(sessionID) }

        XCTAssertTrue(harness.deepgram.connectCalls.isEmpty)
        XCTAssertTrue(harness.rawRecordingCapture.appendedAudio.isEmpty)
        XCTAssertTrue(harness.finalizations.value.isEmpty)
        XCTAssertNil(harness.runtime.ownership)
    }

    private func makeHarness(
        activeApplicationProvider: @escaping () -> ActiveApplicationContext? = { nil },
        resolvedTranscriptionLanguageProvider: @escaping (String?) -> DeepgramLanguage = { _ in .automatic },
        transcriptionSettingsProvider: @escaping () -> TranscriptionProviderSettings = {
            TranscriptionProviderSettings(provider: .deepgram, apiKey: "dg_key")
        },
        resolvedEnhancementPromptProvider: @escaping (UUID?, String?) -> EnhancementPromptContext? = { _, _ in nil }
    ) -> RuntimeHarness {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let audio = FakeAudioCapturePort()
        let deepgram = FakeTranscriptionStreamPort()
        let sound = FakeSoundPort()
        let rawRecordingCapture = FakeRawRecordingCapture()

        let statuses = Box<[AppStatus]>([])
        let finalizations = Box<[RecordingFinalization]>([])

        let runtime = RecordingRuntime(
            audioCapture: audio,
            transcriptionStream: deepgram,
            scheduler: scheduler,
            clock: clock,
            activeApplicationProvider: activeApplicationProvider,
            audioInputSelectionProvider: {
                ResolvedAudioInputSelection(
                    selection: .systemDefault,
                    selectedDevice: nil,
                    systemDefaultDevice: nil
                )
            },
            resolvedTranscriptionLanguageProvider: resolvedTranscriptionLanguageProvider,
            transcriptionSettingsProvider: transcriptionSettingsProvider,
            resolvedEnhancementPromptProvider: resolvedEnhancementPromptProvider,
            playSoundEffectsEnabledProvider: { false },
            muteDuringRecordingProvider: { false },
            rawRecordingCaptureProvider: { _ in rawRecordingCapture },
            soundPort: sound
        )

        runtime.onStatus = { status in
            statuses.value.append(status)
        }
        runtime.onFinalizeRequested = { finalization in
            finalizations.value.append(finalization)
        }

        return RuntimeHarness(
            runtime: runtime,
            audio: audio,
            deepgram: deepgram,
            scheduler: scheduler,
            statuses: statuses,
            finalizations: finalizations,
            rawRecordingCapture: rawRecordingCapture
        )
    }

    private func waitUntil(
        _ message: String = "Timed out waiting for asynchronous runtime work.",
        condition: () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail(message)
    }
}

private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
