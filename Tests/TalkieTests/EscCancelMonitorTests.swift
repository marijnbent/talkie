import Carbon
import XCTest
@testable import TalkieCore

@MainActor
final class EscCancelMonitorTests: XCTestCase {
    func testEscIsConsumedWhenCancellationRuns() {
        let eventMonitor = FakeEventMonitorPort()
        var cancelCallCount = 0
        let monitor = EscCancelMonitor(
            eventMonitor: eventMonitor,
            isEnabled: { true },
            shouldCancel: { true },
            cancelRecording: { cancelCallCount += 1 }
        )

        monitor.start()

        let consumed = eventMonitor.sendKeyDown(CGKeyCode(kVK_Escape))

        XCTAssertTrue(consumed)
        XCTAssertEqual(cancelCallCount, 1)
    }

    func testEscPassesThroughWhenNothingIsRunning() {
        let eventMonitor = FakeEventMonitorPort()
        var cancelCallCount = 0
        let monitor = EscCancelMonitor(
            eventMonitor: eventMonitor,
            isEnabled: { true },
            shouldCancel: { false },
            cancelRecording: { cancelCallCount += 1 }
        )

        monitor.start()

        let consumed = eventMonitor.sendKeyDown(CGKeyCode(kVK_Escape))

        XCTAssertFalse(consumed)
        XCTAssertEqual(cancelCallCount, 0)
    }

    func testNonEscapePassesThrough() {
        let eventMonitor = FakeEventMonitorPort()
        var cancelCallCount = 0
        let monitor = EscCancelMonitor(
            eventMonitor: eventMonitor,
            isEnabled: { true },
            shouldCancel: { true },
            cancelRecording: { cancelCallCount += 1 }
        )

        monitor.start()

        let consumed = eventMonitor.sendKeyDown(CGKeyCode(kVK_ANSI_A))

        XCTAssertFalse(consumed)
        XCTAssertEqual(cancelCallCount, 0)
    }
}
