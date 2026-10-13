import SwiftUI
import CoreLocation

// MARK: - Trip

/// A journey: one or more cities in order, who's travelling, and (once planned) the days.
/// Saved as JSON in UserDefaults by `AppState`.
struct Trip: Codable, Equatable {
    enum Source: String, Codable {
        /// Built by the traveller, place by place.
        case own
        /// Suggested by Candor (Gemini or the on-device planner).
        case candor
    }

    var source: Source
    /// First day of the trip (the first city's arrival).
    var startDate: Date
    /// Planned days, one per date from `startDate`. Empty until the traveller plans.
    var days: [TripDay]
    /// The cities in visiting order, with their dates and stays.
    var cities: [CityStay] = []
    var party: TravelParty?
    /// Head count for a family or group (solo and couple are implied).
    var travellers: Int?
    /// What Gemini found on the web for these dates: events, food, markets, weather, tips.
    var insights: [TripInsight] = []

    init(source: Source, startDate: Date, days: [TripDay], cities: [CityStay] = [],
         party: TravelParty? = nil, travellers: Int? = nil) {
        self.source = source
        self.startDate = startDate
        self.days = days
        self.cities = cities
        self.party = party
        self.travellers = travellers
    }

    /// A trip with its cities set and no days planned yet.
    init(cities: [CityStay], party: TravelParty?, travellers: Int?) {
        self.init(source: .own, startDate: cities.first?.arrival ?? Calendar.current.startOfDay(for: .now),
                  days: [], cities: cities, party: party, travellers: travellers)
    }

    // Trips saved before cities existed have no `cities`, `party` or `travellers`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        startDate = try c.decode(Date.self, forKey: .startDate)
        days = try c.decode([TripDay].self, forKey: .days)
        cities = try c.decodeIfPresent([CityStay].self, forKey: .cities) ?? []
        party = try c.decodeIfPresent(TravelParty.self, forKey: .party)
        travellers = try c.decodeIfPresent(Int.self, forKey: .travellers)
        insights = try c.decodeIfPresent([TripInsight].self, forKey: .insights) ?? []
    }

    /// The day to show first: today's day while the trip is on, else the first or last day.
    var todayIndex: Int {
        guard !days.isEmpty else { return 0 }
        let calendar = Calendar.current
        let offset = calendar.dateComponents([.day],
                                             from: calendar.startOfDay(for: startDate),
                                             to: calendar.startOfDay(for: .now)).day ?? 0
        return min(max(offset, 0), days.count - 1)
    }

    func date(ofDay index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
    }

    var stopCount: Int { days.reduce(0) { $0 + $1.stops.count } }

    /// Days from the first arrival to the last departure, counting both ends.
    var plannedDayCount: Int {
        guard let first = cities.first?.arrival, let last = cities.last?.departure else { return max(days.count, 1) }
        let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return max(span + 1, 1)
    }

    /// The city the traveller is in on `date`: the stay covering it, else the nearest one.
    func cityStay(on date: Date) -> CityStay? {
        let day = Calendar.current.startOfDay(for: date)
        if let covering = cities.last(where: { $0.arrival <= day && day <= $0.departure }) { return covering }
        if let first = cities.first, day < first.arrival { return first }
        return cities.last
    }

    /// The city for planned day `index`.
    func cityStay(ofDay index: Int) -> CityStay? { cityStay(on: date(ofDay: index)) }

    /// "Couple", "Family of 4"; English, for prompting Gemini.
    var partySummary: String {
        guard let party else { return "not given" }
        return party.fixedCount == nil ? "\(party.rawValue) of \(travellers ?? 3)" : party.rawValue
    }
}

/// Something worth knowing for the trip, found on the web when Candor planned it:
/// "Diwali on 20 Oct: markets are packed, book cabs early."
struct TripInsight: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case event, food, market, weather, tip
    }

    var id = UUID()
    /// English city name, matching `CityStay.city.name`.
    var city: String
    var kind: Kind
    var title: String
    var detail: String
    /// "Sat & Sun", "18 Oct, 7 pm", when the item happens on certain days.
    var when: String?
    /// The web page it came from, when Gemini searched.
    var sourceTitle: String?
    var sourceURL: String?
}

/// One city on the trip: when the traveller is there and where they sleep.
struct CityStay: Codable, Equatable, Identifiable {
    var id = UUID()
    var city: City
    var arrival: Date
    var departure: Date
    /// Booked hotel or home. Days in this city start here.
    var stay: Stay?
    /// True when they haven't booked and want Candor to suggest where to stay.
    var wantsStaySuggestions = false

    /// Nights + 1.
    var dayCount: Int {
        max((Calendar.current.dateComponents([.day], from: arrival, to: departure).day ?? 0) + 1, 1)
    }

    /// Where a day here starts: the stay, else the city's central start point, else its centre.
    var dayStart: (coordinate: CLLocationCoordinate2D, name: String) {
        if let stay { return (stay.coordinate, stay.name) }
        if let pack = city.pack { return (pack.defaultStart, L(pack.defaultStartName)) }
        return (city.coordinate, L(city.name))
    }

    /// English, for prompting Gemini.
    var staySummary: String {
        if let stay { return "booked at \(stay.name)" + (stay.address.map { ", \($0)" } ?? "") }
        return wantsStaySuggestions ? "not booked yet; wants suggestions on where to stay" : "not given"
    }
}

