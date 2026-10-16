import Foundation

/// Prices and tricks shared anonymously by Candor travellers, kept in Firestore by the Cloud Run
/// backend (`backend/gemini-proxy`, see community.js). Nothing personal is sent: no name, no account,
/// no device id, and locations are rounded to about 1 km on the server.
///
/// Sharing can be turned off in Me → Preferences. Without a backend address every call is a no-op.
enum CommunityService {
    struct Stats: Decodable {
        let reports: Int
        let medianPaidINR: Double?
        let lowPaidINR: Double?
        let highPaidINR: Double?
        let medianAskedINR: Double?
        let note: String?
    }

    static let shareKey = "candor.shareChecks"

    /// On unless the traveller turned it off.
    static var sharingOn: Bool {
        UserDefaults.standard.object(forKey: shareKey) as? Bool ?? true
    }

    /// What travellers paid for an item in a city, or nil without a backend or on any error.
    static func stats(item: String, city: String) async -> Stats? {
        guard let base = Backend.geminiProxy,
              var components = URLComponents(string: base + "/v1/community/prices") else { return nil }
        components.queryItems = [URLQueryItem(name: "city", value: city), URLQueryItem(name: "item", value: item)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Stats.self, from: data)
    }

    /// Shares one price check (what was asked, and the fair range Candor found).
    static func sharePrice(item: String, city: String, askedINR: Double?, paidINR: Double? = nil,
                           fairLowINR: Double?, fairHighINR: Double?) {
        guard askedINR != nil || paidINR != nil else { return }
        var body: [String: Any] = ["item": item, "city": city]
        if let askedINR { body["askedINR"] = askedINR }
        if let paidINR { body["paidINR"] = paidINR }
        if let fairLowINR { body["fairLowINR"] = fairLowINR }
        if let fairHighINR { body["fairHighINR"] = fairHighINR }
        post("/v1/community/prices", body)
    }

    /// Shares that a known trick happened, with a rough location for the hotspot map.
    static func reportScam(_ title: String, city: String, latitude: Double?, longitude: Double?) {
        var body: [String: Any] = ["scam": title, "city": city]
        if let latitude, let longitude {
            body["lat"] = latitude
            body["lon"] = longitude
        }
        post("/v1/community/reports", body)
    }

    /// Fire and forget: sharing must never slow down or break a check.
    private static func post(_ path: String, _ body: [String: Any]) {
        guard sharingOn, let base = Backend.geminiProxy, let url = URL(string: base + path) else { return }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 8
        Task.detached(priority: .utility) { _ = try? await URLSession.shared.data(for: request) }
    }
}
