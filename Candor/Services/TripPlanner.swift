import Foundation
import CoreLocation

/// Plans trip days: picks places for the traveller, times each day, and works out
/// how to get between places by foot, Metro, auto or cab, with fair fares.
enum TripPlanner {
    /// Roads in Indian cities run about a third longer than the straight line.
    private static let roadFactor = 1.35

    // MARK: Timing a day

    static func dayPlan(_ day: TripDay, date: Date, origin: CLLocationCoordinate2D,
                        originName: String, style: TravelStyle, city: City? = .delhi,
                        likesWalking: Bool = false) -> DayPlan {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date) ?? date
        var cursor = start
        var from = origin
        var fromName = originName
        var fromAirport = false
        var entries: [DayPlan.Entry] = []
        for stop in day.stops {
            let leg = leg(from: from, fromName: fromName, fromAirport: fromAirport, to: stop, at: cursor,
                          style: style, city: city, likesWalking: likesWalking)
            let arrival = cursor.addingTimeInterval(Double(leg.bestOption.minutes) * 60)
            let departure = arrival.addingTimeInterval(Double(stop.stayMinutes) * 60)
            entries.append(DayPlan.Entry(stop: stop, leg: leg, arrival: arrival, departure: departure))
            cursor = departure
            from = stop.coordinate
            fromName = stop.name
            fromAirport = stop.isAirport
        }
        return DayPlan(start: start, startName: originName, entries: entries)
    }

    // MARK: Getting from one place to the next

    static func leg(from origin: CLLocationCoordinate2D, fromName: String, fromAirport: Bool = false,
                    to stop: TripStop, at time: Date, style: TravelStyle, city: City? = .delhi,
                    likesWalking: Bool = false) -> Leg {
        // Someone happy to walk gets walking offered, and preferred, for longer hops.
        let walkBonus = likesWalking ? 0.8 : 0
        let straight = DelhiMetro.km(origin, stop.coordinate)
        let road = straight * roadFactor
        let night = FareChart.isNight(time)
        let airport = fromAirport || stop.isAirport
        let place = L(stop.name)
        // Fares come from the city's own chart when Candor has one; elsewhere the same meter
        // rules are only a guide, and the traveller is told so.
        let verifiedFares = city?.pack?.fareSource != nil
        let estimateTip = verifiedFares ? nil : L("Estimate: Candor doesn't have this city's official fare chart yet.")

        var options: [LegOption] = []

        if straight <= 2 + walkBonus {
            options.append(LegOption(
                mode: .walk,
                minutes: max(1, Int((straight / 4.5 * 60).rounded(.up))),
                fareLow: 0, fareHigh: 0,
                summary: L("%@ km on foot", oneDecimal(straight)),
                steps: [L("Walk to %@", place)],
                tips: []))
        }

        if road >= 3, city?.pack?.hasMetro == true,
           let metro = metroOption(from: origin, to: stop, place: place, night: night) {
            options.append(metro)
        }

        if road <= 25 && !airport {
            let fare = RideMode.auto.fare(km: road, night: night)
            options.append(LegOption(
                mode: .auto,
                minutes: Int((road / 18 * 60 + 3).rounded(.up)),
                fareLow: fare, fareHigh: (fare * 1.2).rounded(),
                summary: L("Metered auto, about %@ km", oneDecimal(road)),
                steps: [L("Stop an auto and show the driver \"%@\"", place),
                        L("Ask for the meter before you get in")],
                tips: [L("Say \"Meter se chaliye\": please go by the meter.")] + [estimateTip].compactMap { $0 }))
        }

        let cabLow = RideMode.taxi.fare(km: road, night: night)
        let cabHigh = (RideMode.taxiAC.fare(km: road, night: night) * 1.3).rounded()
        var cabTips = [L("App cabs show the fare before you book. Compare it with this range.")]
        if let estimateTip { cabTips.append(estimateTip) }
        if airport { cabTips.insert(L("At the airport, use the official prepaid taxi counter or the marked app-cab pickup bays."), at: 0) }
        options.append(LegOption(
            mode: .cab,
            minutes: Int((road / 22 * 60 + 6).rounded(.up)),
            fareLow: cabLow, fareHigh: max(cabLow, cabHigh),
            summary: L("Cab, about %@ km", oneDecimal(road)),
            steps: [L("Book an app cab or take a metered taxi to %@", place),
                    L("Check the fare before you confirm")],
            tips: cabTips))

        return Leg(from: fromName, to: stop.name, km: road, options: options,
                   best: best(options, straight: max(straight - walkBonus, 0), road: road, style: style))
    }

    private static func best(_ options: [LegOption], straight: Double, road: Double, style: TravelStyle) -> TravelMode {
        func has(_ mode: TravelMode) -> Bool { options.contains { $0.mode == mode } }
        func minutes(_ mode: TravelMode) -> Int? { options.first { $0.mode == mode }?.minutes }
        switch style {
        case .luxury:
            return has(.walk) && straight <= 0.8 ? .walk : .cab
        case .budget:
            if has(.walk) && straight <= 1.5 { return .walk }
            if has(.metro) { return .metro }
            if has(.auto) { return .auto }
            return .cab
        case .comfort:
            if has(.walk) && straight <= 1.2 { return .walk }
            if let metro = minutes(.metro), let cab = minutes(.cab), metro <= cab + 10 { return .metro }
            if has(.auto) && road <= 8 { return .auto }
            return .cab
        }
    }

    /// Metro when both ends are within 2.5 km of a station: walk or a short auto to the station,
    /// the ride with its changes, then walk or auto to the place.
    private static func metroOption(from origin: CLLocationCoordinate2D, to stop: TripStop,
                                    place: String, night: Bool) -> LegOption? {
        let start = DelhiMetro.nearestStation(to: origin)
        let end = DelhiMetro.nearestStation(to: stop.coordinate)
        guard start.km <= 2.5, end.km <= 2.5,
              let route = DelhiMetro.route(from: start.station, to: end.station) else { return nil }

        var minutes = route.minutes
        var fare = route.fare
        var steps: [String] = []

        func access(_ km: Double, to target: String, station: Bool) {
            if km <= 1.2 {
                minutes += Int((km / 4.5 * 60).rounded(.up))
                steps.append(station ? L("Walk to %@ station", L(target)) : L("Walk to %@", target))
            } else {
                let road = km * roadFactor
                let autoFare = RideMode.auto.fare(km: road, night: night)
                minutes += Int((road / 18 * 60 + 3).rounded(.up))
                fare = (fare.low + autoFare, fare.high + (autoFare * 1.2).rounded())
                steps.append(station ? L("Take a short auto to %@ station", L(target)) : L("Take a short auto to %@", target))
            }
        }

        access(start.km, to: start.station.name, station: true)
        for (index, segment) in route.segments.enumerated() {
            if index == 0 {
                steps.append(L("Ride the %@", segment.line.title))
            } else {
                steps.append(L("Change at %1$@ to the %2$@", L(segment.from.name), segment.line.title))
            }
        }
        steps.append(L("Get off at %@", L(end.station.name)))
        access(end.km, to: place, station: false)

        var tips = [L("Buy a token at the counter or pay with a UPI QR ticket."),
                    L("The first coach is reserved for women."),
                    L("Trains run from about 5:30 am to 11 pm.")]
        if route.usesAirportExpress {
            tips.append(L("The Airport Express has its own gates and tickets."))
        }

        let lines = route.segments.map { $0.line.title }.joined(separator: " → ")
        return LegOption(mode: .metro, minutes: minutes, fareLow: fare.low, fareHigh: fare.high,
                         summary: L("%1$@ · %2$@ to %3$@", lines, L(start.station.name), L(end.station.name)),
                         steps: steps, tips: tips)
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: Suggesting days

    static func score(_ spot: Spot, persona: Persona, pack: CityPack) -> Int {
        var score = spot.category == .sight ? 1 : 0
        for interest in persona.interests where pack.interestSpots[interest]?.contains(spot.id) == true {
            score += 2
        }
        return score
    }

    /// The trip's dates grouped by the city the traveller is in on each one, in order.
    private static func dayGroups(_ trip: Trip) -> [(cityStay: CityStay?, dates: [Date])] {
        var groups: [(cityStay: CityStay?, dates: [Date])] = []
        for index in 0..<trip.plannedDayCount {
            let date = trip.date(ofDay: index)
            let stay = trip.cityStay(on: date)
            if let last = groups.last, last.cityStay?.id == stay?.id {
                groups[groups.count - 1].dates.append(date)
            } else {
                groups.append((stay, [date]))
            }
        }
        return groups
    }

    /// On-device plan for every city with a pack: each day starts from the best place still open,
    /// adds its nearest open neighbours, and is ordered as a chain from where the day starts.
    /// Cities without a pack get empty days for the traveller (or Gemini) to fill.
    static func suggest(persona: Persona, trip: Trip) -> Trip {
        var planned = trip
        planned.source = .candor
        planned.days = dayGroups(trip).flatMap { group -> [TripDay] in
            guard let cityStay = group.cityStay, let pack = cityStay.city.pack else {
                return group.dates.map { _ in TripDay() }
            }
            return suggestDays(persona: persona, pack: pack, dates: group.dates, from: cityStay.dayStart.coordinate)
        }
        return planned
    }

    private static func suggestDays(persona: Persona, pack: CityPack, dates: [Date],
                                    from start: CLLocationCoordinate2D) -> [TripDay] {
        let perDay = persona.travelStyle == .budget ? 4 : 3
        var remaining = pack.spots
            .filter { $0.category != .transport }
            .sorted { score($0, persona: persona, pack: pack) > score($1, persona: persona, pack: pack) }
        var days: [TripDay] = []
        for date in dates {
            let open = remaining.filter { TripStop(spot: $0).closedNote(on: date) == nil }
            guard let anchor = open.first else {
                days.append(TripDay())
                continue
            }
            let neighbours = open.dropFirst()
                .sorted { DelhiMetro.km(anchor.coordinate, $0.coordinate) < DelhiMetro.km(anchor.coordinate, $1.coordinate) }
                .prefix(perDay - 1)
            let picked = [anchor] + neighbours
            remaining.removeAll { spot in picked.contains(spot) }
            days.append(TripDay(stops: ordered(picked, from: start).map { TripStop(spot: $0) }))
        }
        return days
    }

    /// Nearest-neighbour order starting from where the day starts.
    private static func ordered(_ spots: [Spot], from start: CLLocationCoordinate2D) -> [Spot] {
        var left = spots
        var here = start
        var result: [Spot] = []
        while let next = left.min(by: { DelhiMetro.km(here, $0.coordinate) < DelhiMetro.km(here, $1.coordinate) }) {
            result.append(next)
            left.removeAll { $0.id == next.id }
            here = next.coordinate
        }
        return result
    }

    /// Plans with Gemini, city by city, with Google Search grounding so the plan reflects what's
    /// on the web for the traveller's dates. In a verified city Gemini picks from Candor's own
    /// places (every id is checked). In an AI-guide city it names real places, which are then found
    /// in Google Maps; anything it can't find is dropped. Alongside the days it collects what's
    /// worth knowing (events on those dates, dishes and where to eat them, markets and their days,
    /// weather, tips) into `Trip.insights`. Falls back to `suggest` per city.
    /// `progress` gets a short, readable line for each step, for the planning screen.
    static func suggestWithGemini(app: AppState, trip: Trip,
                                  progress: @escaping (String) -> Void = { _ in }) async -> Trip {
        let persona = app.persona
        let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
        var planned = trip
        planned.source = .candor
        var days: [TripDay] = []
        var insights: [TripInsight] = []
        for group in dayGroups(trip) {
            guard let cityStay = group.cityStay else {
                days += group.dates.map { _ in TripDay() }
                continue
            }
            let name = L(cityStay.city.name)
            progress(L("Searching what's on in %@ on your dates", name))
            async let found = cityInsights(client: client, persona: persona, trip: trip,
                                           cityStay: cityStay, dates: group.dates)
            progress(L("Picking places in %@ for your interests", name))
            let fromGemini: [TripDay]?
            if let pack = cityStay.city.pack {
                fromGemini = try? await geminiDays(client: client, persona: persona, trip: trip, cityStay: cityStay,
                                                   pack: pack, dates: group.dates)
            } else {
                progress(L("Finding each place on Google Maps"))
                fromGemini = try? await geminiOpenDays(client: client, persona: persona, trip: trip,
                                                       cityStay: cityStay, dates: group.dates)
            }
            if let fromGemini, fromGemini.contains(where: { !$0.stops.isEmpty }) {
                days += fromGemini
            } else if let pack = cityStay.city.pack {
                days += suggestDays(persona: persona, pack: pack, dates: group.dates, from: cityStay.dayStart.coordinate)
            } else {
                days += group.dates.map { _ in TripDay() }
            }
            progress(L("Collecting food, markets and events in %@", name))
            insights += await found
        }
        planned.days = days
        planned.insights = insights
        return planned
    }

    /// Events, food, markets, weather and tips for one city on the trip's dates, from the web.
    /// Empty when Gemini can't be reached; the plan doesn't depend on it.
    private static func cityInsights(client: GeminiClient, persona: Persona, trip: Trip, cityStay: CityStay,
                                     dates: [Date]) async -> [TripInsight] {
        guard let first = dates.first, let last = dates.last else { return [] }
        let english = Locale(identifier: "en")
        let range = first.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(english))
            + " to " + last.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(english))
        let city = cityStay.city
        let prompt = """
        Search the web for what a visitor to \(city.name), \(city.country) should know for \(range).
        Find, specifically for those dates: festivals, events, concerts or exhibitions; public holidays \
        or closures; the weather to expect and what to wear. Also: must-try local dishes, each with one \
        specific, well-reviewed place to eat it; markets worth visiting with the days they are open or \
        closed; one or two practical tips (transport cards, common scams, etiquette).
        The traveller: \(traveller(persona, trip: trip, cityStay: cityStay))
        Be concrete: real names, dates and places. Skip anything you can't confirm for these dates.
        Write "title", "detail" and "when" in \(persona.englishLanguageName), short.
        Reply only with JSON: {"insights":[{"kind":"event|food|market|weather|tip","title":"<short>",\
        "detail":"<one sentence>","when":"<dates or days, optional>","source":<0-based index of the web result it came from, optional>}]}
        Give 6 to 10 items, events first.
        """
        guard let answer = try? await client.askGrounded(prompt),
              let object = GeminiClient.jsonObject(in: answer.text),
              let raw = object["insights"] as? [[String: Any]] else { return [] }
        return raw.prefix(12).compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            let kind = TripInsight.Kind(rawValue: (item["kind"] as? String ?? "").lowercased()) ?? .tip
            var insight = TripInsight(city: city.name, kind: kind, title: title,
                                      detail: item["detail"] as? String ?? "", when: item["when"] as? String)
            if let index = item["source"] as? Int, answer.sources.indices.contains(index) {
                insight.sourceTitle = answer.sources[index].title
                insight.sourceURL = answer.sources[index].url
            }
            if insight.when?.isEmpty == true { insight.when = nil }
            return insight
        }
    }

    private static func traveller(_ persona: Persona, trip: Trip, cityStay: CityStay) -> String {
        """
        Travel style: \(persona.travelStyle.rawValue). \
        Interests: \(persona.interests.isEmpty ? "general sightseeing" : persona.interests.joined(separator: ", ")). \
        Preferences: \(persona.tasteSummary). \
        Travelling: \(trip.partySummary). Stay: \(cityStay.staySummary).
        """
    }

    private static func dateLines(_ dates: [Date]) -> String {
        dates.enumerated().map { index, date in
            "Day \(index + 1): " + date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "en")))
        }.joined(separator: "\n")
    }

    private static func geminiDays(client: GeminiClient, persona: Persona, trip: Trip, cityStay: CityStay,
                                   pack: CityPack, dates: [Date]) async throws -> [TripDay] {
        let places = pack.spots.filter { $0.category != .transport }
        let list = places.map { spot in
            var line = "- \(spot.id): \(spot.name) (\(spot.category.rawValue)). \(spot.blurb)"
            if pack.closedWeekday[spot.id] == 2 { line += " Closed on Mondays." }
            return line
        }.joined(separator: "\n")
        let prompt = """
        Plan \(dates.count) day(s) in \(cityStay.city.name) for a traveller. \(traveller(persona, trip: trip, cityStay: cityStay))
        Dates:
        \(dateLines(dates))
        Use only these places (by id):
        \(list)
        Put 2 to 4 places on each day, close to each other and in a sensible visiting order. \
        Don't use a place on a day it is closed, and don't repeat places.
        Write "title" and "why" in \(persona.englishLanguageName), short.
        Reply as JSON: {"days":[{"title":"<short day title>","stops":[{"id":"<place id>","why":"<one sentence>"}]}]}
        """
        let rawDays = try await askDays(client: client, prompt: prompt)
        var used = Set<String>()
        var days: [TripDay] = []
        for (index, rawDay) in rawDays.prefix(dates.count).enumerated() {
            let stops = (rawDay["stops"] as? [[String: Any]] ?? []).compactMap { rawStop -> TripStop? in
                guard let id = rawStop["id"] as? String,
                      let spot = places.first(where: { $0.id == id }),
                      !used.contains(id) else { return nil }
                let stop = TripStop(spot: spot, note: rawStop["why"] as? String)
                guard stop.closedNote(on: dates[index]) == nil else { return nil }
                used.insert(id)
                return stop
            }
            days.append(TripDay(title: rawDay["title"] as? String, stops: stops))
        }
        while days.count < dates.count { days.append(TripDay()) }
        return days
    }

    /// AI-guide city: Gemini names places, Google Maps confirms each one and gives its location.
    private static func geminiOpenDays(client: GeminiClient, persona: Persona, trip: Trip, cityStay: CityStay,
                                       dates: [Date]) async throws -> [TripDay] {
        let city = cityStay.city
        let prompt = """
        Plan \(dates.count) day(s) in \(city.name), \(city.country) for a traveller. \(traveller(persona, trip: trip, cityStay: cityStay))
        Dates:
        \(dateLines(dates))
        Put 2 to 4 well-known, real places on each day, close to each other and in a sensible visiting order. \
        Use each place's official name as it appears on Google Maps. Avoid places closed on that weekday. Don't repeat places.
        "minutes" is a sensible time to spend there.
        Write "title" and "why" in \(persona.englishLanguageName), short.
        Reply as JSON: {"days":[{"title":"<short day title>","stops":[{"name":"<place name>","why":"<one sentence>","minutes":90}]}]}
        """
        let rawDays = Array(try await askDays(client: client, prompt: prompt).prefix(dates.count))

        // Find every named place in Google Maps at once, then keep Gemini's order.
        let named: [(day: Int, order: Int, name: String, why: String?, minutes: Int?)] =
            rawDays.enumerated().flatMap { day, rawDay in
                (rawDay["stops"] as? [[String: Any]] ?? []).enumerated().compactMap { order, rawStop in
                    (rawStop["name"] as? String).map { (day, order, $0, rawStop["why"] as? String, rawStop["minutes"] as? Int) }
                }
            }
        let found = await withTaskGroup(of: (Int, GooglePlace?).self) { group in
            for (index, item) in named.enumerated() {
                group.addTask { (index, try? await GooglePlaces.search(item.name, in: city, reachKm: 40).first) }
            }
            var results = [GooglePlace?](repeating: nil, count: named.count)
            for await (index, place) in group { results[index] = place }
            return results
        }

        var days = rawDays.map { TripDay(title: $0["title"] as? String) }
        var used = Set<String>()
        for (index, item) in named.enumerated() {
            guard let place = found[index], !used.contains(place.id) else { continue }
            used.insert(place.id)
            var stop = TripStop(name: place.name, coordinate: place.coordinate)
            stop.note = item.why
            if let minutes = item.minutes { stop.stayMinutes = min(max(minutes, 15), 300) }
            days[item.day].stops.append(stop)
        }
        while days.count < dates.count { days.append(TripDay()) }
        return days
    }

    /// Asks with Google Search grounding (opening days, what's on), then plain JSON if that fails.
    private static func askDays(client: GeminiClient, prompt: String) async throws -> [[String: Any]] {
        let grounded = prompt + "\nCheck opening days and anything special on these dates on the web. Reply only with the JSON."
        if let answer = try? await client.askGrounded(grounded),
           let days = GeminiClient.jsonObject(in: answer.text)?["days"] as? [[String: Any]], !days.isEmpty {
            return days
        }
        let raw = try await client.ask(prompt, json: true)
        return GeminiClient.jsonObject(in: raw)?["days"] as? [[String: Any]] ?? []
    }
}
