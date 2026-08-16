import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import Foundation

final class DispatchWorkItemTask: CancellableTask {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

final class DispatchSchedulerAdapter: SchedulerPort {
    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> CancellableTask {
        let workItem = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchWorkItemTask(workItem: workItem)
    }
}

struct SystemClockAdapter: ClockPort {
    func now() -> TimeInterval {
        CACurrentMediaTime()
    }
}

final class AudioCaptureControllerAdapter: AudioCapturePort, @unchecked Sendable {
    private let controller: AudioCaptureController

    init(controller: AudioCaptureController = AudioCaptureController()) {
        self.controller = controller
    }

    var onAudioChunk: (@Sendable (UUID, Linear16AudioChunk) -> Void)? {
        get { controller.onAudioChunk }
        set { controller.onAudioChunk = newValue }
    }

    var onConfigurationChanged: (@Sendable (UUID) -> Void)? {
        get { controller.onConfigurationChanged }
        set { controller.onConfigurationChanged = newValue }
    }

    func start(sessionID: UUID) async throws -> AudioStreamFormat {
        try await controller.start(sessionID: sessionID)
    }

    func stop(sessionID: UUID) async {
        await controller.stop(sessionID: sessionID)
    }
}

final class DeepgramClientAdapter: TranscriptionStreamPort, @unchecked Sendable {
    var onTranscriptEvent: ((String, Bool) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onTranscriptionError: ((String) -> Void)?
    var onConnectionDropped: ((String) -> Void)?

    private lazy var client: DeepgramClient = {
        DeepgramClient(
            onTranscriptEvent: { [weak self] text, isFinal in
                self?.onTranscriptEvent?(text, isFinal)
            },
            onLog: { [weak self] message, level in
                self?.onLog?(message, level)
            },
            onTranscriptionError: { [weak self] message in
                self?.onTranscriptionError?(message)
            },
            onConnectionDropped: { [weak self] reason in
                self?.onConnectionDropped?(reason)
            }
        )
    }()

    func connect(
        settings: TranscriptionProviderSettings,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    ) {
        client.connect(apiKey: settings.apiKey, format: format, language: language)
    }

    func sendAudio(data: Data) {
        client.sendAudio(data: data)
    }

    func closeStream(onClosed: @escaping () -> Void) {
        client.closeStream(onClosed: onClosed)
    }

    func disconnect() {
        client.disconnect()
    }
}

final class ElevenLabsClientAdapter: TranscriptionStreamPort, @unchecked Sendable {
    var onTranscriptEvent: ((String, Bool) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onTranscriptionError: ((String) -> Void)?
    var onConnectionDropped: ((String) -> Void)?

    private lazy var client: ElevenLabsClient = {
        ElevenLabsClient(
            onTranscriptEvent: { [weak self] text, isFinal in
                self?.onTranscriptEvent?(text, isFinal)
            },
            onLog: { [weak self] message, level in
                self?.onLog?(message, level)
            },
            onTranscriptionError: { [weak self] message in
                self?.onTranscriptionError?(message)
            },
            onConnectionDropped: { [weak self] reason in
                self?.onConnectionDropped?(reason)
            }
        )
    }()

    func connect(
        settings: TranscriptionProviderSettings,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    ) {
        client.connect(
            apiKey: settings.apiKey,
            format: format,
            language: language,
            automaticLanguageCandidates: settings.automaticLanguageCandidates
        )
    }

    func sendAudio(data: Data) {
        client.sendAudio(data: data)
    }

    func closeStream(onClosed: @escaping () -> Void) {
        client.closeStream(onClosed: onClosed)
    }

    func disconnect() {
        client.disconnect()
    }
}

/// Keeps one provider active for the full recording session and forwards its events.
final class TranscriptionStreamRouter: TranscriptionStreamPort, @unchecked Sendable {
    var onTranscriptEvent: ((String, Bool) -> Void)?
    var onLog: ((String, LogLevel) -> Void)?
    var onTranscriptionError: ((String) -> Void)?
    var onConnectionDropped: ((String) -> Void)?

    private let deepgram: TranscriptionStreamPort
    private let elevenLabs: TranscriptionStreamPort
    private let lock = NSLock()
    private var activeProvider: TranscriptionProvider?
    private var activeStream: TranscriptionStreamPort?

    init(
        deepgram: TranscriptionStreamPort = DeepgramClientAdapter(),
        elevenLabs: TranscriptionStreamPort = ElevenLabsClientAdapter()
    ) {
        self.deepgram = deepgram
        self.elevenLabs = elevenLabs
        wire(deepgram, provider: .deepgram)
        wire(elevenLabs, provider: .elevenLabs)
    }

