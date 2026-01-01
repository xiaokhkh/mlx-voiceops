import Foundation

final class ASRClient {
    private let baseURL = URL(string: "http://127.0.0.1:8765")!

    struct Resp: Decodable {
        let text: String
    }

    func transcribe(wavURL: URL) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/asr/transcribe"))
        req.httpMethod = "POST"

        let boundary = "----VoiceOpsBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }

        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        add("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: wavURL))
        add("\r\n--\(boundary)--\r\n")

        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ASRClient", code: 1)
        }
        return try JSONDecoder().decode(Resp.self, from: data).text
    }
}
