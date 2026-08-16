import Foundation

enum TranscriptionReconnectPolicy {
    static let maxAttempts = 1

    static func shouldRetry(currentAttempt: Int) -> Bool {
        currentAttempt < maxAttempts
    }
}
