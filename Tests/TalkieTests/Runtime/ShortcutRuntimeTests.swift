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

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        XCTAssertEqual(cycleCount, 0)

        phase = .recording
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Command),
            modifiers: superCapsLockModifiers
        )
        XCTAssertEqual(cycleCount, 1)

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        XCTAssertEqual(cycleCount, 2)

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        phase = .finalizing
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        XCTAssertEqual(cycleCount, 2)
    }

    func testCompanionKeyDiscardsRecordingWhileShortcutIsHeldWithoutConsumingKey() {
        let harness = makeCompanionKeyHarness()

        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: harness.shortcut.key.modifierFlag
        )
        harness.clock.currentTime = 1
        let wasConsumed = harness.eventMonitor.sendKeyDown(CGKeyCode(kVK_ANSI_Slash))

        XCTAssertFalse(wasConsumed)
        XCTAssertEqual(harness.receivedActions.value.last, .discard)
    }

    func testFnKeyDownDoesNotDiscardItsOwnQuickPress() {
        let harness = makeCompanionKeyHarness(key: .fn)

        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: harness.shortcut.key.modifierFlag
        )
        _ = harness.eventMonitor.sendKeyDown(CGKeyCode(harness.shortcut.key.keyCode))
        harness.clock.currentTime = 0.1
        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: []
        )

        XCTAssertFalse(harness.receivedActions.value.contains(.discard))
        XCTAssertTrue(harness.receivedActions.value.contains(.setLatched(true)))
    }

    private func makeCompanionKeyHarness(key: ShortcutKey = .rightOption) -> (
        runtime: ShortcutRuntime,
        eventMonitor: FakeEventMonitorPort,
        clock: ManualClock,
        shortcut: ShortcutConfig,
        receivedActions: ShortcutActionRecorder
    ) {
        let eventMonitor = FakeEventMonitorPort()
        let clock = ManualClock()
        let shortcut = ShortcutConfig(id: UUID(), key: key, mode: .both)
        let runtime = ShortcutRuntime(
            eventMonitor: eventMonitor,
            clock: clock,
            clickHoldThreshold: 0.2
        )
        var phase = RecordingPhase.idle
        var ownership: RecordingOwnership?
        let receivedActions = ShortcutActionRecorder()
        runtime.phaseProvider = { phase }
        runtime.ownershipProvider = { ownership }
        runtime.onActions = { actions in
            receivedActions.value.append(contentsOf: actions)
            if case .start = actions.first {
                phase = .recording
                ownership = RecordingOwnership(
                    ownerShortcutID: shortcut.id,
                    ownerMode: shortcut.mode,
                    isLatched: false,
                    recordingStartedAt: clock.now(),
                    sessionID: UUID()
                )
            }
        }
        runtime.configure(shortcuts: [shortcut])
        runtime.start()
        return (runtime, eventMonitor, clock, shortcut, receivedActions)
    }
}

private final class ShortcutActionRecorder {
    var value: [ShortcutAction] = []
}
