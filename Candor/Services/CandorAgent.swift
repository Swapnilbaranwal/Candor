import SwiftUI
import CoreLocation

/// Chat state for the Agent tab. Every run goes through `AgentEngine`, which
/// streams visible steps (tool calls) back to the UI.
@Observable
final class CandorAgent {
    var messages: [ChatMessage] = []
    var isWorking = false
    /// Wall-clock time of the last finished run and which agent answered. Read by the UI tests' benchmark.
    private(set) var lastRunSeconds: Double = 0
    private(set) var lastRunMode = "none"

    private let app: AppState
    private let engine: AgentEngine

    init(app: AppState, location: LocationService) {
        self.app = app
        self.engine = AgentEngine(app: app, location: location)
    }

    var toolCount: Int { AgentEngine.toolNames.count }

    /// `canonical` is the English original of a ready-made prompt shown in another language.
    /// Gemini reads any language; the offline agent matches English keywords and uses `canonical`.
    func send(_ text: String, image: UIImage? = nil, canonical: String? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil, !isWorking else { return }
        isWorking = true
        let started = Date()

        let history = messages.suffix(8).compactMap { message -> (role: String, text: String)? in
            message.text.isEmpty ? nil : (message.role == .user ? "user" : "model", message.text)
        }

        messages.append(ChatMessage(role: .user, text: trimmed, image: image))
        let reply = ChatMessage(role: .agent, text: "", isWorking: true)
        let replyID = reply.id
        messages.append(reply)

        let prompt = trimmed.isEmpty ? "What is in this photo, and is the price fair?" : trimmed
        let result = await engine.run(prompt: prompt, image: image, history: history, canonical: canonical) { [weak self] step in
            self?.upsert(step, into: replyID)
        }

        if let index = messages.firstIndex(where: { $0.id == replyID }) {
            withAnimation(.smooth) {
                messages[index].text = result.text
                messages[index].verdict = result.verdict
                messages[index].isWorking = false
            }
        }
        if let verdict = result.verdict, verdict.askedINR != nil {
            app.record(PriceCheckRecord(verdict: verdict, kind: image == nil ? .agent : .scan))
        }
        lastRunSeconds = Date().timeIntervalSince(started)
        lastRunMode = engine.lastRunMode
        isWorking = false
    }

    /// One-off run for other screens (Scan, Scam radar) that show their own trail.
    func run(prompt: String, image: UIImage? = nil, onStep: @escaping (AgentStep) -> Void) async -> AgentResult {
        await engine.run(prompt: prompt, image: image, history: [], onStep: onStep)
    }

    func clear() {
        guard !isWorking else { return }
        messages.removeAll()
    }

    private func upsert(_ step: AgentStep, into messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        withAnimation(.snappy) {
            if let stepIndex = messages[index].steps.firstIndex(where: { $0.id == step.id }) {
                messages[index].steps[stepIndex] = step
            } else {
                messages[index].steps.append(step)
            }
        }
    }
}

/// Upserts a step into an array (helper for screens that keep their own trail).
func upsertStep(_ step: AgentStep, in steps: inout [AgentStep]) {
    if let index = steps.firstIndex(where: { $0.id == step.id }) {
        steps[index] = step
    } else {
        steps.append(step)
    }
}

// MARK: - Engine

final class AgentEngine {
    static let toolNames = ["lookup_price", "estimate_fare", "route_distance", "check_scam", "find_nearby", "convert_currency", "report_verdict"]

    private let app: AppState
    private let location: LocationService
    private var onStep: (AgentStep) -> Void = { _ in }
    /// "gemini", "offline", or "gemini-failed" when Gemini errored and the offline agent answered.
    private(set) var lastRunMode = "none"

    init(app: AppState, location: LocationService) {
        self.app = app
        self.location = location
    }

    func run(prompt: String,
             image: UIImage?,
             history: [(role: String, text: String)],
             canonical: String? = nil,
             onStep: @escaping (AgentStep) -> Void) async -> AgentResult {
        self.onStep = onStep
        lastRunMode = "offline"
        if app.hasGemini {
            do {
                let result = try await runGemini(prompt: prompt, image: image, history: history)
                lastRunMode = "gemini"
                return result
            } catch {
                lastRunMode = "gemini-failed"
                // The API's own message is long and technical: it goes to the console, and the
                // traveller sees one short sentence.
                print("Gemini failed: \(error.localizedDescription)")
                var step = AgentStep(icon: "wifi.exclamationmark", title: L("Gemini unavailable"),
                                     detail: L("%@ Switching to the offline agent.", Self.reason(for: error)))
                step.state = .failed
                emit(step)
            }
        }
        return await runOffline(prompt: canonical ?? prompt, image: image)
    }

