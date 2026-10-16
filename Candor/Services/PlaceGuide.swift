import Foundation
import CoreLocation

/// What a traveller should know once they reach a stop: a line about the place, today's hours,
/// and a few things to do there.
struct PlaceGuideInfo: Equatable {
    var summary: String?
    var thingsToDo: [String]
    /// Today's opening hours, e.g. "5:00 AM – 8:00 PM".
    var hoursToday: String?
    var rating: Double?
    /// "Google Maps" or "Gemini", shown under the list.
    var source: String
}

/// Builds `PlaceGuideInfo` for a trip stop and answers questions about it in place, so the
/// traveller never leaves the Trip tab.
///
/// 1. Google Maps (Places API) for the summary, today's hours and the kind of place.
/// 2. Gemini, when there's a key, for things to do and free-form answers.
/// 3. Without Gemini: Candor's own tip plus ideas that fit the kind of place.
enum PlaceGuide {
    private static var cache: [UUID: PlaceGuideInfo] = [:]

    /// Cached guide, if it's already been looked up: lets an opened stop show it on the first frame.
    static func cached(_ stop: TripStop) -> PlaceGuideInfo? { cache[stop.id] }

    static func info(for stop: TripStop, app: AppState) async -> PlaceGuideInfo {
        if let cached = cache[stop.id] { return cached }
        let details = try? await GooglePlaces.details(stop.name, near: stop.coordinate)
        var info = PlaceGuideInfo(summary: details?.summary ?? stop.spot.map { L($0.blurb) },
                                  thingsToDo: offlineIdeas(for: stop, details: details),
                                  hoursToday: details?.hoursToday,
                                  rating: details?.rating,
                                  source: "Google Maps")
        if app.hasGemini, let ideas = try? await geminiIdeas(for: stop, details: details, app: app), !ideas.isEmpty {
            info.thingsToDo = ideas
            info.source = "Gemini"
        }
        cache[stop.id] = info
        return info
    }

    /// An answer to a question about the stop, shown under the question on the Trip tab.
    /// `leg` is how the traveller gets here, for "what should it cost?".
    static func answer(_ question: String, about stop: TripStop, leg: Leg?, info: PlaceGuideInfo?,
                       app: AppState, agent: CandorAgent) async -> AgentResult {
        if app.hasGemini, let text = try? await geminiAnswer(question, about: stop, leg: leg, info: info, app: app) {
            return AgentResult(text: text, verdict: nil)
        }
        let q = question.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { q.contains($0) } }

        if has(["time", "when", "open", "close", "hour", "crowd", "early", "morning", "evening"]) {
            var lines: [String] = []
            if let hours = info?.hoursToday {
                lines.append(L("Open today **%@**.", hours))
            }
            lines.append(L("Go early in the day: it's cooler, quieter and the light is softer for photos."))
            return AgentResult(text: lines.joined(separator: "\n"), verdict: nil)
        }
        if has(["cost", "price", "how much", "fee", "ticket", "entry", "pay", "₹"]) {
            var lines: [String] = []
            if let tip = stop.spot?.tip, ["ticket", "entry", "free"].contains(where: { tip.lowercased().contains($0) }) {
                lines.append(L(tip))
            } else {
                lines.append(L("Candor doesn't have the entry price for %@ yet. Pay only at the official counter, at the price on the board.", L(stop.name)))
            }
            if let leg {
                let fares = leg.sortedOptions.prefix(3).map { "\($0.mode.title) **\($0.fareText)**" }
                lines.append(L("Getting here from %1$@: %2$@.", L(leg.from), fares.joined(separator: " · ")))
            }
            return AgentResult(text: lines.joined(separator: "\n\n"), verdict: nil)
        }
        if has(["do", "see", "visit", "worth", "spend"]), let ideas = info?.thingsToDo, !ideas.isEmpty {
            return AgentResult(text: ideas.map { "• \($0)" }.joined(separator: "\n"), verdict: nil)
        }
        if has(["watch", "scam", "careful", "safe", "trick", "tout"]) {
            // The offline agent matches "scam" to Candor's travel-smart tips.
            return await agent.run(prompt: "scam tips: \(question) \(stop.spot?.tip ?? "") \(stop.name)") { _ in }
        }
        // Prices, rides and the rest: the agent's own tools know these.
        return await agent.run(prompt: "\(question) (\(stop.name), Delhi)") { _ in }
    }

    // MARK: Gemini

    private static func geminiIdeas(for stop: TripStop, details: GooglePlaces.Details?, app: AppState) async throws -> [String] {
        let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
        let context = [details?.summary, stop.spot?.blurb, stop.spot?.tip].compactMap { $0 }.joined(separator: " ")
        let prompt = """
        A traveller from abroad has just reached \(stop.name) in Delhi. \(context)
        List 4 specific things to do there, in \(app.persona.englishLanguageName), each under 14 words, \
        practical and honest (what to see, where to go inside, what it costs if anything, one thing to watch for).
        Reply as JSON: {"things": ["…", "…"]}
        """
        let text = try await client.ask(prompt, json: true)
        let things = GeminiClient.jsonObject(in: text)?["things"] as? [String] ?? []
        return Array(things.prefix(5))
    }

    private static func geminiAnswer(_ question: String, about stop: TripStop, leg: Leg?, info: PlaceGuideInfo?, app: AppState) async throws -> String {
        let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
        let fares = leg.map { leg in
            "Fair fares from \(leg.from): " + leg.sortedOptions.prefix(4).map { "\($0.mode.title) \($0.fareText)" }.joined(separator: ", ") + "."
        }
        let context = [info?.summary, info?.hoursToday.map { "Open today \($0)." }, stop.spot?.tip, fares]
            .compactMap { $0 }.joined(separator: " ")
        let system = """
        You are Candor, a fair-price travel companion in Delhi. Answer in \(app.persona.englishLanguageName), \
        in at most 4 short lines, plain and practical. Give prices in rupees. If you're not sure, say so.
        """
        return try await client.ask("About \(stop.name), Delhi. \(context)\nQuestion: \(question)", system: system)
    }

    // MARK: Without Gemini

    /// Candor's own tip first, then ideas that suit the kind of place.
    private static func offlineIdeas(for stop: TripStop, details: GooglePlaces.Details?) -> [String] {
        var ideas: [String] = []
        if let tip = stop.spot?.tip { ideas.append(L(tip)) }
        let types = Set(details?.types ?? [])
        func any(_ names: [String]) -> Bool { !types.isDisjoint(with: names) }

        if any(["park", "garden", "national_park", "botanical_garden"]) {
            ideas += [L("Take a slow walk; mornings are cooler and quieter."),
                      L("Find a shaded lawn for a break, and carry water."),
                      L("Look out for the monuments and old trees along the paths.")]
        } else if any(["hindu_temple", "mosque", "church", "place_of_worship", "sikh_temple", "gurudwara"]) {
            ideas += [L("Dress modestly, with shoulders and knees covered."),
                      L("Leave your shoes at the counter, which is usually free."),
                      L("Ask before taking photos inside.")]
        } else if any(["museum", "art_gallery"]) {
            ideas += [L("Buy tickets at the official counter and check the foreigner rate."),
                      L("Ask about an audio guide at the entrance."),
                      L("Give the main galleries at least an hour.")]
        } else if any(["market", "shopping_mall", "store", "clothing_store", "jewelry_store"]) {
            ideas += [L("Ask the price first, then check it with Candor before you pay."),
                      L("Carry small notes; change is often short."),
                      L("Keep your bag in front in crowded lanes.")]
        } else if any(["restaurant", "cafe", "food", "bakery", "meal_takeaway"]) {
            ideas += [L("Pick busy stalls: high turnover means fresh food."),
                      L("Check prices on the menu before you order.")]
        } else {
            ideas += [L("Buy tickets only at the official counter or online."),
                      L("Hire a guide only at the official desk, never at the gate."),
                      L("Go early for fewer crowds and softer light.")]
        }
        return Array(ideas.prefix(4))
    }
}

