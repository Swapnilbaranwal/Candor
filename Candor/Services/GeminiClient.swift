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
/// With no key, requests go to Candor's Cloud Run proxy (`Backend.geminiProxy`), which holds the
/// key on the server. With a key, typed in settings or from `Keys.xcconfig` in development, they go
/// straight to the Gemini API.
struct GeminiClient {
    var apiKey: String
    var model: String

    private static let geminiAPI = "https://generativelanguage.googleapis.com"

    func generate(_ body: [String: Any]) async throws -> [String: Any] {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = key.isEmpty ? (Backend.geminiProxy ?? Self.geminiAPI) : Self.geminiAPI
        guard let url = URL(string: "\(base)/v1beta/models/\(trimmedModel):generateContent") else {
            throw GeminiError.http(0, "Invalid model name")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // "Model is experiencing high demand" (503) is usually momentary, so ask again twice, a
        // little later each time, before giving up. A used-up quota (429) is not: waiting a few
        // seconds does not bring it back, and the traveller is better served by the offline agent.
        var failure = GeminiError.emptyResponse
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(attempt == 1 ? 1.5 : 3))
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return json }
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
            failure = GeminiError.http(status, message)
            guard status == 500 || status == 503 else { break }
        }
        throw failure
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

    /// Asks with Google Search grounding, so the answer can use what's on the web today (events
    /// on the traveller's dates, opening days, new places). Grounded answers can't be forced into
    /// JSON mode, so the JSON is picked out of the text. Returns the text and the web pages used.
    /// Falls back to a plain JSON request when search grounding isn't available.
    func askGrounded(_ prompt: String) async throws -> (text: String, sources: [WebSource]) {
        let message: [String: Any] = ["role": "user", "parts": [["text": prompt]]]
        let body: [String: Any] = ["contents": [message], "tools": [["google_search": [String: Any]()]]]
        do {
            let response = try await generate(body)
            guard let content = Self.firstContent(response) else { throw GeminiError.emptyResponse }
            let text = Self.text(of: content)
            guard !text.isEmpty else { throw GeminiError.emptyResponse }
            return (text, Self.sources(of: response))
        } catch let error as GeminiError {
            // No grounding on this key or model (400): ask without it rather than fail the plan.
            if case .http(let code, _) = error, code == 400 || code == 403 {
                return (try await ask(prompt, json: true), [])
            }
            throw error
        }
    }

    /// A web page Gemini read while answering.
    struct WebSource: Hashable {
        let title: String
        let url: String
    }

    static func sources(of response: [String: Any]) -> [WebSource] {
        let candidate = (response["candidates"] as? [[String: Any]])?.first
        let metadata = candidate?["groundingMetadata"] as? [String: Any]
        let chunks = metadata?["groundingChunks"] as? [[String: Any]] ?? []
        // Kept in chunk order (no de-duplication) so an index from the model lines up.
        return chunks.map { chunk in
            let web = chunk["web"] as? [String: Any]
            let url = web?["uri"] as? String ?? ""
            return WebSource(title: (web?["title"] as? String) ?? url, url: url)
        }
    }

    /// The JSON object in a model answer, even when it's wrapped in ```json fences or prose.
    static func jsonObject(in text: String) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            return object
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
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
