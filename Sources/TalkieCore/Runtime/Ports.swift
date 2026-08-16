import AppKit
import ApplicationServices
import AVFoundation
import Foundation

protocol CancellableTask {
    func cancel()
}

protocol SchedulerPort {
    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> CancellableTask
}

protocol ClockPort {
    func now() -> TimeInterval
}

protocol AudioCapturePort: AnyObject, Sendable {
    var onAudioChunk: (@Sendable (UUID, Linear16AudioChunk) -> Void)? { get set }
    var onConfigurationChanged: (@Sendable (UUID) -> Void)? { get set }
    func start(sessionID: UUID) async throws -> AudioStreamFormat
    func stop(sessionID: UUID) async
}

protocol TranscriptionStreamPort: AnyObject {
    var onTranscriptEvent: ((String, Bool) -> Void)? { get set }
    var onLog: ((String, LogLevel) -> Void)? { get set }
    var onTranscriptionError: ((String) -> Void)? { get set }
    var onConnectionDropped: ((String) -> Void)? { get set }

    func connect(
        settings: TranscriptionProviderSettings,
        format: AudioStreamFormat,
        language: DeepgramLanguage
    )
    func sendAudio(data: Data)
    func closeStream(onClosed: @escaping () -> Void)
    func disconnect()
}

struct PasteboardSnapshotPayload: Equatable {
    let items: [[String: Data]]
}

protocol PasteboardPort {
    func snapshot() -> PasteboardSnapshotPayload
    func writeString(_ value: String)
    func restore(_ snapshot: PasteboardSnapshotPayload)
    func sendPasteCommand() -> Bool
}

struct PreparedPasteVerification {
    let expectedText: String
    let expectedValue: String
    let expectedSelectedRange: NSRange
    let focusedElement: AXUIElement
    let initialValue: String
    let initialSelectedRange: NSRange
}

enum PasteVerificationCheck: Equatable {
    case confirmed
    case pending
    case unconfirmed(PasteVerificationFailureReason)
}

enum PasteVerificationFailureReason: Equatable {
    case accessibilityUnavailable
    case unsupportedFocusedElement
    case focusChanged
    case valueUnavailable
    case selectionUnavailable
    case mismatch
    case timedOut
}

protocol PasteVerificationPort {
    func prepare(expectedText: String) -> PreparedPasteVerification?
    func check(_ verification: PreparedPasteVerification) -> PasteVerificationCheck
}

protocol SoundPort {
    func play(named: String)
}

protocol EventMonitorPort {
    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any?

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?

    func addKeyDownInterceptor(
        handler: @escaping (CGKeyCode) -> Bool
    ) -> Any?

    func removeMonitor(_ monitor: Any)
}