    /// Why Gemini did not answer, in one short sentence.
    private static func reason(for error: Error) -> String {
        switch error {
        case GeminiError.http(429, _): L("Gemini's usage limit is reached.")
        case GeminiError.http(503, _), GeminiError.http(500, _):
            L("Gemini is busy right now. Try again in a minute.")
        case GeminiError.http(400, let message) where message.lowercased().contains("api key"):
            L("Gemini says the API key isn't valid. Check it in Me.")
        case GeminiError.http(401, _), GeminiError.http(403, _):
            L("Gemini rejected the API key (it may be restricted or not enabled for the Gemini API). Check it in Me.")
        case GeminiError.http(404, _): L("No Gemini model is available to this key.")
        case GeminiError.http(let code, _): L("Gemini returned error %@.", code)
        case is URLError: L("Couldn't reach Gemini. Check the internet connection.")
        default: L("Gemini couldn't answer.")
        }
    }

    // MARK: Step helpers

    private func emit(_ step: AgentStep) {
        onStep(step)
    }

    private func begin(_ icon: String, _ title: String, _ detail: String) -> AgentStep {
        let step = AgentStep(icon: icon, title: title, detail: detail)
        emit(step)
        return step
    }

    private func finish(_ step: AgentStep, detail: String? = nil, failed: Bool = false) {
        var updated = step
        if let detail { updated.detail = detail }
        updated.state = failed ? .failed : .done
        emit(updated)
    }

    private func pause(_ ms: Int = 450) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: Gemini (function calling loop)

    /// Where the traveller is and how much Candor knows there. Candor's own data (prices, fares,
    /// scams) covers verified cities only; elsewhere the agent must say its figures are estimates.
    private var tripContext: String {
        guard let trip = app.trip, !trip.cities.isEmpty else {
            return "Candor's verified data covers Delhi. Trip details: not given."
        }
        let route = trip.cities.map { stay in
            let dates = stay.arrival.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en")))
                + "–" + stay.departure.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en")))
            return "\(stay.city.name) (\(dates); \(stay.city.coverage == .verified ? "verified data" : "no verified data, give estimates and say so"); stay: \(stay.staySummary))"
        }.joined(separator: " → ")
        let current = trip.cityStay(on: .now)?.city.name ?? trip.cities[0].city.name
        return "Trip: \(route). Current city: \(current). Party: \(trip.partySummary). " +
            "Candor's tools (prices, fares, scams, places) hold verified data for Delhi only."
    }

    private var systemPrompt: String {
        let p = app.persona
        let interests = p.interests.isEmpty ? "general sightseeing" : p.interests.joined(separator: ", ")
        return """
        You are Candor, a travel agent inside an iPhone app for foreign visitors in India. \(tripContext)
        Traveller: \(p.name.isEmpty ? "unnamed" : p.name). Language: \(p.englishLanguageName). Home currency: \(p.homeCurrency). \
        Style: \(p.travelStyle.rawValue). Interests: \(interests). Preferences: \(p.tasteSummary). \
        Local time: \(Date.now.formatted(date: .abbreviated, time: .shortened)). Measuring from: \(location.originName).

        Rules:
        - Always reply in \(p.englishLanguageName). Be warm, concise and practical; prefer short bullet points.
        - Never invent prices. Ground every price in a tool result (lookup_price, estimate_fare) or in a printed MRP you can clearly read in a photo. If there is no data, say so and give bargaining guidance instead.
        - On packaged goods in India the printed MRP is the legal maximum retail price, including taxes.
        - For rides: call route_distance for the destination, then estimate_fare.
        - Whenever you judge a specific price, call report_verdict exactly once with the fair range in INR so the app can show a verdict card. Write its `item` in \(p.englishLanguageName); copy `source` exactly as a tool returned it.
        - Tool results are mostly in English. Translate what you use from them into \(p.englishLanguageName).
        - When quoting an INR amount, also give it in the traveller's home currency using convert_currency.
        - For situations that feel off, call check_scam and give clear next steps.
        - Be respectful about locals: most people are honest. Frame advice as price transparency, not distrust.
        """
    }