struct TripDay: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String?
    var stops: [TripStop] = []

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let names = stops.prefix(2).map { L($0.name) }
        return names.isEmpty ? L("Free day") : names.joined(separator: " · ")
    }
}

struct TripStop: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    /// Set for places from a city pack (`CityPack.spots`); nil for a place found in maps search.
    var spotID: String?
    var name: String
    var latitude: Double
    var longitude: Double
    /// Why Candor suggested it, when Gemini planned the day.
    var note: String?
    var stayMinutes: Int
    /// When the traveller ticked off getting here (the leg before this stop).
    var arrivedAt: Date?
    /// When the traveller ticked off visiting this place.
    var visitedAt: Date?

    var isArrived: Bool { arrivedAt != nil || visitedAt != nil }
    var isVisited: Bool { visitedAt != nil }

    init(spot: Spot, note: String? = nil) {
        spotID = spot.id
        name = spot.name
        latitude = spot.latitude
        longitude = spot.longitude
        self.note = note
        switch spot.category {
        case .sight: stayMinutes = 90
        case .market: stayMinutes = 75
        case .fixedPrice: stayMinutes = 45
        case .transport: stayMinutes = 30
        }
    }

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        stayMinutes = 60
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var spot: Spot? {
        guard let spotID else { return nil }
        return CityPack.all.values.lazy.compactMap { $0.spot(spotID) }.first
    }

    var isAirport: Bool { spotID == "airport" }

    /// A warning when the place is shut on that day.
    func closedNote(on date: Date) -> String? {
        guard let spotID,
              let weekday = CityPack.all.values.lazy.compactMap({ $0.closedWeekday[spotID] }).first else { return nil }
        return Calendar.current.component(.weekday, from: date) == weekday ? L("Closed on Mondays") : nil
    }
}

extension DelhiData {
    /// Weekly closing day by spot id (`Calendar` weekday: 1 = Sunday, 2 = Monday).
    static let closedWeekday: [String: Int] = ["redfort": 2, "lotus": 2, "akshardham": 2]
}

// MARK: - Getting around

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case walk, metro, auto, cab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: L("Walk")
        case .metro: L("Metro")
        case .auto: L("Auto")
        case .cab: L("Cab")
        }
    }

    var icon: String {
        switch self {
        case .walk: "figure.walk"
        case .metro: "tram.fill"
        case .auto: "car.side.fill"
        case .cab: "car.fill"
        }
    }

    var color: Color {
        switch self {
        case .walk: Theme.mint
        case .metro: Theme.indigo
        case .auto: Theme.saffron
        case .cab: Theme.teal
        }
    }
}

/// One way to get from a place to the next.
struct LegOption: Identifiable, Equatable {
    var id: TravelMode { mode }
    let mode: TravelMode
    let minutes: Int
    let fareLow: Double
    let fareHigh: Double
    let summary: String
    let steps: [String]
    let tips: [String]

    var fareText: String {
        if fareHigh <= 0 { return L("Free") }
        return fareLow == fareHigh ? inr(fareLow) : "\(inr(fareLow))–\(inr(fareHigh))"
    }
}

struct Leg: Identifiable, Equatable {
    let id = UUID()
    let from: String
    let to: String
    /// Road distance.
    let km: Double
    let options: [LegOption]
    let best: TravelMode

    var bestOption: LegOption {
        options.first { $0.mode == best } ?? options[0]
    }

    /// Best first, then quickest.
    var sortedOptions: [LegOption] {
        options.sorted { a, b in
            if a.mode == best { return true }
            if b.mode == best { return false }
            return a.minutes < b.minutes
        }
    }
}

/// A day with times: when you leave, how you travel, when you arrive and leave each place.
struct DayPlan {
    struct Entry: Identifiable {
        var id: UUID { stop.id }
        let stop: TripStop
        let leg: Leg
        let arrival: Date
        let departure: Date
    }

    let start: Date
    let startName: String
    let entries: [Entry]

    var travelMinutes: Int { entries.reduce(0) { $0 + $1.leg.bestOption.minutes } }
    var fareLow: Double { entries.reduce(0) { $0 + $1.leg.bestOption.fareLow } }
    var fareHigh: Double { entries.reduce(0) { $0 + $1.leg.bestOption.fareHigh } }
    var end: Date { entries.last?.departure ?? start }

    var fareText: String {
        if fareHigh <= 0 { return L("Free") }
        return fareLow == fareHigh ? inr(fareLow) : "\(inr(fareLow))–\(inr(fareHigh))"
    }
}

/// "45 min", "1 h", "2 h 15 min".
func durationText(_ minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return L("%@ min", rest) }
    if rest == 0 { return L("%@ h", hours) }
    return L("%1$@ h %2$@ min", hours, rest)
}

/// "9:30 AM", in the app's language.
func timeText(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Localizer.shared.locale))
}

extension LocationService {
    /// Where planned day `index` starts: that city's stay or start point. Without a trip, the
    /// traveller's location (or the demo spot).
    func dayStart(trip: Trip?, day index: Int) -> (coordinate: CLLocationCoordinate2D, name: String) {
        guard let cityStay = trip?.cityStay(ofDay: index) else { return (origin, originName) }
        // No hotel set and the traveller is in that city now: start from where they are.
        if cityStay.stay == nil, let here = location?.coordinate, cityStay.city.bounds.contains(here) {
            return (here, L("Your location"))
        }
        return cityStay.dayStart
    }
}
