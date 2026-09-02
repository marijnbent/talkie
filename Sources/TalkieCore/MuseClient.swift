import Foundation

final class MuseClient: NSObject, @unchecked Sendable {
    private final class CompletionBox: @unchecked Sendable {
        let callback: () -> Void

        init(_ callback: @escaping () -> Void) {
            self.callback = callback
        }
    }

    private static let endpoint = URL(string: "wss://api.meta.ai/v1/asr/realtime")!
    private static let model = "muse-voice-transcribe-1.0"
    private static let closeTimeoutSeconds: TimeInterval = 3

    private let session: URLSession
    private let queue = DispatchQueue(label: "Talkie.MuseClient")
    private var task: URLSessionWebSocketTask?
    private var converter: MusePCMConverter?
    private var isConnected = false
    private var isClosing = false
    private var handshakeAccepted = false
    private var pendingAudio: [Data] = []
    private var onClose: (() -> Void)?
    private var closeTimer: DispatchSourceTimer?

    private let onTranscriptEvent: ((String, Bool) -> Void)?
    private let onLog: ((String, LogLevel) -> Void)?
    private let onTranscriptionError: ((String) -> Void)?
    private let onConnectionDropped: ((String) -> Void)?

    init(
        onTranscriptEvent: ((String, Bool) -> Void)? = nil,
        onLog: ((String, LogLevel) -> Void)? = nil,
        onTranscriptionError: ((String) -> Void)? = nil,
        onConnectionDropped: ((String) -> Void)? = nil
    ) {
        session = URLSession(configuration: .default)
        self.onTranscriptEvent = onTranscriptEvent
        self.onLog = onLog
        self.onTranscriptionError = onTranscriptionError
        self.onConnectionDropped = onConnectionDropped
        super.init()
    }

    func connect(
        apiKey: String,
        format: AudioStreamFormat,
        language: DeepgramLanguage,
        automaticLanguageCandidates: [DeepgramLanguage]
    ) {
        disconnect(logDisconnection: false)

        guard format.sampleRate > 0 else {
            reportTranscriptionError("Muse requires audio with a valid sample rate.")
            return
        }
        guard format.channels > 0 else {
            reportTranscriptionError("Muse requires at least one audio channel.")
            return
        }

        let converter = MusePCMConverter(format: format)
        let task = session.webSocketTask(with: Self.endpoint)
        queue.sync {
            self.task = task
            self.converter = converter
            self.isConnected = true
            self.isClosing = false
            self.handshakeAccepted = false
            self.pendingAudio = []
            self.closeTimer?.cancel()
            self.closeTimer = nil
        }
        task.resume()
        onLog?("WebSocket connecting to Muse.", .info)
        receiveLoop(for: task)

        do {
            let handshake = try Self.makeHandshake(
                apiKey: apiKey,
                audioEncoding: converter.audioEncoding,
                language: TranscriptionProvider.muse.normalizedLanguage(language),
                automaticLanguageCandidates: automaticLanguageCandidates
            )
            task.send(.string(handshake)) { [weak self] error in
                guard let self, let error, !Self.isCancellationError(error) else { return }
                self.queue.async { [weak self] in
                    self?.handleUnexpectedConnectionDropOnQueue(
                        "Muse WebSocket handshake error: \(error.localizedDescription)",
                        task: task
                    )
                }
            }
        } catch {
            reportTranscriptionError("Failed to encode Muse handshake.")
            disconnect(logDisconnection: false)
        }
    }

