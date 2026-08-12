import Foundation
import AppKit

struct ActiveApplicationContext {
    let bundleIdentifier: String?
    let icon: NSImage?
}

struct EnhancementPromptContext: Equatable {
    let name: String
    let content: String
    let isForActiveApp: Bool
}

struct RecordingFinalization {
    let enhancementPrompt: EnhancementPromptContext?
    let transcriptionError: String?
    let rawRecordingFileURL: URL?
    let transcriptionLanguage: DeepgramLanguage?
}

private final class RecordingAudioRouter: @unchecked Sendable {
    private let deepgram: DeepgramPort
    private let lock = NSLock()
    private let publishInterval: UInt64 = 33_000_000

    private var sessionID: UUID?
    private var rawCapture: RawRecordingCapture?
    private var smoothedLevel: Float = 0
    private var lastPublishedLevel: Float = 0
    private var lastPublishTime: UInt64 = 0
    private var levelHandler: (@Sendable (UUID, Float) -> Void)?

    init(deepgram: DeepgramPort) {
        self.deepgram = deepgram
    }

    var onLevel: (@Sendable (UUID, Float) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return levelHandler
        }
        set {
            lock.lock()
            levelHandler = newValue
            lock.unlock()
        }
    }

    func activate(sessionID: UUID, rawCapture: RawRecordingCapture) {
        lock.lock()
        self.sessionID = sessionID
        self.rawCapture = rawCapture
        smoothedLevel = 0
        lastPublishedLevel = 0
        lastPublishTime = 0
        lock.unlock()
    }

    func deactivate(sessionID: UUID) {
        lock.lock()
        guard self.sessionID == sessionID else {
            lock.unlock()
            return
        }
        self.sessionID = nil
        rawCapture = nil
        lock.unlock()
    }

    func route(sessionID: UUID, chunk: Linear16AudioChunk) {
        lock.lock()
        guard self.sessionID == sessionID, let rawCapture else {
            lock.unlock()
            return
        }

        // Both consumers keep the same immutable Data storage through copy-on-write.
        rawCapture.append(data: chunk.data)
        deepgram.sendAudio(data: chunk.data)

        smoothedLevel = (smoothedLevel * 0.78) + (chunk.meterLevel * 0.22)
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldPublish = lastPublishTime == 0
            || now - lastPublishTime >= publishInterval
            || abs(smoothedLevel - lastPublishedLevel) >= 0.12
        let handler = levelHandler
        let publishedLevel = smoothedLevel
        if shouldPublish {
            lastPublishedLevel = publishedLevel
            lastPublishTime = now
        }
        lock.unlock()

        if shouldPublish {
            handler?(sessionID, publishedLevel)
        }
    }
}

@MainActor
final class RecordingRuntime {
    private let audioCapture: AudioCapturePort
    private let deepgram: DeepgramPort
    private let audioRouter: RecordingAudioRouter
    private let scheduler: SchedulerPort
    private let clock: ClockPort

    private let activeApplicationProvider: () -> ActiveApplicationContext?
    private let audioInputSelectionProvider: () -> ResolvedAudioInputSelection
    private let resolvedTranscriptionLanguageProvider: (String?) -> DeepgramLanguage
    private let apiKeyProvider: () -> String
    private let resolvedEnhancementPromptProvider: (UUID?, String?) -> EnhancementPromptContext?
    private let playSoundEffectsEnabledProvider: () -> Bool
    private let muteDuringRecordingProvider: () -> Bool
    private let rawRecordingCaptureProvider: (AudioStreamFormat) -> RawRecordingCapture
    private let soundPort: SoundPort

    private let stopDelay: TimeInterval
    private let reconnectDelay: TimeInterval
    private let finalizeWatchdogTimeout: TimeInterval
    private let maxReconnectAttempts: Int

    private var stopTask: CancellableTask?
    private var reconnectTask: CancellableTask?
    private var finalizeWatchdogTask: CancellableTask?
    private var captureStartTask: Task<Void, Never>?
    private var captureStopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?

    private(set) var phase: RecordingPhase = .idle {
        didSet { onPhaseChanged?(phase) }
    }

    private(set) var ownership: RecordingOwnership? {
        didSet { onOwnershipChanged?(ownership) }
    }

    private var currentRecordingFormat: AudioStreamFormat?
    private var currentActiveApplication: ActiveApplicationContext?
    private var pendingTranscriptionError: String?
    private var pendingEnhancementPrompt: EnhancementPromptContext?
    private var pendingTranscriptionLanguage: DeepgramLanguage?
    private var rawRecordingCapture: RawRecordingCapture?
    private var deepgramReconnectAttempt = 0
    private var hasPlayedTranscriptionFailureSound = false
    private var didFinalizeCurrentSession = false
    private var pendingStopAfterCaptureStart = false

