import Foundation

final class OfflineLLMClient {
    enum OfflineError: Error {
        case invalidResponse
    }

    private struct Message: Encodable, Decodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ResponseBody: Decodable {
        let message: Message?
    }

    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private let model: String
    private let session: URLSession

    init(
        model: String = "qwen2.5-coder:7b-instruct-q5_1",
        session: URLSession = OfflineLLMClient.makeSession()
    ) {
        self.model = model
        self.session = session
    }

    func translate(text: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: OfflineLLMClient.systemPrompt),
                Message(role: "user", content: OfflineLLMClient.userPrompt(text: text))
            ],
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OfflineError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.message?.content else {
            throw OfflineError.invalidResponse
        }
        return stripCodeFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"),
              let end = trimmed.range(of: "```", options: .backwards),
              end.lowerBound > trimmed.startIndex else {
            return trimmed
        }
        let contentStart = trimmed.index(trimmed.startIndex, offsetBy: 3)
        var inner = String(trimmed[contentStart..<end.lowerBound])
        if inner.hasPrefix("text") || inner.hasPrefix("markdown") {
            if let newline = inner.firstIndex(of: "\n") {
                inner = String(inner[inner.index(after: newline)...])
            }
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let systemPrompt = """
You are a translation module inside a programming-focused voice input tool.

Your job:
- Translate ALL input to English.
- Preserve meaning exactly. Do not invent facts, commands, logs, or technical conclusions.
- Keep code identifiers, file paths, URLs, and CLI commands unchanged.
- Keep numbers, versions, and punctuation intact when possible.
- Return only the translated text. No extra commentary.

Runtime info (offline LLM):
- Base URL: http://127.0.0.1:11434
- API: POST /api/chat
- Default model: qwen2.5-coder:7b-instruct-q5_1
- Request JSON: {"model":"<model>","messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"stream":false}
- Response JSON: {"message":{"role":"assistant","content":"<string>"}}
"""

    private static func userPrompt(text: String) -> String {
        return """
Translate the following text to English. If it is already English, return it unchanged.

Text:
<<<
\(text)
>>>
"""
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }
}