    private var toolDeclarations: [[String: Any]] {
        func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
        func number(_ description: String) -> [String: Any] { ["type": "number", "description": description] }
        func function(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
            let parameters: [String: Any] = ["type": "object", "properties": properties, "required": required]
            return ["name": name, "description": description, "parameters": parameters]
        }
        return [
            function("lookup_price",
                     "Look up fair reference prices in Delhi for food, drinks, packaged goods, metro and short rides.",
                     ["query": string("Item to look up, e.g. 'masala chai' or '1 litre water bottle'.")],
                     required: ["query"]),
            function("route_distance",
                     "Find a destination in Delhi and return the driving distance from the traveller.",
                     ["destination": string("Place name or address.")],
                     required: ["destination"]),
            function("estimate_fare",
                     "Compute the official metered fare for an auto-rickshaw or taxi in Delhi.",
                     ["mode": ["type": "string", "enum": ["auto", "taxi", "taxi_ac"], "description": "Vehicle type."] as [String: Any],
                      "distance_km": number("Trip distance in km."),
                      "night": ["type": "boolean", "description": "True between 11 pm and 5 am."] as [String: Any]],
                     required: ["mode", "distance_km"]),
            function("check_scam",
                     "Match a situation against Candor's database of common tourist scams in Delhi.",
                     ["situation": string("What is happening, in the traveller's words.")],
                     required: ["situation"]),
            function("find_nearby",
                     "List verified places from Candor's Delhi list, nearest first.",
                     ["category": ["type": "string", "enum": ["sight", "fixed_price", "market", "transport", "any"], "description": "Kind of place."] as [String: Any]],
                     required: ["category"]),
            function("convert_currency",
                     "Convert an INR amount into the traveller's home currency.",
                     ["amount_inr": number("Amount in Indian rupees.")],
                     required: ["amount_inr"]),
            function("report_verdict",
                     "Show the traveller a verdict card for one specific price check. Call once per check.",
                     ["item": string("What is being priced."),
                      "fair_low_inr": number("Low end of the fair range in INR."),
                      "fair_high_inr": number("High end of the fair range in INR."),
                      "asked_inr": number("Price being asked, if known."),
                      "source": string("Where the fair range comes from, e.g. 'Printed MRP' or 'Delhi fare chart'.")],
                     required: ["item", "fair_low_inr", "fair_high_inr", "source"])
        ]
    }

    private func runGemini(prompt: String, image: UIImage?, history: [(role: String, text: String)]) async throws -> AgentResult {
        let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
        var contents: [[String: Any]] = history.map { entry -> [String: Any] in
            ["role": entry.role, "parts": [["text": entry.text]]]
        }

        var parts: [[String: Any]] = [["text": prompt]]
        if let image, let data = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.7) {
            let read = begin("eye", L("Reading your photo"), "Gemini vision · \(app.geminiModel)")
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": data.base64EncodedString()]])
            finish(read, detail: L("Photo attached (%@ KB)", data.count / 1024))
        }
        contents.append(["role": "user", "parts": parts])

        var verdict: PriceVerdict?
        var thinking = begin("brain.head.profile", L("Planning"), "Gemini · \(app.geminiModel)")
        // A price check is a short tool-calling job, so ask Gemini 3 for light reasoning: it answers sooner.
        var thinkingLevel: String? = "low"

        for _ in 0..<6 {
            var body: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": contents,
                "tools": [["functionDeclarations": toolDeclarations]]
            ]
            if let thinkingLevel {
                body["generationConfig"] = ["thinkingConfig": ["thinkingLevel": thinkingLevel]]
            }
            let response: [String: Any]
            do {
                do {
                    response = try await client.generate(body)
                } catch GeminiError.http(400, _) where thinkingLevel != nil {
                    // A model that doesn't know this setting rejects the request: drop it and ask again.
                    thinkingLevel = nil
                    body["generationConfig"] = nil
                    response = try await client.generate(body)
                }
            } catch {
                // Close the step that was waiting on Gemini, or it keeps spinning above the failure line.
                finish(thinking, failed: true)
                throw error
            }
            guard let content = GeminiClient.firstContent(response) else {
                finish(thinking, failed: true)
                throw GeminiError.emptyResponse
            }
            contents.append(content)

