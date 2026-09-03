import Foundation

enum CelerisClient {
    static let model = "celeris-1"

    private static let timeoutInterval: TimeInterval = 30

    static func enhance(
        transcript: String,
        prompt: String,
        apiKey: String,
        model: String = model
    ) async throws -> String {
        let request = try makeRequest(
            transcript: transcript,
            prompt: prompt,
            apiKey: apiKey,
            model: model
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CelerisError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw CelerisError.httpError(statusCode: httpResponse.statusCode, body: Self.preview(body))
            }

            let decoded = try JSONDecoder().decode(CelerisResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw CelerisError.noContent
            }
            return content
        } catch let error as URLError {
            throw CelerisError.requestFailed(reason: error.localizedDescription)
        }
    }

    static func makeRequest(
        transcript: String,
        prompt: String,
        apiKey: String,
        model: String
    ) throws -> URLRequest {
        let model = model.trimmed
        guard !model.isEmpty,
              let endpoint = URL(string: "https://inference.celeris.ai/\(model)/v1/chat/completions") else {
            throw CelerisError.invalidModel
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let content = "\(prompt)\n\n<transcription>\(transcript)</transcription>"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": content]
            ],
            "max_tokens": 2_048,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func preview(_ text: String, maxLength: Int = 400) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmed
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "…"
    }
}

enum CelerisError: LocalizedError {
    case invalidModel
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noContent
    case requestFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "Invalid Celeris model."
        case .invalidResponse:
            return "Invalid response from Celeris."
        case .httpError(let statusCode, let body):
            return "Celeris HTTP \(statusCode): \(body)"
        case .noContent:
            return "Celeris returned no content."
        case .requestFailed(let reason):
            return "Celeris request failed: \(reason)"
        }
    }
}

private struct CelerisResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
