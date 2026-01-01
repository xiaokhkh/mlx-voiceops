import Foundation

final class CodexClient {
    enum CodexError: Error {
        case missingConfig
        case invalidResponse
    }

    struct Config {
        let baseURL: URL
        let apiKey: String
        let model: String
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct ResponseMessage: Decodable {
                let content: String?
            }
            let message: ResponseMessage?
        }
        let choices: [Choice]?
    }

    private let config: Config?
    private let session: URLSession

    init(config: Config? = nil, session: URLSession = CodexClient.makeSession()) {
        if let config {
            self.config = config
        } else {
            self.config = CodexClient.loadConfigFromEnv()
        }
        self.session = session
    }

    func rewrite(text: String) async throws -> String {
        guard let config else { throw CodexError.missingConfig }
        let url = endpointURL(baseURL: config.baseURL)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = RequestBody(
            model: config.model,
            messages: [
                Message(role: "system", content: CodexClient.systemPrompt),
                Message(role: "user", content: CodexClient.userPrompt(text: text))
            ],
            temperature: 0.2,
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CodexError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices?.first?.message?.content else {
            throw CodexError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func endpointURL(baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("chat/completions")
        }
        return baseURL.appendingPathComponent("v1/chat/completions")
    }

    private static func loadConfigFromEnv() -> Config? {
        let env = ProcessInfo.processInfo.environment
        let base = env["CODEX_BASE_URL"] ?? "https://api.openai.com"
        let key = env["CODEX_API_KEY"] ?? ""
        let model = env["CODEX_MODEL"] ?? "gpt-4o-mini"
        guard !key.isEmpty, let baseURL = URL(string: base) else { return nil }
        return Config(baseURL: baseURL, apiKey: key, model: model)
    }

    private static let systemPrompt = """
You are an advanced rewrite engine for engineering text.
Rewrite the user's text into clear, structured, and concise technical prose.
Preserve meaning and do not invent facts, commands, or logs.
If information is missing, insert TODO placeholders instead of guessing.
Return plain text only.
"""

    private static func userPrompt(text: String) -> String {
        return """
Rewrite the following text:
<<<
\(text)
>>>
"""
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }
}
