import Foundation

/// Candor's Google Cloud backend.
enum Backend {
    /// Address of the Cloud Run service in `backend/gemini-proxy`, for example
    /// "https://candor-gemini-proxy-xxxxx.asia-south1.run.app". The service holds the Gemini API
    /// key, so no key ships in the app. Empty means there is no backend, and the app needs a key.
    static let geminiProxyURL = ""

    /// The proxy to send Gemini requests to, without a trailing slash, or nil when there is none.
    /// Launching with `-candor.geminiProxyURL <address>` overrides the built-in address.
    static var geminiProxy: String? {
        let override = UserDefaults.standard.string(forKey: "candor.geminiProxyURL") ?? ""
        var address = (override.isEmpty ? geminiProxyURL : override).trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        guard address.hasPrefix("https://") || address.hasPrefix("http://") else { return nil }
        return address
    }
}