extension GooglePlaces {
    /// What Google Maps knows about a place: its summary, kind, rating and today's hours.
    struct Details {
        var summary: String?
        var types: [String]
        var rating: Double?
        var hoursToday: String?
        /// The week's opening hours, when Google Maps has them.
        var openingHours: OpeningHours?
    }

    static func details(_ name: String, near coordinate: CLLocationCoordinate2D) async throws -> Details? {
        let key = apiKey
        guard !key.isEmpty, let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else { return nil }
        let body: [String: Any] = [
            "textQuery": name,
            "maxResultCount": 1,
            "languageCode": Localizer.shared.language,
            "locationBias": ["circle": ["center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                                        "radius": 2_000]]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.editorialSummary,places.generativeSummary,places.types,places.rating,places.regularOpeningHours.weekdayDescriptions,places.regularOpeningHours.periods",
                         forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let place = (json["places"] as? [[String: Any]])?.first else { return nil }

        let editorial = (place["editorialSummary"] as? [String: Any])?["text"] as? String
        let generative = ((place["generativeSummary"] as? [String: Any])?["overview"] as? [String: Any])?["text"] as? String
        let days = (place["regularOpeningHours"] as? [String: Any])?["weekdayDescriptions"] as? [String] ?? []
        // Google lists Monday first; Calendar's weekday is 1 for Sunday.
        let weekday = Calendar.current.component(.weekday, from: .now)
        let today = days.count == 7 ? days[(weekday + 5) % 7] : nil
        let hours = today?.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        return Details(summary: editorial ?? generative,
                       types: place["types"] as? [String] ?? [],
                       rating: place["rating"] as? Double,
                       hoursToday: hours,
                       openingHours: openingHours(place["regularOpeningHours"] as? [String: Any]))
    }

    /// Google's `regularOpeningHours.periods` as `OpeningHours`. A period with no close is open around the clock.
    private static func openingHours(_ raw: [String: Any]?) -> OpeningHours? {
        let periods = raw?["periods"] as? [[String: Any]] ?? []
        guard !periods.isEmpty else { return nil }
        if periods.count == 1, periods[0]["close"] == nil { return .always }
        let parsed = periods.compactMap { period -> OpeningHours.Period? in
            guard let open = period["open"] as? [String: Any], let close = period["close"] as? [String: Any],
                  let day = open["day"] as? Int else { return nil }
            let opens = (open["hour"] as? Int ?? 0) * 60 + (open["minute"] as? Int ?? 0)
            var closes = (close["hour"] as? Int ?? 0) * 60 + (close["minute"] as? Int ?? 0)
            if (close["day"] as? Int) != day { closes += 24 * 60 }
            return OpeningHours.Period(day: day, open: opens, close: closes)
        }
        return parsed.isEmpty ? nil : OpeningHours(periods: parsed)
    }
}
