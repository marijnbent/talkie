import Foundation
import XCTest
@testable import TalkieCore

final class AssemblyAIPrerecordedClientTests: XCTestCase {
    func testUploadsThenPollsUntilCompleted() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AssemblyAIHTTPStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = try await AssemblyAIPrerecordedClient.transcribe(
            fileURL: file,
            apiKey: "test-key",
            language: .automatic,
            automaticLanguageCandidates: [.dutch, .english],
            session: session,
            pollInterval: .milliseconds(1)
        )
        XCTAssertEqual(result, "Hallo world.")
    }
}

private final class AssemblyAIHTTPStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
        let body: String
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/v2/upload"):
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
            body = #"{"upload_url":"https://cdn.assemblyai.com/upload/test"}"#
        case ("POST", "/v2/transcript"):
            body = #"{"id":"test-id","status":"queued"}"#
        case ("GET", "/v2/transcript/test-id"):
            body = #"{"id":"test-id","status":"completed","text":"Hallo world."}"#
        default:
            XCTFail("Unexpected request")
            body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
