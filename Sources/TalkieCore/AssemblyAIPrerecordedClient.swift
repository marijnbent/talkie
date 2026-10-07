import Foundation

enum AssemblyAIPrerecordedClient {
    static func transcribe(
        fileURL: URL,
        apiKey: String,
        language: DeepgramLanguage,
        automaticLanguageCandidates: [DeepgramLanguage],
        session: URLSession = .shared,
        pollInterval: Duration = .seconds(1)
    ) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        let upload = try await request(path: "upload", method: "POST", apiKey: apiKey, body: audio, contentType: "application/octet-stream", session: session)
        guard let uploadURL = upload.upload_url else { throw AssemblyAIRequestError("Invalid upload response.") }
        let body = try makeRequestBody(audioURL: uploadURL, language: language, candidates: automaticLanguageCandidates)
        var transcript = try await request(path: "transcript", method: "POST", apiKey: apiKey, body: body, session: session)
        guard let id = transcript.id else { throw AssemblyAIRequestError("Invalid transcript response.") }
        let deadline = ContinuousClock.now + .seconds(300)
        while true {
            try Task.checkCancellation()
            switch transcript.status {
            case "completed":
                guard let text = transcript.text?.trimmed, !text.isEmpty else {
                    throw AssemblyAIRequestError("No transcript returned.")
                }
                return text
            case "error":
                throw AssemblyAIRequestError(transcript.error ?? "Transcription failed.")
            case "queued", "processing":
                guard ContinuousClock.now < deadline else { throw AssemblyAIRequestError("Transcription timed out.") }
                try await Task.sleep(for: pollInterval)
                transcript = try await request(path: "transcript/\(id)", method: "GET", apiKey: apiKey, session: session)
            default:
                throw AssemblyAIRequestError("Invalid transcript status.")
            }
        }
    }

    static func makeRequestBody(audioURL: String, language: DeepgramLanguage, candidates: [DeepgramLanguage]) throws -> Data {
        var body: [String: Any] = [
            "audio_url": audioURL,
            "speech_models": ["universal-3-5-pro", "universal-2"]
        ]
        let codes = AssemblyAIClient.languageCodes(for: language, candidates: candidates)
        if TranscriptionProvider.assemblyAI.normalizedLanguage(language) == .automatic {
            body["language_detection"] = true
            body["language_detection_options"] = ["expected_languages": codes]
        } else {
            body["language_code"] = codes.first
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func request(
        path: String,
        method: String,
        apiKey: String,
        body: Data? = nil,
        contentType: String = "application/json",
        session: URLSession
    ) async throws -> AssemblyAIResponse {
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/")!.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AssemblyAIRequestError("Invalid HTTP response.") }
        guard (200...299).contains(response.statusCode) else {
            throw AssemblyAIRequestError("HTTP \(response.statusCode).")
        }
        return try JSONDecoder().decode(AssemblyAIResponse.self, from: data)
    }
}

private struct AssemblyAIResponse: Decodable {
    let upload_url: String?
    let id: String?
    let status: String?
    let text: String?
    let error: String?
}

private struct AssemblyAIRequestError: LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { "AssemblyAI: \(reason)" }
}
