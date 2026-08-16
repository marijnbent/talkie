import Foundation
import XCTest
@testable import TalkieCore

final class ElevenLabsPrerecordedClientTests: XCTestCase {
    func testMultipartBodyContainsModelLanguageAndFile() throws {
        let boundary = "test-boundary"
        let body = try ElevenLabsPrerecordedClient.makeMultipartBody(
            fileData: Data([0x52, 0x49, 0x46, 0x46]),
            fileName: "recording.wav",
            contentType: "audio/wav",
            language: .flemish,
            boundary: boundary
        )
        let bodyText = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(bodyText.contains("name=\"model_id\""))
        XCTAssertTrue(bodyText.contains("scribe_v2"))
        XCTAssertTrue(bodyText.contains("name=\"language_code\""))
        XCTAssertTrue(bodyText.contains("nl"))
        XCTAssertTrue(bodyText.contains("filename=\"recording.wav\""))
        XCTAssertTrue(bodyText.contains("Content-Type: audio/wav"))
        let terminator = Data("\r\n--test-boundary--\r\n".utf8)
        XCTAssertEqual(Data(body.suffix(terminator.count)), terminator)
    }

    func testAutomaticLanguageOmitsLanguageMultipartField() throws {
        let body = try ElevenLabsPrerecordedClient.makeMultipartBody(
            fileData: Data([0x01]),
            fileName: "recording.wav",
            contentType: "audio/wav",
            language: .automatic,
            boundary: "test-boundary"
        )

        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("language_code"))
    }

    func testResponseDecoderReadsTranscriptAndWords() throws {
        let response = try ElevenLabsPrerecordedClient.decodeResponse(Data("""
        {
            "language_code": "en",
            "language_probability": 0.98,
            "text": "Hello world",
            "words": [{"start": 0.0, "end": 0.5, "text": "Hello", "type": "word"}]
        }
        """.utf8))

        XCTAssertEqual(response.languageCode, "en")
        XCTAssertEqual(response.languageProbability, 0.98)
        XCTAssertEqual(response.text, "Hello world")
        XCTAssertEqual(response.words?.first?.text, "Hello")
        XCTAssertEqual(response.words?.first?.start, 0)
    }
}