    func connect(
        settings: TranscriptionProviderSettings,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    ) {
        let stream = stream(for: settings.provider)
        let previousStream = lock.withLock { () -> TranscriptionStreamPort? in
            let previous = activeProvider == settings.provider ? nil : activeStream
            activeProvider = settings.provider
            activeStream = stream
            return previous
        }
        previousStream?.disconnect()
        stream.connect(settings: settings, format: format, language: language)
    }

    func sendAudio(data: Data) {
        lock.withLock { activeStream }?.sendAudio(data: data)
    }

    func closeStream(onClosed: @escaping () -> Void) {
        guard let stream = lock.withLock({ activeStream }) else {
            onClosed()
            return
        }
        stream.closeStream(onClosed: onClosed)
    }

    func disconnect() {
        let stream = lock.withLock { () -> TranscriptionStreamPort? in
            defer {
                activeProvider = nil
                activeStream = nil
            }
            return activeStream
        }
        stream?.disconnect()
    }

    private func stream(for provider: TranscriptionProvider) -> TranscriptionStreamPort {
        switch provider {
        case .deepgram:
            return deepgram
        case .elevenLabs:
            return elevenLabs
        }
    }

    private func wire(_ stream: TranscriptionStreamPort, provider: TranscriptionProvider) {
        stream.onTranscriptEvent = { [weak self] text, isFinal in
            guard self?.isActive(provider) == true else { return }
            self?.onTranscriptEvent?(text, isFinal)
        }
        stream.onLog = { [weak self] message, level in
            guard self?.isActive(provider) == true else { return }
            self?.onLog?(message, level)
        }
        stream.onTranscriptionError = { [weak self] message in
            guard self?.isActive(provider) == true else { return }
            self?.onTranscriptionError?(message)
        }
        stream.onConnectionDropped = { [weak self] reason in
            guard self?.isActive(provider) == true else { return }
            self?.onConnectionDropped?(reason)
        }
    }

    private func isActive(_ provider: TranscriptionProvider) -> Bool {
        lock.withLock { activeProvider == provider }
    }
}

struct NSSoundAdapter: SoundPort {
    func play(named: String) {
        NSSound(named: named)?.play()
    }
}

final class NSPasteboardAdapter: PasteboardPort {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> PasteboardSnapshotPayload {
        let items: [[String: Data]] = pasteboard.pasteboardItems?.map { item in
            var dataByType: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type.rawValue] = data
                }
            }
            return dataByType
        } ?? []
        return PasteboardSnapshotPayload(items: items)
    }

    func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func restore(_ snapshot: PasteboardSnapshotPayload) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (typeRaw, data) in dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    func sendPasteCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }
}

struct NSEventMonitorAdapter: EventMonitorPort {
    private final class KeyDownInterceptorToken {
        let eventTap: CFMachPort
        let runLoopSource: CFRunLoopSource
        let userInfo: UnsafeMutableRawPointer

        init(eventTap: CFMachPort, runLoopSource: CFRunLoopSource, userInfo: UnsafeMutableRawPointer) {
            self.eventTap = eventTap
            self.runLoopSource = runLoopSource
            self.userInfo = userInfo
        }
    }

    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func addKeyDownInterceptor(
        handler: @escaping (CGKeyCode) -> Bool
    ) -> Any? {
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let interceptor = Unmanaged<KeyDownInterceptorBox>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return interceptor.handler(keyCode) ? nil : Unmanaged.passUnretained(event)
        }

        let interceptor = KeyDownInterceptorBox(handler: handler)
        let userInfo = Unmanaged.passRetained(interceptor).toOpaque()
        let mask = (1 << CGEventType.keyDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) else {
            Unmanaged<KeyDownInterceptorBox>.fromOpaque(userInfo).release()
            return nil
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            Unmanaged<KeyDownInterceptorBox>.fromOpaque(userInfo).release()
            CFMachPortInvalidate(eventTap)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return KeyDownInterceptorToken(eventTap: eventTap, runLoopSource: runLoopSource, userInfo: userInfo)
    }

    func removeMonitor(_ monitor: Any) {
        if let token = monitor as? KeyDownInterceptorToken {
            Unmanaged<KeyDownInterceptorBox>.fromOpaque(token.userInfo).release()
            CFMachPortInvalidate(token.eventTap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), token.runLoopSource, .commonModes)
            return
        }

        NSEvent.removeMonitor(monitor)
    }
}

private final class KeyDownInterceptorBox {
    let handler: (CGKeyCode) -> Bool

    init(handler: @escaping (CGKeyCode) -> Bool) {
        self.handler = handler
    }
}
