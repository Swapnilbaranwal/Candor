import SwiftUI
import CoreLocation

// MARK: - Persona

struct Persona: Codable, Equatable {
    var name = ""
    var phone = ""
    var homeCurrency = Persona.defaultCurrency
    var languageCode = Persona.defaultLanguage
    var travelStyle: TravelStyle = .comfort
    var interests: [String] = []
    var tripDays = 2
    var isComplete = false

    static var defaultLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static var defaultCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return CurrencyOption.all.contains { $0.code == code } ? code : "USD"
    }

    /// Language name shown in the UI, in the device language.
    var languageName: String {
        Locale.current.localizedString(forLanguageCode: languageCode)?.capitalized ?? languageCode
    }

    /// Language name in English, used for prompting Gemini.
    var englishLanguageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? "Traveller"
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "C" : letters.uppercased()
    }
}

enum TravelStyle: String, Codable, CaseIterable, Identifiable {
    case budget, comfort, luxury
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .budget: "backpack.fill"
        case .comfort: "suitcase.rolling.fill"
        case .luxury: "crown.fill"
        }
    }
}

// MARK: - Verdicts

enum Verdict: String, Codable {
    case fair, high, overcharge, info

    static func judge(asked: Double?, high: Double) -> Verdict {
        guard let asked, high > 0 else { return .info }
        if asked <= high * 1.1 { return .fair }
        if asked <= high * 1.6 { return .high }
        return .overcharge
    }

    var title: String {
        switch self {
        case .fair: "Fair price"
        case .high: "A bit high"
        case .overcharge: "Overcharge"
        case .info: "Fair range"
        }
    }

    var icon: String {
        switch self {
        case .fair: "checkmark.seal.fill"
        case .high: "exclamationmark.triangle.fill"
        case .overcharge: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fair: Theme.mint
        case .high: Theme.saffron
        case .overcharge: Theme.rose
        case .info: Theme.teal
        }
    }
}

struct PriceVerdict: Equatable {
    var item: String
    var fairLowINR: Double
    var fairHighINR: Double
    var askedINR: Double?
    var source: String
    var verdict: Verdict
    var tip: Phrase?

    init(item: String, fairLowINR: Double, fairHighINR: Double, askedINR: Double?, source: String, tip: Phrase? = nil) {
        self.item = item
        self.fairLowINR = min(fairLowINR, fairHighINR)
        self.fairHighINR = max(fairLowINR, fairHighINR)
        self.askedINR = askedINR
        self.source = source
        self.verdict = Verdict.judge(asked: askedINR, high: max(fairLowINR, fairHighINR))
        self.tip = tip
    }

    var overPercent: Int? {
        guard let asked = askedINR, fairHighINR > 0, asked > fairHighINR else { return nil }
        return Int(((asked - fairHighINR) / fairHighINR * 100).rounded())
    }

    var rangeText: String {
        fairLowINR == fairHighINR ? inr(fairLowINR) : "\(inr(fairLowINR)) – \(inr(fairHighINR))"
    }
}

enum CheckKind: String, Codable {
    case scan, ride, agent

    var icon: String {
        switch self {
        case .scan: "camera.viewfinder"
        case .ride: "car.fill"
        case .agent: "sparkles"
        }
    }
}

struct PriceCheckRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var title: String
    var kind: CheckKind
    var askedINR: Double?
    var fairLowINR: Double
    var fairHighINR: Double
    var verdict: Verdict

    init(verdict v: PriceVerdict, kind: CheckKind) {
        title = v.item
        self.kind = kind
        askedINR = v.askedINR
        fairLowINR = v.fairLowINR
        fairHighINR = v.fairHighINR
        verdict = v.verdict
    }

    var overchargeINR: Double {
        guard let asked = askedINR, asked > fairHighINR else { return 0 }
        return asked - fairHighINR
    }
}

// MARK: - Agent

struct AgentStep: Identifiable, Equatable {
    enum State: Equatable { case running, done, failed }

