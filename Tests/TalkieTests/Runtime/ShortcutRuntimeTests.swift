import Carbon
import XCTest
@testable import TalkieCore

@MainActor
final class ShortcutRuntimeTests: XCTestCase {
    private let superCapsLockModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    func testSuperCapsLockCyclesOncePerPressOnlyWhileRecording() {
        let eventMonitor = FakeEventMonitorPort()
        let runtime = ShortcutRuntime(
            eventMonitor: eventMonitor,
            clock: ManualClock(),
            clickHoldThreshold: 0.2
        )
        var phase = RecordingPhase.idle
        var cycleCount = 0
        runtime.phaseProvider = { phase }
        runtime.onCycleLanguage = { cycleCount += 1 }
        runtime.start()

        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers,
            timestamp: 1
        )
        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: [],
            timestamp: 2
        )
        XCTAssertEqual(cycleCount, 0)

        phase = .recording
        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers,
            timestamp: 3
        )
        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Command),
            modifiers: superCapsLockModifiers,
            timestamp: 4
        )
        XCTAssertEqual(cycleCount, 1)

        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: [],
            timestamp: 5
        )
        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers,
            timestamp: 6
        )
        XCTAssertEqual(cycleCount, 2)

        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: [],
            timestamp: 7
        )
        phase = .finalizing
        eventMonitor.sendLocalFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers,
            timestamp: 8
        )
        XCTAssertEqual(cycleCount, 2)
    }
}
