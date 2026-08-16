import XCTest
@testable import TalkieCore

final class TranscriptionReconnectPolicyTests: XCTestCase {
    func testAllowsExactlyOneReconnectAttempt() {
        XCTAssertTrue(TranscriptionReconnectPolicy.shouldRetry(currentAttempt: 0))
        XCTAssertFalse(TranscriptionReconnectPolicy.shouldRetry(currentAttempt: 1))
        XCTAssertFalse(TranscriptionReconnectPolicy.shouldRetry(currentAttempt: 2))
    }
}