    let id = UUID()
    var icon: String
    var title: String
    var detail: String
    var state: State = .running
}

struct ChatMessage: Identifiable {
    enum Role { case user, agent }

    let id = UUID()
    let role: Role
    var text: String
    var image: UIImage?
    var steps: [AgentStep] = []
    var verdict: PriceVerdict?
    var isWorking = false
}

struct AgentResult {
    var text: String
    var verdict: PriceVerdict?
}

// MARK: - Rides

enum RideMode: String, CaseIterable, Identifiable, Codable {
    case auto, taxi, taxiAC

    var id: String { rawValue }

    init(apiName: String) {
        switch apiName.lowercased() {
        case "taxi", "cab": self = .taxi
        case "taxi_ac", "ac_taxi", "ac taxi": self = .taxiAC
        default: self = .auto
        }
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .taxi: "Taxi"
        case .taxiAC: "AC Taxi"
        }
    }

    var icon: String {
        switch self {
        case .auto: "car.side.fill"
        case .taxi: "car.fill"
        case .taxiAC: "snowflake"
        }
    }

    // Delhi Transport Department fare revision (2022). Verify against the current notification.
    var baseFare: Double {
        switch self {
        case .auto: 30
        case .taxi, .taxiAC: 40
        }
    }

    var baseKm: Double {
        switch self {
        case .auto: 1.5
        case .taxi, .taxiAC: 1
        }
    }

    var perKm: Double {
        switch self {
        case .auto: 11
        case .taxi: 17
        case .taxiAC: 20
        }
    }

    var ruleText: String {
        "₹\(Int(baseFare)) for the first \(baseKm.formatted()) km, then ₹\(Int(perKm))/km. +25% from 11 pm to 5 am."
    }

    func fare(km: Double, night: Bool) -> Double {
        let raw = baseFare + max(0, km - baseKm) * perKm
        return (raw * (night ? 1.25 : 1)).rounded()
    }
}

enum FareChart {
    static let source = "Delhi Transport Dept. fare chart (2022 revision)"

    static func isNight(_ date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 23 || hour < 5
    }
}

// MARK: - Places, prices, scams, phrases

enum SpotCategory: String, CaseIterable, Identifiable {
    case sight = "sight"
    case fixedPrice = "fixed_price"
    case market = "market"
    case transport = "transport"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sight: "Sights"
        case .fixedPrice: "Fixed price"
        case .market: "Markets"
        case .transport: "Transport"
        }
    }

    var icon: String {
        switch self {
        case .sight: "building.columns.fill"
        case .fixedPrice: "tag.fill"
        case .market: "basket.fill"
        case .transport: "tram.fill"
        }
    }

    var color: Color {
        switch self {
        case .sight: Theme.indigo
        case .fixedPrice: Theme.mint
        case .market: Theme.saffron
        case .transport: Theme.teal
        }
    }
}

struct Spot: Identifiable, Hashable {
    let id: String
    let name: String
    let category: SpotCategory
    let latitude: Double
    let longitude: Double
    let blurb: String
    let tip: String
    var aliases: [String] = []

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ReferencePrice: Identifiable {
    let id = UUID()
    let item: String
    let keywords: [String]
    let low: Double
    let high: Double
    let unit: String
    let source: String
    let note: String

    var dictionary: [String: Any] {
        ["item": item, "fair_low_inr": low, "fair_high_inr": high, "unit": unit, "source": source, "note": note]
    }
}

struct Scam: Identifiable {
    let id: String
    let title: String
    let icon: String
    let howItWorks: String
    let redFlags: [String]
    let whatToDo: String
    let keywords: [String]
}

struct Phrase: Identifiable, Equatable, Hashable {
    var id: String { english }
    let english: String
    let hindi: String
    let roman: String
    var category: String = "Prices"
}

struct CountryCode: Identifiable, Hashable {
    var id: String { region }
    let region: String
    let flag: String
    let dial: String
}

struct CurrencyOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let flag: String
    let fallbackINR: Double
}
