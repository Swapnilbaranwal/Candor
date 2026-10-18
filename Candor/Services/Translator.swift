import Foundation
import AVFoundation
import Speech

// MARK: - Languages

/// A language the interpreter speaks: India's main languages plus the ones travellers arrive with.
struct InterpreterLanguage: Hashable, Identifiable {
    /// Google Translate code ("hi", "ta", "zh-CN").
    let code: String
    /// Locale for speech recognition and the speaking voice ("hi-IN").
    let speechLocale: String
    var id: String { code }

    /// The language's own name for itself ("हिन्दी", "Español").
    var name: String { Persona.nativeName(of: code) }

    private static func make(_ code: String, _ locale: String) -> InterpreterLanguage {
        InterpreterLanguage(code: code, speechLocale: locale)
    }

    /// Spoken around India, Hindi first.
    static let indian: [InterpreterLanguage] = [
        make("hi", "hi-IN"), make("en", "en-IN"), make("bn", "bn-IN"), make("ta", "ta-IN"),
        make("te", "te-IN"), make("mr", "mr-IN"), make("gu", "gu-IN"), make("kn", "kn-IN"),
        make("ml", "ml-IN"), make("pa", "pa-IN"), make("ur", "ur-IN"), make("or", "or-IN")
    ]

    /// Travellers' languages.
    static let world: [InterpreterLanguage] = [
        make("en", "en-US"), make("es", "es-ES"), make("fr", "fr-FR"), make("de", "de-DE"),
        make("it", "it-IT"), make("pt", "pt-BR"), make("ru", "ru-RU"), make("ja", "ja-JP"),
        make("ko", "ko-KR"), make("zh-CN", "zh-CN"), make("ar", "ar-SA"), make("he", "he-IL"),
        make("nl", "nl-NL"), make("tr", "tr-TR"), make("th", "th-TH"), make("vi", "vi-VN"),
        make("id", "id-ID"), make("pl", "pl-PL")
    ]

    static let hindi = indian[0]

    /// The traveller's own language, from their persona code ("zh" maps to Simplified Chinese).
    static func forPersona(_ code: String) -> InterpreterLanguage {
        world.first { $0.code == code || $0.code.hasPrefix(code + "-") }
            ?? indian.first { $0.code == code }
            ?? make(code, code)
    }
}

// MARK: - Translation

enum TranslatorError: LocalizedError {
    case notConfigured, failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: L("Translation needs the Google key or Gemini. Check AI settings in Me.")
        case .failed(let message): message
        }
    }
}

/// Translates between any two languages with Google Translate (Cloud Translation API, on the
/// app's Google key). If the key doesn't have the Translation API turned on, Gemini translates.
enum Translator {
    private static let endpoint = "https://translation.googleapis.com/language/translate/v2"

    static func translate(_ text: String, from source: InterpreterLanguage, to target: InterpreterLanguage,
                          app: AppState) async throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, source.code != target.code else { return text }
        var googleError: Error?
        if !GooglePlaces.apiKey.isEmpty {
            do { return try await google(text, from: source.code, to: target.code) } catch { googleError = error }
        }
        guard app.hasGemini else { throw googleError ?? TranslatorError.notConfigured }
        return try await gemini(text, from: source, to: target, app: app)
    }

    private static func google(_ text: String, from source: String, to target: String) async throws -> String {
        guard let url = URL(string: "\(endpoint)?key=\(GooglePlaces.apiKey)") else { throw TranslatorError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Keys restricted to iOS apps check this header.
        if let bundle = Bundle.main.bundleIdentifier { request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": text, "source": source, "target": target, "format": "text"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let translations = (json["data"] as? [String: Any])?["translations"] as? [[String: Any]],
              let translated = translations.first?["translatedText"] as? String else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Translation failed"
            throw TranslatorError.failed(message)
        }
        return translated
    }

    private static func gemini(_ text: String, from source: InterpreterLanguage, to target: InterpreterLanguage,
                               app: AppState) async throws -> String {
        let english = Locale(identifier: "en")
        let from = english.localizedString(forIdentifier: source.code) ?? source.code
        let to = english.localizedString(forIdentifier: target.code) ?? target.code
        let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
        let prompt = """
        Translate this \(from) into natural, polite spoken \(to), as a traveller in India would say it \
        face to face. Use \(to)'s own script. Reply as JSON: {"translation": "<text>"}.
        Text: \(text)
        """
        let raw = try await client.ask(prompt, json: true)
        return GeminiClient.jsonObject(in: raw)?["translation"] as? String ?? raw
    }
}

// MARK: - Listening

/// Live speech to text in a chosen language, for the interpreter's mic buttons.
@MainActor
@Observable
final class SpeechListener {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var error: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// Asks for the microphone and speech recognition, then listens until `stop()`.
    func start(locale: String) async {
        stop()
        error = nil
        transcript = ""
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized, await AVAudioApplication.requestRecordPermission() else {
            error = L("Allow the microphone and speech recognition in Settings to talk to the interpreter.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            error = L("Listening isn't available in this language on this phone. Type instead.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            Self.feed(engine.inputNode, into: request)
            engine.prepare()
            try engine.start()
            isListening = true
            task = Self.recognize(recognizer, request) { [weak self] text, done in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.stop() }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    // The audio tap and the recogniser call back on their own threads, so their closures are
    // made here, off the main actor; results hop back to it.

    nonisolated private static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer,
                                              _ request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @MainActor (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, failure in
            let text = result?.bestTranscription.formattedString
            let done = failure != nil || result?.isFinal == true
            Task { @MainActor in update(text, done) }
        }
    }

    func stop() {
        guard isListening || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        // Hand the audio back so the translation can be spoken out loud.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
}
