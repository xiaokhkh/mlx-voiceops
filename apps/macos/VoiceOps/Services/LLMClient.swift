import Foundation

final class LLMClient {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!

    struct Req: Encodable {
        let mode: String
        let text: String
    }

    struct Resp: Decodable {
        let output: String
    }

    func generate(mode: Mode, text: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/llm/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Req(mode: mode.rawValue, text: text))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LLMClient", code: 1)
        }
        return try JSONDecoder().decode(Resp.self, from: data).output
    }
}
