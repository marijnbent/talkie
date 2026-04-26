import AppKit
import Carbon

@MainActor
final class EscCancelMonitor {
    private let eventMonitor: EventMonitorPort
    private let isEnabled: () -> Bool
    private let shouldCancel: () -> Bool
    private let cancelRecording: () -> Void

    private var keyDownInterceptor: Any?

    init(
        eventMonitor: EventMonitorPort,
        isEnabled: @escaping () -> Bool,
        shouldCancel: @escaping () -> Bool,
        cancelRecording: @escaping () -> Void
    ) {
        self.eventMonitor = eventMonitor
        self.isEnabled = isEnabled
        self.shouldCancel = shouldCancel
        self.cancelRecording = cancelRecording
    }

    func start() {
        stop()

        let escKeyCode = CGKeyCode(kVK_Escape)
        keyDownInterceptor = eventMonitor.addKeyDownInterceptor { [weak self] keyCode in
            guard keyCode == escKeyCode else { return false }
            guard let self else { return false }
            return self.handleEsc()
        }
    }

    func stop() {
        if let keyDownInterceptor {
            eventMonitor.removeMonitor(keyDownInterceptor)
            self.keyDownInterceptor = nil
        }
    }

    private func handleEsc() -> Bool {
        guard isEnabled(), shouldCancel() else { return false }
        cancelRecording()
        return true
    }
}