    func sendAudio(data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self,
                  self.task != nil,
                  self.isConnected,
                  !self.isClosing,
                  let converter = self.converter else { return }

            let converted = converter.convert(data)
            guard !converted.isEmpty else { return }
            if self.handshakeAccepted {
                self.sendBinaryOnQueue(converted)
            } else {
                self.pendingAudio.append(converted)
            }
        }
    }

    func closeStream(onClosed: @escaping () -> Void) {
        let completion = CompletionBox(onClosed)
        queue.async { [weak self] in
            guard let self else {
                completion.callback()
                return
            }

            guard self.task != nil else {
                self.onClose = nil
                self.isClosing = false
                self.isConnected = false
                completion.callback()
                return
            }

            self.isClosing = true
            self.isConnected = false
            self.onClose = completion.callback
            if let tail = self.converter?.finish(), !tail.isEmpty {
                self.pendingAudio.append(tail)
            }
            if self.handshakeAccepted {
                self.endStreamOnQueue()
            }
            self.scheduleCloseTimeoutOnQueue()
        }
    }

    func disconnect() {
        disconnect(logDisconnection: true)
    }

    private func disconnect(logDisconnection: Bool) {
        let hadConnection = queue.sync { () -> Bool in
            let hadConnection = isConnected || isClosing || task != nil
            isConnected = false
            isClosing = false
            handshakeAccepted = false
            pendingAudio = []
            converter = nil
            closeTimer?.cancel()
            closeTimer = nil
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            onClose = nil
            return hadConnection
        }
        if hadConnection && logDisconnection {
            onLog?("Muse WebSocket disconnected.", .info)
        }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.queue.sync(execute: { self.task === task }) else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncoming(text: text, for: task)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncoming(text: text, for: task)
                    } else {
                        self.reportTranscriptionError("Muse returned invalid UTF-8 data.")
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                self.queue.async { [weak self] in
                    guard let self, self.task === task else { return }
                    if self.isClosing {
                        self.finishCloseOnQueue()
                    } else if !Self.isCancellationError(error) {
                        self.handleUnexpectedConnectionDropOnQueue(
                            "Muse WebSocket receive error: \(error.localizedDescription)",
                            task: task
                        )
                    }
                }
                return
            }

            let shouldContinue = self.queue.sync {
                self.task === task && (self.isConnected || self.isClosing)
            }
            if shouldContinue {
                self.receiveLoop(for: task)
            }
        }
    }

    private func handleIncoming(text: String, for task: URLSessionWebSocketTask) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(MuseServerMessage.self, from: data) else {
            onLog?("Failed to decode Muse message. Preview: \(Self.preview(text))", .warning)
            return
        }

        guard let type = message.type else {
            guard message.sessionId != nil else {
                onLog?("Muse returned an invalid handshake acknowledgement.", .warning)
                return
            }
            queue.async { [weak self] in
                guard let self, self.task === task else { return }
                self.handshakeAccepted = true
                self.onLog?("Muse WebSocket connected.", .info)
                if self.isClosing {
                    self.endStreamOnQueue()
                } else {
                    self.sendPendingAudioOnQueue()
                }
            }
            return
        }

        switch type {
        case "transcript":
            if let transcript = message.transcript, !transcript.isEmpty {
                onTranscriptEvent?(transcript, message.final ?? false)
            }
        case "error":
            reportTranscriptionError("Muse error: \(message.message ?? "Unknown provider error.")")
        default:
            break
        }
    }

    private func sendPendingAudioOnQueue() {
        let audio = pendingAudio
        pendingAudio = []
        for data in audio {
            sendBinaryOnQueue(data)
        }
    }

    private func sendBinaryOnQueue(_ data: Data) {
        guard let task else { return }
        task.send(.data(data)) { [weak self] error in
            guard let self, let error, !Self.isCancellationError(error) else { return }
            self.queue.async { [weak self] in
                self?.handleUnexpectedConnectionDropOnQueue(
                    "Muse WebSocket send error: \(error.localizedDescription)",
                    task: task
                )
            }
        }
    }

    private func endStreamOnQueue() {
        guard let task else {
            finishCloseOnQueue()
            return
        }
        sendPendingAudioOnQueue()
        task.send(.string("{\"type\":\"endStream\"}")) { [weak self] error in
            guard let self, let error, !Self.isCancellationError(error) else { return }
            self.onLog?("Failed to end Muse stream: \(error.localizedDescription)", .warning)
        }
        onLog?("Sent endStream to Muse.", .info)
    }

    private func handleUnexpectedConnectionDropOnQueue(_ message: String, task: URLSessionWebSocketTask) {
        guard self.task === task, !isClosing else { return }
        isConnected = false
        self.task = nil
        pendingAudio = []
        converter = nil
        onLog?(message, .error)
        onConnectionDropped?(message)
    }

    private func scheduleCloseTimeoutOnQueue() {
        guard isClosing else { return }
        closeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.closeTimeoutSeconds)
        timer.setEventHandler { [weak self] in self?.finishCloseOnQueue() }
        closeTimer = timer
        timer.activate()
    }

    private func finishCloseOnQueue() {
        guard isClosing else { return }
        isClosing = false
        let callback = onClose
        onClose = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        converter = nil
        pendingAudio = []
        handshakeAccepted = false
        closeTimer?.cancel()
        closeTimer = nil
        onLog?("Muse WebSocket closed.", .info)
        callback?()
    }

    private func reportTranscriptionError(_ message: String) {
        onLog?(message, .error)
        onTranscriptionError?(message)
    }

    static func makeHandshake(
        apiKey: String,
        audioEncoding: String,
        language: DeepgramLanguage,
        automaticLanguageCandidates: [DeepgramLanguage] = TranscriptionProvider.muse.defaultAutomaticLanguageCandidates
    ) throws -> String {
        let handshake = MuseHandshake(
            authorization: MuseAuthorization(accessToken: "Bearer \(apiKey)"),
            audioEncoding: audioEncoding,
            model: model,
            mode: "PUSH_TO_TALK",
            partialMode: "CUMULATIVE",
            emitAudioProgress: false,
            languageBias: languageBias(
                for: language,
                automaticLanguageCandidates: automaticLanguageCandidates
            )
        )
        return String(decoding: try JSONEncoder().encode(handshake), as: UTF8.self)
    }

    private static func languageBias(
        for language: DeepgramLanguage,
        automaticLanguageCandidates: [DeepgramLanguage]
    ) -> [String] {
        if language == .automatic {
            return TranscriptionProvider.muse
                .normalizedAutomaticLanguageCandidates(automaticLanguageCandidates)
                .compactMap(\.museLanguageName)
        }
        return language.museLanguageName.map { [$0] } ?? []
    }

    private static func preview(_ text: String, maxLength: Int = 400) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmed
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "…"
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

