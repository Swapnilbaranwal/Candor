import SwiftUI
import CoreLocation

/// Chat state for the Agent tab. Every run goes through `AgentEngine`, which
/// streams visible steps (tool calls) back to the UI.
@Observable
final class CandorAgent {
    var messages: [ChatMessage] = []
    var isWorking = false

    private let app: AppState
    private let engine: AgentEngine

    init(app: AppState, location: LocationService) {
        self.app = app
        self.engine = AgentEngine(app: app, location: location)
    }

    var toolCount: Int { AgentEngine.toolNames.count }

    func send(_ text: String, image: UIImage? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil, !isWorking else { return }
        isWorking = true

        let history = messages.suffix(8).compactMap { message -> (role: String, text: String)? in
            message.text.isEmpty ? nil : (message.role == .user ? "user" : "model", message.text)
        }

        messages.append(ChatMessage(role: .user, text: trimmed, image: image))
        let reply = ChatMessage(role: .agent, text: "", isWorking: true)
        let replyID = reply.id
        messages.append(reply)

        let prompt = trimmed.isEmpty ? "What is in this photo, and is the price fair?" : trimmed
        let result = await engine.run(prompt: prompt, image: image, history: history) { [weak self] step in
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

    init(app: AppState, location: LocationService) {
        self.app = app
        self.location = location
    }

    func run(prompt: String,
             image: UIImage?,
             history: [(role: String, text: String)],
             onStep: @escaping (AgentStep) -> Void) async -> AgentResult {
        self.onStep = onStep
        if app.hasGemini {
            do {
                return try await runGemini(prompt: prompt, image: image, history: history)
            } catch {
                var step = AgentStep(icon: "wifi.exclamationmark", title: "Gemini unavailable",
                                     detail: "\(error.localizedDescription) Switching to the offline agent.")
                step.state = .failed
                emit(step)
            }
        }
        return await runOffline(prompt: prompt, image: image)
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

    private var systemPrompt: String {
        let p = app.persona
        let interests = p.interests.isEmpty ? "general sightseeing" : p.interests.joined(separator: ", ")
        return """
        You are Candor, a travel agent inside an iPhone app for foreign visitors in India. The current pilot city is Delhi.
        Traveller: \(p.name.isEmpty ? "unnamed" : p.name). Language: \(p.englishLanguageName). Home currency: \(p.homeCurrency). \
        Style: \(p.travelStyle.title). Interests: \(interests). Trip length: \(p.tripDays) days. \
        Local time: \(Date.now.formatted(date: .abbreviated, time: .shortened)). Measuring from: \(location.originName).

        Rules:
        - Always reply in \(p.englishLanguageName). Be warm, concise and practical; prefer short bullet points.
        - Never invent prices. Ground every price in a tool result (lookup_price, estimate_fare) or in a printed MRP you can clearly read in a photo. If there is no data, say so and give bargaining guidance instead.
        - On packaged goods in India the printed MRP is the legal maximum retail price, including taxes.
        - For rides: call route_distance for the destination, then estimate_fare.
        - Whenever you judge a specific price, call report_verdict exactly once with the fair range in INR so the app can show a verdict card.
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
            let read = begin("eye", "Reading your photo", "Gemini vision · \(app.geminiModel)")
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": data.base64EncodedString()]])
            finish(read, detail: "Photo attached (\(data.count / 1024) KB)")
        }
        contents.append(["role": "user", "parts": parts])

        var verdict: PriceVerdict?
        var thinking = begin("brain.head.profile", "Planning", "Gemini · \(app.geminiModel)")

        for _ in 0..<6 {
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": contents,
                "tools": [["functionDeclarations": toolDeclarations]]
            ]
            let response = try await client.generate(body)
            guard let content = GeminiClient.firstContent(response) else { throw GeminiError.emptyResponse }
            contents.append(content)

            let responseParts = content["parts"] as? [[String: Any]] ?? []
            let calls = responseParts.compactMap { $0["functionCall"] as? [String: Any] }

            if calls.isEmpty {
                finish(thinking, detail: "Answer ready")
                let text = GeminiClient.text(of: content)
                return AgentResult(text: text.isEmpty ? "Done. See the result above." : text, verdict: verdict)
            }

            finish(thinking, detail: "Calling \(calls.count) tool\(calls.count == 1 ? "" : "s")")
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
            thinking = begin("brain.head.profile", "Reasoning over results", "Gemini · \(app.geminiModel)")
        }

        finish(thinking, detail: "Stopped after 6 rounds")
        return AgentResult(text: "I gathered the details above but couldn't finish the answer. Please try rephrasing.", verdict: verdict)
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
            let step = begin("tag.fill", "Checking price reference", query)
            await pause(250)
            let matches = DelhiData.lookup(query)
            guard let top = matches.first else {
                finish(step, detail: "No reference for \"\(query)\"")
                return ToolOutput(result: ["found": false,
                                           "guidance": "No reference price. In bargaining markets, open around 50–60% of the first quote. MRP items are never negotiable upward."])
            }
            finish(step, detail: "\(top.item): \(top.low == top.high ? inr(top.low) : "\(inr(top.low))–\(inr(top.high))")")
            return ToolOutput(result: ["found": true, "matches": Array(matches.prefix(3)).map { $0.dictionary }])

        case "route_distance":
            let destination = args["destination"] as? String ?? ""
            let step = begin("arrow.triangle.turn.up.right.diamond.fill", "Measuring route", "\(location.originName) → \(destination)")
            if let route = await Routing.distance(to: destination, from: location.origin) {
                finish(step, detail: "\(route.name) · \(route.km.formatted(.number.precision(.fractionLength(1)))) km by road")
                return ToolOutput(result: ["destination": route.name, "distance_km": (route.km * 10).rounded() / 10, "from": location.originName])
            }
            finish(step, detail: "Couldn't find \"\(destination)\"", failed: true)
            return ToolOutput(result: ["error": "Destination not found. Ask the traveller for a nearby landmark."])

        case "estimate_fare":
            let mode = RideMode(apiName: args["mode"] as? String ?? "auto")
            let km = max(0, numberValue(args["distance_km"]) ?? 0)
            let night = (args["night"] as? Bool) ?? FareChart.isNight()
            let step = begin("gauge.with.needle.fill", "Applying Delhi fare chart", "\(mode.title) · \(km.formatted(.number.precision(.fractionLength(1)))) km")
            await pause(250)
            let fare = mode.fare(km: km, night: night)
            finish(step, detail: "Metered fare ≈ \(inr(fare))\(night ? " (night)" : "")")
            return ToolOutput(result: ["mode": mode.title,
                                       "distance_km": km,
                                       "metered_fare_inr": fare,
                                       "fair_upper_inr": (fare * 1.2).rounded(),
                                       "night_rate_applied": night,
                                       "rule": mode.ruleText,
                                       "source": FareChart.source])

        case "check_scam":
            let situation = args["situation"] as? String ?? ""
            let step = begin("shield.lefthalf.filled", "Scanning scam radar", "\(DelhiData.scams.count) known patterns")
            await pause(300)
            let matches = DelhiData.matchScams(situation)
            finish(step, detail: matches.first.map { "Match: \($0.title)" } ?? "No known pattern matched")
            let scamList = matches.prefix(2).map { scam -> [String: Any] in
                ["title": scam.title, "how_it_works": scam.howItWorks, "red_flags": scam.redFlags, "what_to_do": scam.whatToDo]
            }
            return ToolOutput(result: ["matches": scamList,
                                       "emergency_number": DelhiData.emergencyNumber,
                                       "tourism_helpline": DelhiData.tourismHelplineDisplay])

        case "find_nearby":
            let raw = args["category"] as? String ?? "any"
            let category = SpotCategory(rawValue: raw)
            let step = begin("mappin.and.ellipse", "Finding verified places", category?.title ?? "All categories")
            await pause(250)
            let spots = DelhiData.spots
                .filter { category == nil || $0.category == category }
                .sorted { location.distanceKm(to: $0.coordinate) < location.distanceKm(to: $1.coordinate) }
                .prefix(6)
            finish(step, detail: spots.prefix(3).map(\.name).joined(separator: ", "))
            let places = spots.map { spot -> [String: Any] in
                ["name": spot.name, "about": spot.blurb, "tip": spot.tip,
                 "approx_km": (location.distanceKm(to: spot.coordinate) * 10).rounded() / 10]
            }
            return ToolOutput(result: ["places": places])

        case "convert_currency":
            let amount = numberValue(args["amount_inr"]) ?? 0
            let code = app.persona.homeCurrency
            let step = begin("dollarsign.arrow.circlepath", "Converting to \(code)", inr(amount))
            let converted = app.currency.convert(inr: amount, to: code) ?? 0
            finish(step, detail: "\(inr(amount)) ≈ \(CurrencyService.format(converted, code: code))")
            return ToolOutput(result: ["amount_inr": amount, "currency": code,
                                       "converted": (converted * 100).rounded() / 100,
                                       "rates": app.currency.isLive ? "live ECB reference" : "indicative"])

        case "report_verdict":
            let verdict = PriceVerdict(item: args["item"] as? String ?? "Item",
                                       fairLowINR: numberValue(args["fair_low_inr"]) ?? 0,
                                       fairHighINR: numberValue(args["fair_high_inr"]) ?? 0,
                                       askedINR: numberValue(args["asked_inr"]),
                                       source: args["source"] as? String ?? "Candor reference",
                                       tip: tipPhrase(for: args["source"] as? String ?? ""))
            let step = begin(verdict.verdict.icon, "Preparing verdict", verdict.item)
            finish(step, detail: "\(verdict.verdict.title) · fair \(verdict.rangeText)")
            return ToolOutput(result: ["shown_to_user": true, "verdict": verdict.verdict.title], verdict: verdict)

        default:
            return ToolOutput(result: ["error": "Unknown tool \(name)"])
        }
    }

    private func tipPhrase(for source: String) -> Phrase? {
        let s = source.lowercased()
        if s.contains("mrp") { return DelhiData.mrpPhrase }
        if s.contains("fare") || s.contains("meter") { return DelhiData.meterPhrase }
        return DelhiData.reducePhrase
    }

    // MARK: Offline agent (no API key)

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
        let planning = begin("brain.head.profile", "Planning", "On-device agent (no Gemini key)")
        await pause()
        let intent = detectIntent(text, hasImage: image != nil)
        finish(planning, detail: "Intent: \(intent.rawValue)")

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
        let read = begin("eye", "Reading your photo", "Demo vision (add a Gemini key for real recognition)")
        await pause(700)
        let reference = DelhiData.lookup(text).first ?? DelhiData.prices[0]
        finish(read, detail: "Detected (demo): \(reference.item)")
        _ = await execute("lookup_price", ["query": reference.keywords.first ?? reference.item])
        let asked = priceIn(text)
        if let asked { _ = await execute("convert_currency", ["amount_inr": asked]) }
        let output = await execute("report_verdict", ["item": reference.item, "fair_low_inr": reference.low,
                                                      "fair_high_inr": reference.high, "asked_inr": asked as Any,
                                                      "source": reference.source])
        var answer = "**\(reference.item)** should cost **\(reference.low == reference.high ? inr(reference.low) : "\(inr(reference.low))–\(inr(reference.high))")** (\(app.homeAmount(reference.high))).\n\(reference.note)"
        if asked == nil { answer += "\n\nTell me what you're being asked to pay and I'll judge it." }
        answer += "\n\n_Demo mode: photo recognition needs a Gemini API key (Me → AI settings)._"
        return AgentResult(text: answer, verdict: output.verdict)
    }

    private func offlineRide(_ text: String) async -> AgentResult {
        let mode: RideMode = (text.contains("taxi") || text.contains("cab") || text.contains("uber"))
            ? (text.contains(" ac") || text.contains("a/c") ? .taxiAC : .taxi)
            : .auto
        let night = text.contains("night") || FareChart.isNight()
        var km = distanceIn(text)
        var destinationName = "your destination"

        if km == nil {
            let destination = DelhiData.spot(matching: text)?.name ?? destinationPhrase(in: text)
            if let destination {
                let output = await execute("route_distance", ["destination": destination])
                km = numberValue(output.result["distance_km"])
                destinationName = output.result["destination"] as? String ?? destination
            }
        }
        guard let km else {
            return AgentResult(text: "Where are you going? Try \"auto to India Gate, driver wants ₹300\" or give the distance in km.", verdict: nil)
        }

        let fareOutput = await execute("estimate_fare", ["mode": mode.rawValue == "taxiAC" ? "taxi_ac" : mode.rawValue,
                                                        "distance_km": km, "night": night])
        let fare = numberValue(fareOutput.result["metered_fare_inr"]) ?? 0
        let asked = priceIn(text.replacingOccurrences(of: "\(Int(km)) km", with: ""))
        _ = await execute("convert_currency", ["amount_inr": fare])
        let verdictOutput = await execute("report_verdict", ["item": "\(mode.title) to \(destinationName)",
                                                             "fair_low_inr": fare, "fair_high_inr": (fare * 1.2).rounded(),
                                                             "asked_inr": asked as Any, "source": FareChart.source])

        var answer = "The metered \(mode.title.lowercased()) fare for **\(km.formatted(.number.precision(.fractionLength(1)))) km** is about **\(inr(fare))** (\(app.homeAmount(fare)))."
        if let asked, let v = verdictOutput.verdict {
            switch v.verdict {
            case .fair, .info: answer += "\n\n\(inr(asked)) is reasonable. Go ahead."
            case .high: answer += "\n\n\(inr(asked)) is a little high. Offer around \(inr(fare)) or ask for the meter."
            case .overcharge: answer += "\n\n\(inr(asked)) is an overcharge (+\(v.overPercent ?? 0)%). Say **\"Meter se chaliye\"**, or use a prepaid booth or app cab."
            }
        } else {
            answer += "\n\nAsk for the meter: **\"Meter se chaliye\"**."
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
            return AgentResult(text: """
            I don't recognise this as a known scam, but trust your instincts:
            • Don't hand over money, cards or your passport under pressure.
            • Move to a busy, official place (station counter, hotel lobby, police booth).
            • Emergency: **\(DelhiData.emergencyNumber)**. Tourist helpline: **\(DelhiData.tourismHelplineDisplay)**.
            """, verdict: nil)
        }
        _ = output
        let flags = scam.redFlags.map { "• \($0)" }.joined(separator: "\n")
        return AgentResult(text: """
        This looks like **\(scam.title)**.
        \(scam.howItWorks)

        **Red flags**
        \(flags)

        **What to do:** \(scam.whatToDo)
        """, verdict: nil)
    }

    private func offlinePrice(_ text: String) async -> AgentResult {
        let output = await execute("lookup_price", ["query": text])
        guard output.result["found"] as? Bool == true, let reference = DelhiData.lookup(text).first else {
            return AgentResult(text: "I don't have a reference price for that yet. In bargaining markets, open around half of the first quote and walk away politely if it doesn't move. Packaged goods are never above their printed MRP.", verdict: nil)
        }
        let asked = priceIn(text)
        _ = await execute("convert_currency", ["amount_inr": asked ?? reference.high])
        let verdictOutput = await execute("report_verdict", ["item": reference.item, "fair_low_inr": reference.low,
                                                             "fair_high_inr": reference.high, "asked_inr": asked as Any,
                                                             "source": reference.source])
        var answer = "**\(reference.item)** usually costs **\(verdictOutput.verdict?.rangeText ?? inr(reference.high))** per \(reference.unit) (\(app.homeAmount(reference.high)))."
        answer += "\n\(reference.note)"
        if let v = verdictOutput.verdict, asked != nil, v.verdict == .overcharge || v.verdict == .high {
            answer += "\n\nThat's \(v.verdict == .overcharge ? "an overcharge" : "a bit high"). Try: **\"\(v.tip?.roman ?? "Thoda kam kijiye.")\"**"
        }
        return AgentResult(text: answer, verdict: verdictOutput.verdict)
    }

    private func offlinePlan() async -> AgentResult {
        let output = await execute("find_nearby", ["category": "any"])
        _ = output
        let sights = DelhiData.spots.filter { $0.category == .sight }
        let markets = DelhiData.spots.filter { $0.category == .market }
        let days = max(1, min(app.persona.tripDays, 3))
        var lines: [String] = []
        for day in 0..<days {
            let morning = sights[(day * 2) % sights.count]
            let afternoon = sights[(day * 2 + 1) % sights.count]
            let evening = markets[day % markets.count]
            lines.append("**Day \(day + 1)**\n• Morning: \(morning.name). \(morning.tip)\n• Afternoon: \(afternoon.name)\n• Evening: \(evening.name). \(evening.tip)")
        }
        let routeStep = begin("map.fill", "Ordering stops", "\(days) day\(days == 1 ? "" : "s") · \(app.persona.travelStyle.title)")
        await pause(300)
        finish(routeStep, detail: "Grouped by area to cut ride costs")
        return AgentResult(text: lines.joined(separator: "\n\n") + "\n\nAsk me \"auto from Red Fort to Chandni Chowk\" to check any ride on the way.", verdict: nil)
    }

    private func offlineTranslate(_ text: String) async -> AgentResult {
        let step = begin("character.bubble.fill", "Finding phrase", "Offline phrasebook")
        await pause(300)
        let match = DelhiData.phrases.first { phrase in
            phrase.english.lowercased().split(separator: " ").filter { $0.count > 3 }.contains { text.contains($0) }
        }
        finish(step, detail: match?.english ?? "No close match")
        if let match {
            return AgentResult(text: "**\(match.roman)**\n\(match.hindi)\n\n“\(match.english)”. Open **Interpreter** to hear it spoken.", verdict: nil)
        }
        return AgentResult(text: "Open **Interpreter** from Home for ready-made phrases with audio. Free-text translation needs a Gemini key.", verdict: nil)
    }

    private func offlineConvert(_ text: String) async -> AgentResult {
        let amount = priceIn(text) ?? 100
        let output = await execute("convert_currency", ["amount_inr": amount])
        let converted = numberValue(output.result["converted"]) ?? 0
        return AgentResult(text: "\(inr(amount)) ≈ **\(CurrencyService.format(converted, code: app.persona.homeCurrency))** at \(app.currency.isLive ? "today's reference rate" : "an indicative rate").", verdict: nil)
    }

    private func offlineGeneral() -> AgentResult {
        AgentResult(text: """
        I'm Candor, your fair-price travel agent. Try:
        • "Auto to India Gate, driver wants ₹300"
        • "Is ₹40 fair for a 1 litre water bottle?"
        • "A man says my hotel is closed"
        • "Plan my day in Delhi"
        Or attach a photo of a price tag, menu or bill.
        """, verdict: nil)
    }
}