    var onStatus: ((AppStatus) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onPhaseChanged: ((RecordingPhase) -> Void)?
    var onOwnershipChanged: ((RecordingOwnership?) -> Void)?
    var onOverlayUpdate: ((Bool, String, NSImage?) -> Void)?
    var onAudioLevel: ((CGFloat) -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onWillStartRecording: (() -> Void)?
    var onFinalizeLatestInterim: (() -> Void)?
    var onFinalizeRequested: ((RecordingFinalization) -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onMuteForRecording: (() -> Void)?
    var onRestoreMute: (() -> Void)?

    init(
        audioCapture: AudioCapturePort,
        deepgram: DeepgramPort,
        scheduler: SchedulerPort,
        clock: ClockPort,
        activeApplicationProvider: @escaping () -> ActiveApplicationContext?,
        audioInputSelectionProvider: @escaping () -> ResolvedAudioInputSelection,
        resolvedTranscriptionLanguageProvider: @escaping (String?) -> DeepgramLanguage,
        apiKeyProvider: @escaping () -> String,
        resolvedEnhancementPromptProvider: @escaping (UUID?, String?) -> EnhancementPromptContext?,
        playSoundEffectsEnabledProvider: @escaping () -> Bool,
        muteDuringRecordingProvider: @escaping () -> Bool,
        rawRecordingCaptureProvider: @escaping (AudioStreamFormat) -> RawRecordingCapture = { format in
            RawRecordingStore().makeCapture(format: format)
        },
        soundPort: SoundPort,
        stopDelay: TimeInterval = 0.2,
        reconnectDelay: TimeInterval = 0.4,
        finalizeWatchdogTimeout: TimeInterval = 1.2,
        maxReconnectAttempts: Int = DeepgramReconnectPolicy.maxAttempts
    ) {
        self.audioCapture = audioCapture
        self.deepgram = deepgram
        self.audioRouter = RecordingAudioRouter(deepgram: deepgram)
        self.scheduler = scheduler
        self.clock = clock
        self.activeApplicationProvider = activeApplicationProvider
        self.audioInputSelectionProvider = audioInputSelectionProvider
        self.resolvedTranscriptionLanguageProvider = resolvedTranscriptionLanguageProvider
        self.apiKeyProvider = apiKeyProvider
        self.resolvedEnhancementPromptProvider = resolvedEnhancementPromptProvider
        self.playSoundEffectsEnabledProvider = playSoundEffectsEnabledProvider
        self.muteDuringRecordingProvider = muteDuringRecordingProvider
        self.rawRecordingCaptureProvider = rawRecordingCaptureProvider
        self.soundPort = soundPort
        self.stopDelay = stopDelay
        self.reconnectDelay = reconnectDelay
        self.finalizeWatchdogTimeout = finalizeWatchdogTimeout
        self.maxReconnectAttempts = maxReconnectAttempts

        let audioRouter = self.audioRouter
        audioRouter.onLevel = { [weak self] sessionID, level in
            Task { @MainActor in
                guard let self, self.ownership?.sessionID == sessionID, self.phase == .recording else {
                    return
                }
                self.onAudioLevel?(CGFloat(level))
            }
        }
        self.audioCapture.onAudioChunk = { [weak audioRouter] sessionID, chunk in
            audioRouter?.route(sessionID: sessionID, chunk: chunk)
        }
        self.audioCapture.onConfigurationChanged = { [weak self] sessionID in
            Task { @MainActor in
                self?.handleAudioInputConfigurationChanged(sessionID: sessionID)
            }
        }
        self.deepgram.onTranscriptEvent = { [weak self] text, isFinal in
            Task { @MainActor in
                self?.handleTranscriptEvent(text, isFinal: isFinal)
            }
        }
        self.deepgram.onLog = { [weak self] message, level in
            Task { @MainActor in
                self?.onLog?(message, level)
            }
        }
        self.deepgram.onTranscriptionError = { [weak self] message in
            Task { @MainActor in
                self?.handleTranscriptionError(message)
            }
        }
        self.deepgram.onConnectionDropped = { [weak self] reason in
            Task { @MainActor in
                self?.handleDeepgramConnectionDropped(reason: reason)
            }
        }
    }

    func handle(actions: [ShortcutAction]) {
        for action in actions {
            handle(action: action)
        }
    }

    func handle(action: ShortcutAction) {
        switch action {
        case .start(let ownerShortcutID, let ownerMode, let latched):
            startRecording(ownerShortcutID: ownerShortcutID, ownerMode: ownerMode, isLatched: latched)
        case .stop:
            stopRecording()
        case .cancel:
            cancelRecording()
        case .scheduleStop:
            scheduleStopRecording()
        case .setLatched(let latched):
            guard var ownership else { return }
            ownership.isLatched = latched
            self.ownership = ownership
        case .noop:
            break
        }
    }

    func cancelFromEsc() {
        cancelRecording()
    }

    func changeTranscriptionLanguage(to language: DeepgramLanguage) {
        guard phase == .recording else { return }
        guard pendingTranscriptionLanguage != language else { return }
        guard let format = currentRecordingFormat else { return }

        let apiKey = apiKeyProvider().trimmed
        guard !apiKey.isEmpty else { return }

        cancelReconnect()
        onFinalizeLatestInterim?()
        pendingTranscriptionLanguage = language
        pendingTranscriptionError = nil
        deepgramReconnectAttempt = 0
        onStatus?(.listening)
        deepgram.connect(apiKey: apiKey, format: format, language: language)
        onLog?("Language changed to \(language.displayName) (\(language.deepgramCode)).", .info)
    }

    private func startRecording(ownerShortcutID: UUID, ownerMode: ShortcutMode, isLatched: Bool) {
        guard phase == .idle else { return }

        let apiKey = apiKeyProvider().trimmed
        guard !apiKey.isEmpty else {
            onStatus?(.missingAPIKey)
            onLog?("Missing API key. Open Settings to add one.", .warning)
            onRequestOpenSettings?()
            return
        }

        cancelPendingStop()
        cancelReconnect()
        cancelFinalizeWatchdog()

        pendingTranscriptionError = nil
        pendingEnhancementPrompt = nil
        pendingTranscriptionLanguage = nil
        currentActiveApplication = nil
        hasPlayedTranscriptionFailureSound = false
        deepgramReconnectAttempt = 0
        didFinalizeCurrentSession = false
        pendingStopAfterCaptureStart = false
        onWillStartRecording?()

        let activeApplication = activeApplicationProvider()
        currentActiveApplication = activeApplication
        pendingEnhancementPrompt = resolvedEnhancementPromptProvider(
            ownerShortcutID,
            activeApplication?.bundleIdentifier
        )
        let transcriptionLanguage = resolvedTranscriptionLanguageProvider(activeApplication?.bundleIdentifier)
        pendingTranscriptionLanguage = transcriptionLanguage

        let sessionID = UUID()
        ownership = RecordingOwnership(
            ownerShortcutID: ownerShortcutID,
            ownerMode: ownerMode,
            isLatched: isLatched,
            recordingStartedAt: clock.now(),
            sessionID: sessionID
        )
        phase = .recording

        captureStartTask = Task { @MainActor [weak self] in
            await self?.completeCaptureStart(
                sessionID: sessionID,
                apiKey: apiKey,
                transcriptionLanguage: transcriptionLanguage
            )
        }
    }

    private func completeCaptureStart(
        sessionID: UUID,
        apiKey: String,
        transcriptionLanguage: DeepgramLanguage
    ) async {
        do {
            let format = try await audioCapture.start(sessionID: sessionID)
            try Task.checkCancellation()
            guard ownership?.sessionID == sessionID, phase == .recording else {
                await audioCapture.stop(sessionID: sessionID)
                return
            }

            captureStartTask = nil
            currentRecordingFormat = format
            let rawCapture = rawRecordingCaptureProvider(format)
            rawRecordingCapture = rawCapture
            audioRouter.activate(sessionID: sessionID, rawCapture: rawCapture)

            let resolvedAudioInput = audioInputSelectionProvider()
            onStatus?(.listening)
            onOverlayUpdate?(true, "Listening", overlayAppIcon)
            onLog?("Audio capture started (\(format.sampleRate) Hz, \(format.channels) ch).", .info)
            if resolvedAudioInput.isFallbackToSystemDefault {
                onLog?("Input: \(resolvedAudioInput.displayName). Saved microphone unavailable, using fallback.", .warning)
            } else {
                onLog?("Input: \(resolvedAudioInput.displayName).", .info)
            }
            deepgram.connect(apiKey: apiKey, format: format, language: transcriptionLanguage)

            if muteDuringRecordingProvider() {
                onMuteForRecording?()
            }
            playSound("Tink")
            onLog?("Language: \(transcriptionLanguage.displayName) (\(transcriptionLanguage.deepgramCode)).", .info)
            onLog?("Listening started.", .info)

            if pendingStopAfterCaptureStart {
                pendingStopAfterCaptureStart = false
                stopRecording()
            }
        } catch is CancellationError {
            // Cancellation cleanup owns the session generation and runs elsewhere.
        } catch {
            guard ownership?.sessionID == sessionID, phase == .recording else { return }
            captureStartTask = nil
            finishActiveSession(
                disconnectDeepgram: true,
                clearPendingTranscriptionError: true,
                hideOverlay: true
            )
            onStatus?(.failedToStartAudioCapture(error.localizedDescription))
            onLog?("Failed to start audio capture: \(error.localizedDescription)", .error)
        }
    }

    private func stopRecording() {
        guard phase == .recording else { return }

        cancelPendingStop()
        cancelReconnect()

        guard let sessionID = ownership?.sessionID else { return }
        guard currentRecordingFormat != nil else {
            pendingStopAfterCaptureStart = true
            return
        }

        audioRouter.deactivate(sessionID: sessionID)
        phase = .finalizing
        onAudioLevel?(0)
        onStatus?(.finalizing)
        onRestoreMute?()

        if pendingEnhancementPrompt != nil {
            onOverlayUpdate?(true, "Enhancing", overlayAppIcon)
        } else {
            onOverlayUpdate?(true, "Listening", nil)
        }

        didFinalizeCurrentSession = false
        captureStopTask?.cancel()
        captureStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.audioCapture.stop(sessionID: sessionID)
            guard !Task.isCancelled,
                  self.ownership?.sessionID == sessionID,
                  self.phase == .finalizing else {
                return
            }
            self.captureStopTask = nil
            self.startFinalizeWatchdog()
            self.deepgram.closeStream { [weak self] in
                Task { @MainActor in
                    guard self?.ownership?.sessionID == sessionID else { return }
                    self?.finalizeIfNeeded()
                }
            }
        }
    }

    private func finalizeIfNeeded() {
        guard phase == .finalizing else { return }
        guard !didFinalizeCurrentSession else { return }
        guard let sessionID = ownership?.sessionID else { return }

        didFinalizeCurrentSession = true
        cancelFinalizeWatchdog()
        let capture = rawRecordingCapture
        rawRecordingCapture = nil
        let enhancementPrompt = pendingEnhancementPrompt
        let transcriptionError = pendingTranscriptionError
        let transcriptionLanguage = pendingTranscriptionLanguage

        finalizationTask = Task { @MainActor [weak self] in
            let recordingURL: URL?
            do {
                recordingURL = try await capture?.finish()
            } catch {
                recordingURL = nil
                if let self, self.ownership?.sessionID == sessionID {
                    self.onLog?("Failed to save raw recording: \(error.localizedDescription)", .error)
                }
            }

            guard let self,
                  !Task.isCancelled,
                  self.ownership?.sessionID == sessionID,
                  self.phase == .finalizing else {
                capture?.discard()
                return
            }

            self.finalizationTask = nil
            let finalization = RecordingFinalization(
                enhancementPrompt: enhancementPrompt,
                transcriptionError: transcriptionError,
                rawRecordingFileURL: recordingURL,
                transcriptionLanguage: transcriptionLanguage
            )
            self.finishActiveSession(
                disconnectDeepgram: true,
                clearPendingTranscriptionError: false,
                hideOverlay: false
            )
            self.onFinalizeRequested?(finalization)
        }
    }

    private func startFinalizeWatchdog() {
        cancelFinalizeWatchdog()
        finalizeWatchdogTask = scheduler.schedule(after: finalizeWatchdogTimeout) { [weak self] in
            Task { @MainActor in
                self?.finalizeIfNeeded()
            }
        }
    }

    private func cancelFinalizeWatchdog() {
        finalizeWatchdogTask?.cancel()
        finalizeWatchdogTask = nil
    }

    private func handleTranscriptEvent(_ text: String, isFinal: Bool) {
        let wasRecovering = deepgramReconnectAttempt > 0 || reconnectTask != nil
        if wasRecovering {
            cancelReconnect()
            deepgramReconnectAttempt = 0
            if phase == .recording {
                onStatus?(.listening)
            }
            if pendingTranscriptionError != nil {
                pendingTranscriptionError = nil
                onLog?("Deepgram connection recovered. Transcription resumed.", .info)
            }
        }

        onTranscript?(text, isFinal)
    }

    private func handleTranscriptionError(_ message: String) {
        let isFirstErrorInSession = pendingTranscriptionError == nil
        pendingTranscriptionError = message
        if phase != .idle {
            onStatus?(.transcriptionIssueDetected)
        }
        if isFirstErrorInSession,
           phase != .idle,
           !hasPlayedTranscriptionFailureSound {
            playErrorSound(force: true)
            hasPlayedTranscriptionFailureSound = true
        }
    }

    private func handleDeepgramConnectionDropped(reason: String) {
        guard phase == .recording else { return }
        guard currentRecordingFormat != nil else { return }
        guard reconnectTask == nil else { return }

        onFinalizeLatestInterim?()

        if !DeepgramReconnectPolicy.shouldRetry(currentAttempt: deepgramReconnectAttempt) {
            onStatus?(.connectionLostReleaseToFinalize)
            onLog?(
                "Deepgram reconnect limit reached (\(maxReconnectAttempts) attempts). Last error: \(reason)",
                .error
            )
            return
        }

        deepgramReconnectAttempt += 1
        let attempt = deepgramReconnectAttempt
        let delayText = String(format: "%.1f", reconnectDelay)
        onStatus?(.connectionRecovering)
        onLog?(
            "Deepgram connection dropped. Reconnecting in \(delayText)s (attempt \(attempt)/\(maxReconnectAttempts)).",
            .warning
        )

        reconnectTask = scheduler.schedule(after: reconnectDelay) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reconnectTask = nil
                guard self.phase == .recording else { return }
                guard let format = self.currentRecordingFormat else { return }
                let apiKey = self.apiKeyProvider().trimmed
                guard !apiKey.isEmpty else { return }

                self.onLog?("Attempting Deepgram reconnect (\(attempt)/\(self.maxReconnectAttempts)).", .warning)
                let language = self.pendingTranscriptionLanguage
                    ?? self.resolvedTranscriptionLanguageProvider(self.currentActiveApplication?.bundleIdentifier)
                self.deepgram.connect(apiKey: apiKey, format: format, language: language)
            }
        }
    }

