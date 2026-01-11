import Foundation

final class OfflineLLMClient {
    enum OfflineError: Error {
        case invalidResponse
    }

    private enum WarmUpState {
        case idle
        case running
        case done
    }

    private static var warmUpState: WarmUpState = .idle

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

    private struct StreamResponseBody: Decodable {
        let message: Message?
        let done: Bool?
    }

    enum PromptProfile {
        case translation
        case voice
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

    func warmUp() async {
        if Self.warmUpState != .idle {
            return
        }
        Self.warmUpState = .running
        do {
            _ = try await translate(text: "Hello", profile: .voice)
            Self.warmUpState = .done
        } catch {
            Self.warmUpState = .idle
        }
    }

    func translate(text: String, profile: PromptProfile = .translation) async throws -> String {
        try await chat(
            messages: [ChatMessage(role: "user", content: text, applyTemplate: true)],
            profile: profile
        )
    }

    struct ChatMessage {
        let role: String
        let content: String
        let applyTemplate: Bool
    }

    func chat(messages: [ChatMessage], profile: PromptProfile = .translation) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mapped = messages.map { message in
            if message.role == "user", message.applyTemplate {
                return Message(role: "user", content: OfflineLLMClient.userPrompt(text: message.content, profile: profile))
            }
            return Message(role: message.role, content: message.content)
        }

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: OfflineLLMClient.loadSystemPrompt(profile: profile))
            ] + mapped,
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

    func chatStream(
        messages: [ChatMessage],
        profile: PromptProfile = .translation,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mapped = messages.map { message in
            if message.role == "user", message.applyTemplate {
                return Message(role: "user", content: OfflineLLMClient.userPrompt(text: message.content, profile: profile))
            }
            return Message(role: message.role, content: message.content)
        }

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: OfflineLLMClient.loadSystemPrompt(profile: profile))
            ] + mapped,
            stream: true
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OfflineError.invalidResponse
        }

        var buffer = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed == "[DONE]" { break }
            let payload = trimmed.hasPrefix("data: ") ? String(trimmed.dropFirst(6)) : trimmed
            guard let data = payload.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(StreamResponseBody.self, from: data) else {
                continue
            }
            if let content = decoded.message?.content, !content.isEmpty {
                buffer += content
                onDelta(content)
            }
            if decoded.done == true {
                break
            }
        }
        return stripCodeFence(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
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

    static let translationSystemPromptDefaultsKey = "offlineTranslationSystemPrompt"
    static let translationUserPromptDefaultsKey = "offlineTranslationUserPromptTemplate"
    static let voiceSystemPromptDefaultsKey = "offlineVoiceSystemPrompt"
    static let voiceUserPromptDefaultsKey = "offlineVoiceUserPromptTemplate"

    static let defaultTranslationSystemPrompt = """
You are an English teacher who translates text for a programming-focused tool.

Your job:
- Primarily translate English to Chinese. If the input is already Chinese, polish it for clarity.
- Keep the meaning exact. Do not invent facts, commands, logs, or technical conclusions.
- Preserve code identifiers, file paths, URLs, and CLI commands verbatim.
- Keep numbers, versions, and punctuation intact when possible.
- Normalize temporal references to be consistent. If multiple different weekdays appear, standardize them to avoid conflicts.
- Use natural, fluent Chinese with clear, teacher-like phrasing.
- Return only the translated text. No extra commentary.

Runtime info (offline LLM):
- Base URL: http://127.0.0.1:11434
- API: POST /api/chat
- Default model: qwen2.5-coder:7b-instruct-q5_1
- Request JSON: {"model":"<model>","messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"stream":false}
- Response JSON: {"message":{"role":"assistant","content":"<string>"}}
"""

    static let defaultTranslationUserPromptTemplate = """
Translate the following text to Chinese. If it is already Chinese, polish it for clarity while preserving meaning and terminology.

Text:
<<<
{{text}}
>>>
"""

    static let defaultVoiceSystemPrompt = """
You are a writing-focused English-to-Chinese translator for voice input.

Your job:
- Translate spoken English into clear, natural Chinese.
- If the input is already Chinese, polish it for clarity.
- Preserve technical terms, code identifiers, file paths, URLs, and CLI commands.
- Remove filler words and false starts, but do not change meaning.
- Keep numbers, versions, and punctuation intact when possible.
- Return only the translated text. No extra commentary.
"""

    static let defaultVoiceUserPromptTemplate = """
Translate the following spoken text to Chinese. Keep it concise and natural.

Text:
<<<
{{text}}
>>>
"""

    private static func loadSystemPrompt(profile: PromptProfile) -> String {
        let key: String
        let fallback: String
        switch profile {
        case .translation:
            key = translationSystemPromptDefaultsKey
            fallback = defaultTranslationSystemPrompt
        case .voice:
            key = voiceSystemPromptDefaultsKey
            fallback = defaultVoiceSystemPrompt
        }
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : stored
    }

    private static func loadUserPromptTemplate(profile: PromptProfile) -> String {
        let key: String
        let fallback: String
        switch profile {
        case .translation:
            key = translationUserPromptDefaultsKey
            fallback = defaultTranslationUserPromptTemplate
        case .voice:
            key = voiceUserPromptDefaultsKey
            fallback = defaultVoiceUserPromptTemplate
        }
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : stored
    }

    private static func userPrompt(text: String, profile: PromptProfile) -> String {
        var template = loadUserPromptTemplate(profile: profile)
        if !template.contains("{{text}}") {
            template += "\n\nText:\n<<<\n{{text}}\n>>>\n"
        }
        return template.replacingOccurrences(of: "{{text}}", with: text)
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }
}