            let responseParts = content["parts"] as? [[String: Any]] ?? []
            let calls = responseParts.compactMap { $0["functionCall"] as? [String: Any] }

            if calls.isEmpty {
                finish(thinking, detail: L("Answer ready"))
                let text = GeminiClient.text(of: content)
                return AgentResult(text: text.isEmpty ? L("Done. See the result above.") : text, verdict: verdict)
            }

            finish(thinking, detail: L("Calling tools: %@", calls.count))
            var functionResponses: [[String: Any]] = []
            for call in calls {
                let name = call["name"] as? String ?? ""
                let args = call["args"] as? [String: Any] ?? [:]
                let output = await execute(name, args)
                if let v = output.verdict { verdict = v }
                let functionResponse: [String: Any] = ["name": name, "response": output.result]
                functionResponses.append(["functionResponse": functionResponse])
            }
            contents.append(["role": "user", "parts": functionResponses])
            thinking = begin("brain.head.profile", L("Reasoning over results"), "Gemini · \(app.geminiModel)")
        }

        finish(thinking, detail: L("Stopped after 6 rounds"))
        return AgentResult(text: L("I gathered the details above but couldn't finish the answer. Please try rephrasing."), verdict: verdict)
    }

    // MARK: Tools

    private struct ToolOutput {
        var result: [String: Any]
        var verdict: PriceVerdict?
    }

    private func numberValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private func execute(_ name: String, _ args: [String: Any]) async -> ToolOutput {
        switch name {
        case "lookup_price":
            let query = args["query"] as? String ?? ""
            let step = begin("tag.fill", L("Checking price reference"), query)
            await pause(250)
            let matches = DelhiData.lookup(query)
            guard let top = matches.first else {
                finish(step, detail: L("No reference for \"%@\"", query))
                return ToolOutput(result: ["found": false,
                                           "guidance": "No reference price. In bargaining markets, open around 50–60% of the first quote. MRP items are never negotiable upward."])
            }
            finish(step, detail: "\(L(top.item)): \(Self.range(top))")
            return ToolOutput(result: ["found": true, "matches": Array(matches.prefix(3)).map { $0.dictionary }])

        case "route_distance":
            let destination = args["destination"] as? String ?? ""
            let step = begin("arrow.triangle.turn.up.right.diamond.fill", L("Measuring route"), "\(location.originName) \(Localizer.shared.arrow) \(destination)")
            if let route = await Routing.distance(to: destination, from: location.origin) {
                let distance = L("%@ km by road", route.km.formatted(.number.precision(.fractionLength(1))))
                finish(step, detail: "\(L(route.name)) · \(distance)")
                return ToolOutput(result: ["destination": route.name, "distance_km": (route.km * 10).rounded() / 10, "from": location.originName])
            }
            finish(step, detail: L("Couldn't find \"%@\"", destination), failed: true)
            return ToolOutput(result: ["error": "Destination not found. Ask the traveller for a nearby landmark."])

        case "estimate_fare":
            let mode = RideMode(apiName: args["mode"] as? String ?? "auto")
            let km = max(0, numberValue(args["distance_km"]) ?? 0)
            let night = (args["night"] as? Bool) ?? FareChart.isNight()
            let step = begin("gauge.with.needle.fill", L("Applying Delhi fare chart"), "\(mode.title) · \(km.formatted(.number.precision(.fractionLength(1)))) km")
            await pause(250)
            let fare = mode.fare(km: km, night: night)
            let fareText = L("Metered fare ≈ %@", inr(fare))
            finish(step, detail: night ? "\(fareText) \(L("(night)"))" : fareText)
            return ToolOutput(result: ["mode": mode.title,
                                       "distance_km": km,
                                       "metered_fare_inr": fare,
                                       "fair_upper_inr": (fare * 1.2).rounded(),
                                       "night_rate_applied": night,
                                       "rule": mode.ruleText,
                                       "source": FareChart.source])

        case "check_scam":
            let situation = args["situation"] as? String ?? ""
            let step = begin("shield.lefthalf.filled", L("Scanning scam radar"), L("%@ known patterns", DelhiData.scams.count))
            await pause(300)
            let matches = DelhiData.matchScams(situation)
            finish(step, detail: matches.first.map { L("Match: %@", L($0.title)) } ?? L("No known pattern matched"))
            let scamList = matches.prefix(2).map { scam -> [String: Any] in
                ["title": scam.title, "how_it_works": scam.howItWorks, "red_flags": scam.redFlags, "what_to_do": scam.whatToDo]
            }
            return ToolOutput(result: ["matches": scamList,
                                       "emergency_number": DelhiData.emergencyNumber,
                                       "tourism_helpline": DelhiData.tourismHelplineDisplay])

        case "find_nearby":
            let raw = args["category"] as? String ?? "any"
            let category = SpotCategory(rawValue: raw)
            let step = begin("mappin.and.ellipse", L("Finding verified places"), category?.title ?? L("All categories"))
            await pause(250)
            let spots = DelhiData.spots
                .filter { category == nil || $0.category == category }
                .sorted { location.distanceKm(to: $0.coordinate) < location.distanceKm(to: $1.coordinate) }
                .prefix(6)
            finish(step, detail: spots.prefix(3).map { L($0.name) }.joined(separator: ", "))
            let places = spots.map { spot -> [String: Any] in
                ["name": spot.name, "about": spot.blurb, "tip": spot.tip,
                 "approx_km": (location.distanceKm(to: spot.coordinate) * 10).rounded() / 10]
            }
            return ToolOutput(result: ["places": places])

        case "convert_currency":
            let amount = numberValue(args["amount_inr"]) ?? 0
            let code = app.persona.homeCurrency
            let step = begin("dollarsign.arrow.circlepath", L("Converting to %@", code), inr(amount))
            let converted = app.currency.convert(inr: amount, to: code) ?? 0
            finish(step, detail: "\(inr(amount)) ≈ \(CurrencyService.format(converted, code: code))")
            return ToolOutput(result: ["amount_inr": amount, "currency": code,
                                       "converted": (converted * 100).rounded() / 100,
                                       "rates": app.currency.isLive ? "live ECB reference" : "indicative"])

        case "report_verdict":
            let verdict = PriceVerdict(item: args["item"] as? String ?? L("Item"),
                                       fairLowINR: numberValue(args["fair_low_inr"]) ?? 0,
                                       fairHighINR: numberValue(args["fair_high_inr"]) ?? 0,
                                       askedINR: numberValue(args["asked_inr"]),
                                       source: args["source"] as? String ?? "Candor reference",
                                       tip: tipPhrase(for: args["source"] as? String ?? ""))
            let step = begin(verdict.verdict.icon, L("Preparing verdict"), L(verdict.item))
            finish(step, detail: "\(verdict.verdict.title) · \(L("fair %@", verdict.rangeText))")
            return ToolOutput(result: ["shown_to_user": true, "verdict": verdict.verdict.title], verdict: verdict)

        default:
            return ToolOutput(result: ["error": "Unknown tool \(name)"])
        }
    }

    /// "₹20" for a fixed price, "₹10–₹25" for a range.
    private static func range(_ reference: ReferencePrice) -> String {
        reference.low == reference.high ? inr(reference.low) : "\(inr(reference.low))–\(inr(reference.high))"
    }

    private func tipPhrase(for source: String) -> Phrase? {
        let s = source.lowercased()
        if s.contains("mrp") { return DelhiData.mrpPhrase }
        if s.contains("fare") || s.contains("meter") { return DelhiData.meterPhrase }
        return DelhiData.reducePhrase
    }

    // MARK: Offline agent (no API key)
    //
    // Answers are written in the traveller's language through `L(…)`. Understanding typed
    // questions is keyword matching on English, so ready-made prompts arrive as their English original.

    private enum Intent: String {
        case photo = "Price check from photo"
        case ride = "Ride fare check"
        case scam = "Scam check"
        case price = "Price check"
        case plan = "Day plan"
        case translate = "Phrase help"
        case convert = "Currency conversion"
        case general = "General help"
    }

    private func detectIntent(_ text: String, hasImage: Bool) -> Intent {
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if hasImage { return .photo }
        if has(["scam", "closed", "fake", "gem", "bracelet", "tourist office", "cheat", "commission", "burned", "cancelled", "free gift", "suspicious"]) { return .scam }
        if has(["auto", "taxi", "cab", "ride", "fare", "uber", "driver", "tuk"]) { return .ride }
        if has(["convert", "my currency", "exchange", "in dollars", "in euros"]) { return .convert }
        if has(["translate", "how do i say", "in hindi", "say in"]) { return .translate }
        if has(["plan", "itinerary", "what should i do", "what to do", "visit", "see today", "day in"]) { return .plan }
        if has(["price", "cost", "how much", "₹", "rs", "rupee", "menu", "charge", "pay"]) || !DelhiData.lookup(text).isEmpty { return .price }
        return .general
    }

    private func firstNumber(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for i in 1..<max(match.numberOfRanges, 1) {
            let range = match.range(at: i)
            if range.location != NSNotFound { return Double(ns.substring(with: range)) }
        }
        return nil
    }

    private func distanceIn(_ text: String) -> Double? {
        firstNumber(#"(\d+(?:\.\d+)?)\s*(?:km|kilomet)"#, in: text)
    }

    private func priceIn(_ text: String) -> Double? {
        firstNumber(#"(?:₹|rs\.?|inr)\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:₹|rs\b|rupee|inr)"#, in: text)
            ?? firstNumber(#"\b(\d+(?:\.\d+)?)\b(?!\s*(?:km|kilomet|min|hour|day|person|people|ml|l\b|litre|liter))"#, in: text)
    }

    private func runOffline(prompt: String, image: UIImage?) async -> AgentResult {
        let text = prompt.lowercased()
        let planning = begin("brain.head.profile", L("Planning"), L("On-device agent (no Gemini key)"))
        await pause()
        let intent = detectIntent(text, hasImage: image != nil)
        finish(planning, detail: L("Intent: %@", L(intent.rawValue)))

        switch intent {
        case .photo: return await offlinePhoto(text)
        case .ride: return await offlineRide(text)
        case .scam: return await offlineScam(prompt)
        case .price: return await offlinePrice(text)
        case .plan: return await offlinePlan()
        case .translate: return await offlineTranslate(text)
        case .convert: return await offlineConvert(text)
        case .general: return offlineGeneral()
        }
    }

    private func offlinePhoto(_ text: String) async -> AgentResult {
        let read = begin("eye", L("Reading your photo"), L("Demo vision (add a Gemini key for real recognition)"))
        await pause(700)
        let reference = DelhiData.lookup(text).first ?? DelhiData.prices[0]
        finish(read, detail: L("Detected (demo): %@", L(reference.item)))
        _ = await execute("lookup_price", ["query": reference.keywords.first ?? reference.item])
        let asked = priceIn(text)
        if let asked { _ = await execute("convert_currency", ["amount_inr": asked]) }
        let output = await execute("report_verdict", ["item": reference.item, "fair_low_inr": reference.low,
                                                      "fair_high_inr": reference.high, "asked_inr": asked as Any,
                                                      "source": reference.source])
        var answer = L("**%1$@** should cost **%2$@** (%3$@).", L(reference.item), Self.range(reference), app.homeAmount(reference.high))
        answer += "\n" + L(reference.note)
        if asked == nil { answer += "\n\n" + L("Tell me what you're being asked to pay and I'll judge it.") }
        answer += "\n\n" + L("_Demo mode: photo recognition needs a Gemini API key (Me → AI settings)._")
        return AgentResult(text: answer, verdict: output.verdict)
    }

    private func offlineRide(_ text: String) async -> AgentResult {
        let mode: RideMode = (text.contains("taxi") || text.contains("cab") || text.contains("uber"))
            ? (text.contains(" ac") || text.contains("a/c") ? .taxiAC : .taxi)
            : .auto
        let night = text.contains("night") || FareChart.isNight()
        var km = distanceIn(text)
        var destinationName = L("your destination")

        if km == nil {
            let destination = DelhiData.spot(matching: text)?.name ?? destinationPhrase(in: text)
            if let destination {
                let output = await execute("route_distance", ["destination": destination])
                km = numberValue(output.result["distance_km"])
                destinationName = output.result["destination"] as? String ?? destination
            }
        }
        guard let km else {
            // The example stays in English: offline, typed questions are matched on English keywords.
            return AgentResult(text: L("Where are you going? Try \"%@\" or give the distance in km.", "auto to India Gate, driver wants ₹300"), verdict: nil)
        }

        let fareOutput = await execute("estimate_fare", ["mode": mode.rawValue == "taxiAC" ? "taxi_ac" : mode.rawValue,
                                                        "distance_km": km, "night": night])
        let fare = numberValue(fareOutput.result["metered_fare_inr"]) ?? 0
        let asked = priceIn(text.replacingOccurrences(of: "\(Int(km)) km", with: ""))
        _ = await execute("convert_currency", ["amount_inr": fare])
        let verdictOutput = await execute("report_verdict", ["item": L("%1$@ to %2$@", mode.title, L(destinationName)),
                                                             "fair_low_inr": fare, "fair_high_inr": (fare * 1.2).rounded(),
                                                             "asked_inr": asked as Any, "source": FareChart.source])

        var answer = L("The metered %1$@ fare for **%2$@ km** is about **%3$@** (%4$@).",
                       mode.title, km.formatted(.number.precision(.fractionLength(1))), inr(fare), app.homeAmount(fare))
        answer += "\n\n"
        if let asked, let v = verdictOutput.verdict {
            switch v.verdict {
            case .fair, .info:
                answer += L("%@ is reasonable. Go ahead.", inr(asked))
            case .high:
                answer += L("%1$@ is a little high. Offer around %2$@ or ask for the meter.", inr(asked), inr(fare))
            case .overcharge:
                answer += L("%1$@ is an overcharge (+%2$@%). Say **\"Meter se chaliye\"**, or use a prepaid booth or app cab.",
                            inr(asked), v.overPercent ?? 0)
            }
        } else {
            answer += L("Ask for the meter: **\"Meter se chaliye\"**.")
        }
        return AgentResult(text: answer, verdict: verdictOutput.verdict)
    }

    private func destinationPhrase(in text: String) -> String? {
        guard let range = text.range(of: " to ") else { return nil }
        let rest = text[range.upperBound...]
        let stopWords = [",", ".", " for ", " driver", " he ", " she ", " they ", " wants", " asking", " is ", " costs", " quoted", "₹", " rs"]
        var end = rest.endIndex
        for word in stopWords {
            if let r = rest.range(of: word), r.lowerBound < end { end = r.lowerBound }
        }
        let destination = rest[..<end].trimmingCharacters(in: .whitespaces)
        return destination.isEmpty ? nil : destination
    }

    private func offlineScam(_ prompt: String) async -> AgentResult {
        let output = await execute("check_scam", ["situation": prompt])
        let matches = DelhiData.matchScams(prompt)
        guard let scam = matches.first else {
            let advice: [String] = [
                L("I don't recognise this as a known scam, but trust your instincts:"),
                L("• Don't hand over money, cards or your passport under pressure."),
                L("• Move to a busy, official place (station counter, hotel lobby, police booth)."),
                L("• Emergency: **%1$@**. Tourist helpline: **%2$@**.", DelhiData.emergencyNumber, DelhiData.tourismHelplineDisplay)
            ]
            return AgentResult(text: advice.joined(separator: "\n"), verdict: nil)
        }
        _ = output
        let flags: [String] = scam.redFlags.map { "• \(L($0))" }
        let lines: [String] = [
            L("This looks like **%@**.", L(scam.title)),
            L(scam.howItWorks),
            "",
            "**\(L("Red flags"))**",
            flags.joined(separator: "\n"),
            "",
            "**\(L("What to do")):** \(L(scam.whatToDo))"
        ]
        return AgentResult(text: lines.joined(separator: "\n"), verdict: nil)
    }

    private func offlinePrice(_ text: String) async -> AgentResult {
        let output = await execute("lookup_price", ["query": text])
        guard output.result["found"] as? Bool == true, let reference = DelhiData.lookup(text).first else {
            return AgentResult(text: L("I don't have a reference price for that yet. In bargaining markets, open around half of the first quote and walk away politely if it doesn't move. Packaged goods are never above their printed MRP."), verdict: nil)
        }
        let asked = priceIn(text)
        _ = await execute("convert_currency", ["amount_inr": asked ?? reference.high])
        let verdictOutput = await execute("report_verdict", ["item": reference.item, "fair_low_inr": reference.low,
                                                             "fair_high_inr": reference.high, "asked_inr": asked as Any,
                                                             "source": reference.source])
        var answer = L("**%1$@** usually costs **%2$@** per %3$@ (%4$@).",
                       L(reference.item), verdictOutput.verdict?.rangeText ?? inr(reference.high),
                       L(reference.unit), app.homeAmount(reference.high))
        answer += "\n" + L(reference.note)
        if let v = verdictOutput.verdict, asked != nil, v.verdict == .overcharge || v.verdict == .high {
            let judgement = v.verdict == .overcharge ? L("That's an overcharge.") : L("That's a bit high.")
            let suggestion = L("Try: **\"%@\"**", v.tip?.roman ?? "Thoda kam kijiye.")
            answer += "\n\n\(judgement) \(suggestion)"
        }
        return AgentResult(text: answer, verdict: verdictOutput.verdict)
    }

    private func offlinePlan() async -> AgentResult {
        let output = await execute("find_nearby", ["category": "any"])
        _ = output
        let sights = DelhiData.spots.filter { $0.category == .sight }
        let markets = DelhiData.spots.filter { $0.category == .market }
        let days = max(1, min(app.trip?.plannedDayCount ?? app.persona.tripDays, 3))
        var lines: [String] = []
        for day in 0..<days {
            let morning = sights[(day * 2) % sights.count]
            let afternoon = sights[(day * 2 + 1) % sights.count]
            let evening = markets[day % markets.count]
            let dayPlan: [String] = [
                "**\(L("Day %@", day + 1))**",
                "• \(L("Morning: %@.", L(morning.name))) \(L(morning.tip))",
                "• \(L("Afternoon: %@.", L(afternoon.name)))",
                "• \(L("Evening: %@.", L(evening.name))) \(L(evening.tip))"
            ]
            lines.append(dayPlan.joined(separator: "\n"))
        }
        let routeStep = begin("map.fill", L("Ordering stops"), "\(L("Days: %@", days)) · \(app.persona.travelStyle.title)")
        await pause(300)
        finish(routeStep, detail: L("Grouped by area to cut ride costs"))
        let closing = L("Ask me \"%@\" to check any ride on the way.", "auto from Red Fort to Chandni Chowk")
        return AgentResult(text: lines.joined(separator: "\n\n") + "\n\n" + closing, verdict: nil)
    }

    private func offlineTranslate(_ text: String) async -> AgentResult {
        let step = begin("character.bubble.fill", L("Finding phrase"), L("Offline phrasebook"))
        await pause(300)
        let match = DelhiData.phrases.first { phrase in
            phrase.english.lowercased().split(separator: " ").filter { $0.count > 3 }.contains { text.contains($0) }
        }
        finish(step, detail: match.map { L($0.english) } ?? L("No close match"))
        if let match {
            let hint = L("Open **Phrases** to hear it spoken.")
            return AgentResult(text: "**\(match.roman)**\n\(match.hindi)\n\n“\(L(match.english))”\n\(hint)", verdict: nil)
        }
        return AgentResult(text: L("Open **Phrases** for ready-made lines with audio. Translating your own words needs a Gemini key."), verdict: nil)
    }

    private func offlineConvert(_ text: String) async -> AgentResult {
        let amount = priceIn(text) ?? 100
        let output = await execute("convert_currency", ["amount_inr": amount])
        let converted = numberValue(output.result["converted"]) ?? 0
        let home = CurrencyService.format(converted, code: app.persona.homeCurrency)
        let answer = app.currency.isLive
            ? L("%1$@ ≈ **%2$@** at today's reference rate.", inr(amount), home)
            : L("%1$@ ≈ **%2$@** at an indicative rate.", inr(amount), home)
        return AgentResult(text: answer, verdict: nil)
    }

    private func offlineGeneral() -> AgentResult {
        var lines: [String] = [
            L("I'm Candor, your fair-price travel agent. Try:"),
            "• \"Auto to India Gate, driver wants ₹300\"",
            "• \"Is ₹40 fair for a 1 litre water bottle?\"",
            "• \"A man says my hotel is closed\"",
            "• \"Plan my day in Delhi\"",
            L("Or attach a photo of a price tag, menu or bill.")
        ]
        if Localizer.shared.language != "en" {
            // Be upfront: without Gemini, typed questions are matched on English keywords.
            lines.append("")
            lines.append(L("Without a Gemini key I only understand typed questions in English, like the examples above. The Ride fare screen, the list of known scams and the phrasebook work in your language."))
        }
        return AgentResult(text: lines.joined(separator: "\n"), verdict: nil)
    }
}