    private func handleAudioInputConfigurationChanged(sessionID: UUID) {
        guard ownership?.sessionID == sessionID else { return }
        onLog?("Audio input changed. Capture engine reset.", .warning)
        guard phase != .idle else { return }

        finishActiveSession(disconnectDeepgram: true, clearPendingTranscriptionError: true, hideOverlay: true)
        onStatus?(.inputChangedReady)
        onLog?("Recording stopped because the input device changed.", .warning)
    }

    private func cancelRecording() {
        guard phase != .idle else { return }

        finishActiveSession(disconnectDeepgram: true, clearPendingTranscriptionError: true, hideOverlay: true)
        playSound("Pop")
        onStatus?(.cancelled)
        onLog?("Recording cancelled.", .info)
    }

    private func scheduleStopRecording() {
        cancelPendingStop()
        stopTask = scheduler.schedule(after: stopDelay) { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }

    private func cancelPendingStop() {
        stopTask?.cancel()
        stopTask = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func finishActiveSession(
        disconnectDeepgram: Bool,
        clearPendingTranscriptionError: Bool,
        hideOverlay: Bool
    ) {
        let sessionID = ownership?.sessionID
        cancelPendingStop()
        cancelReconnect()
        cancelFinalizeWatchdog()
        pendingStopAfterCaptureStart = false
        captureStartTask?.cancel()
        captureStartTask = nil
        captureStopTask?.cancel()
        captureStopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil

        if let sessionID {
            audioRouter.deactivate(sessionID: sessionID)
            let audioCapture = self.audioCapture
            Task {
                await audioCapture.stop(sessionID: sessionID)
            }
        }

        if disconnectDeepgram {
            deepgram.disconnect()
        }

        rawRecordingCapture?.discard()
        rawRecordingCapture = nil

        phase = .idle
        ownership = nil
        currentRecordingFormat = nil
        currentActiveApplication = nil
        pendingEnhancementPrompt = nil
        pendingTranscriptionLanguage = nil
        deepgramReconnectAttempt = 0
        didFinalizeCurrentSession = false
        onRestoreMute?()
        onAudioLevel?(0)

        if hideOverlay {
            onOverlayUpdate?(false, "Listening", nil)
        }

        if clearPendingTranscriptionError {
            pendingTranscriptionError = nil
            hasPlayedTranscriptionFailureSound = false
        }
    }

    private func playSound(_ name: String) {
        guard playSoundEffectsEnabledProvider() else { return }
        soundPort.play(named: name)
    }

    private func playErrorSound(force: Bool = false) {
        guard force || playSoundEffectsEnabledProvider() else { return }
        soundPort.play(named: "Basso")
    }

    private var overlayAppIcon: NSImage? {
        guard pendingEnhancementPrompt?.isForActiveApp == true else { return nil }
        return currentActiveApplication?.icon
    }
}
