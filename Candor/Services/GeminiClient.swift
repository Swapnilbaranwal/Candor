import Foundation

enum GeminiError: LocalizedError {
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): "Gemini error \(code): \(message)"
        case .emptyResponse: "Gemini returned no answer."
        }
    }
}

/// Minimal REST client for the Gemini API (generateContent with function calling).
///
/// Prototype note: the key is stored on device. For the submission, route these calls
/// through a Cloud Run proxy so the key never ships inside the app.
struct GeminiClient {
    var apiKey: String
    var model: String

    func generate(_ body: [String: Any]) async throws -> [String: Any] {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(trimmedModel):generateContent") else {
            throw GeminiError.http(0, "Invalid model name")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
            throw GeminiError.http(status, message)
        }
        return json
    }

    /// First candidate's content object, e.g. ["role": "model", "parts": [...]].
    static func firstContent(_ response: [String: Any]) -> [String: Any]? {
        let candidates = response["candidates"] as? [[String: Any]]
        return candidates?.first?["content"] as? [String: Any]
    }

    static func text(of content: [String: Any]) -> String {
        let parts = content["parts"] as? [[String: Any]] ?? []
        return parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain text prompt → text answer.
    func ask(_ prompt: String, system: String? = nil, json: Bool = false) async throws -> String {
        let message: [String: Any] = ["role": "user", "parts": [["text": prompt]]]
        var body: [String: Any] = ["contents": [message]]
        if let system {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        if json {
            body["generationConfig"] = ["responseMimeType": "application/json"]
        }
        let response = try await generate(body)
        guard let content = Self.firstContent(response) else { throw GeminiError.emptyResponse }
        let text = Self.text(of: content)
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }

    /// Translates text. Returns (translation, romanised pronunciation if target is Hindi).
    func translate(_ text: String, toHindi: Bool, userLanguage: String) async throws -> (text: String, roman: String?) {
        let prompt: String
        if toHindi {
            prompt = """
            Translate this into natural, polite spoken Hindi for a street conversation in Delhi. \
            Reply as JSON: {"hindi": "<Devanagari>", "roman": "<easy Latin-script pronunciation>"}.
            Text: \(text)
            """
        } else {
            prompt = """
            Translate this Hindi or Hinglish into natural \(userLanguage). \
            Reply as JSON: {"translation": "<text>"}.
            Text: \(text)
            """
        }
        let raw = try await ask(prompt, json: true)
        let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        if toHindi {
            return ((object["hindi"] as? String) ?? raw, object["roman"] as? String)
        }
        return ((object["translation"] as? String) ?? raw, nil)
    }
}