final class MusePCMConverter {
    let audioEncoding: String
    let sampleRate: Int

    private let sourceSampleRate: Double
    private let channels: Int
    private var resampleBuffer: [Int16] = []
    private var nextOutputPosition: Double = 0

    init(format: AudioStreamFormat) {
        sourceSampleRate = Double(format.sampleRate)
        sampleRate = format.sampleRate == 16_000 ? 16_000 : 24_000
        channels = format.channels
        audioEncoding = sampleRate == 16_000 ? "PCM_16KHZ" : "PCM_24KHZ"
    }

    func convert(_ data: Data) -> Data {
        let monoSamples = Self.downmix(data, channels: channels)
        guard !monoSamples.isEmpty else { return Data() }
        guard Int(sourceSampleRate) != sampleRate else {
            return Self.data(from: monoSamples)
        }

        resampleBuffer.append(contentsOf: monoSamples)
        let step = sourceSampleRate / Double(sampleRate)
        var output: [Int16] = []
        output.reserveCapacity(Int(Double(monoSamples.count) / step) + 1)

        while nextOutputPosition + 1 < Double(resampleBuffer.count) {
            let lowerIndex = Int(nextOutputPosition)
            let fraction = nextOutputPosition - Double(lowerIndex)
            let lower = Double(resampleBuffer[lowerIndex])
            let upper = Double(resampleBuffer[lowerIndex + 1])
            output.append(Int16(clamping: Int((lower + ((upper - lower) * fraction)).rounded())))
            nextOutputPosition += step
        }

        let consumed = min(Int(nextOutputPosition), max(0, resampleBuffer.count - 1))
        if consumed > 0 {
            resampleBuffer.removeFirst(consumed)
            nextOutputPosition -= Double(consumed)
        }
        return Self.data(from: output)
    }

    func finish() -> Data {
        guard Int(sourceSampleRate) != sampleRate,
              !resampleBuffer.isEmpty else { return Data() }
        guard nextOutputPosition <= Double(resampleBuffer.count - 1) else {
            resampleBuffer = []
            nextOutputPosition = 0
            return Data()
        }
        let sample = resampleBuffer[Int(nextOutputPosition)]
        resampleBuffer = []
        nextOutputPosition = 0
        return Self.data(from: [sample])
    }

    private static func downmix(_ data: Data, channels: Int) -> [Int16] {
        let bytesPerFrame = channels * MemoryLayout<Int16>.size
        guard channels > 0, bytesPerFrame > 0 else { return [] }
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return (0..<frameCount).map { frame in
                var sum = 0
                for channel in 0..<channels {
                    sum += Int(samples[(frame * channels) + channel])
                }
                return Int16(clamping: sum / channels)
            }
        }
    }

    private static func data(from samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private struct MuseHandshake: Encodable {
    let authorization: MuseAuthorization
    let audioEncoding: String
    let model: String
    let mode: String
    let partialMode: String
    let emitAudioProgress: Bool
    let languageBias: [String]?
}

private struct MuseAuthorization: Encodable {
    let accessToken: String
}

struct MuseServerMessage: Decodable, Equatable {
    let type: String?
    let sessionId: String?
    let message: String?
    let transcript: String?
    let final: Bool?
}
