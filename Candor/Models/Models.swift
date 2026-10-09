import SwiftUI
import CoreLocation

// MARK: - Persona

/// How the traveller signed in. No option needs an Indian mobile number.
enum SignInMethod: String, Codable {
    case apple, google, email, phone, guest
}

struct Persona: Codable, Equatable {
    var name = ""
    /// Set only for phone sign-in, stored with its dial code ("+44 7911123456").
    var phone = ""
    /// Optional so personas saved before multi-option sign-in still decode.
    var email: String?
    var signInMethod: SignInMethod?
    var homeCurrency = Persona.defaultCurrency
    var languageCode = Persona.defaultLanguage
    var travelStyle: TravelStyle = .comfort
    var interests: [String] = []
    /// How they like to travel, as plain statements ("Street food over fine dining"). English keys
    /// from `Persona.tasteOptions`. Optional so personas saved before it still decode.
    var tastes: [String]?
    var tripDays = 2
    var isComplete = false

    /// Taste statements offered in onboarding. They go to Gemini as written and tune the planner.
    static let tasteOptions = [
        "Street food over fine dining",
        "Local gems over famous sights",
        "Happy to walk",
        "Avoid crowds",
        "Early starts",
        "Slow mornings",
        "Kid-friendly",
        "Vegetarian"
    ]

    var hasTaste: (String) -> Bool { { (tastes ?? []).contains($0) } }

    /// English, for prompting Gemini.
    var tasteSummary: String {
        let list = tastes ?? []
        return list.isEmpty ? "no stated preferences" : list.joined(separator: "; ")
    }

    static var defaultLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static var defaultCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return CurrencyOption.all.contains { $0.code == code } ? code : "USD"
    }

    /// Language name shown in the UI, written in that language ("Español", "日本語").
    var languageName: String { Persona.nativeName(of: languageCode) }

    /// A language's own name for itself, so travellers can find theirs whatever the phone is set to.
    static func nativeName(of code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    /// Language name in English, used for prompting Gemini.
    var englishLanguageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? L("Traveller")
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "C" : letters.uppercased()
    }

    /// Account line shown under the name on the profile.
    var accountLabel: String {
        switch signInMethod {
        case .apple?: return L("Signed in with Apple")
        case .google?: return L("Signed in with Google")
        case .email?: return email ?? L("Signed in with email")
        case .guest?: return L("Guest")
        case .phone?, nil: return phone.isEmpty ? L("Guest") : phone
        }
    }
}

enum TravelParty: String, Codable, CaseIterable, Identifiable {
    case solo, couple, family, group
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solo: L("Solo")
        case .couple: L("Couple")
        case .family: L("Family")
        case .group: L("Friends")
        }
    }
    var icon: String {
        switch self {
        case .solo: "person.fill"
        case .couple: "person.2.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .group: "person.3.fill"
        }
    }
    /// Solo and couple have a fixed size; the others ask how many.
    var fixedCount: Int? {
        switch self {
        case .solo: 1
        case .couple: 2
        case .family, .group: nil
        }
    }
}

/// A booked hotel or home, picked from Apple Maps.
struct Stay: Codable, Equatable {
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TravelStyle: String, Codable, CaseIterable, Identifiable {
    case budget, comfort, luxury
    var id: String { rawValue }
    var title: String {
        switch self {
        case .budget: L("Budget")
        case .comfort: L("Comfort")
        case .luxury: L("Luxury")
        }
    }
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
        case .fair: L("Fair price")
        case .high: L("A bit high")
        case .overcharge: L("Overcharge")
        case .info: L("Fair range")
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
        case .agent: "text.bubble"
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
        case .auto: L("Auto")
        case .taxi: L("Taxi")
        case .taxiAC: L("AC Taxi")
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
        L("₹%1$@ for the first %2$@ km, then ₹%3$@/km. +25% from 11 pm to 5 am.",
          Int(baseFare), baseKm.formatted(), Int(perKm))
    }

    func fare(km: Double, night: Bool) -> Double {
        let raw = baseFare + max(0, km - baseKm) * perKm
        return (raw * (night ? 1.25 : 1)).rounded()
    }
}

enum FareChart {
    /// English key: shown through `L(…)`, and matched on "fare" to pick the phrase to say.
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
        case .sight: L("Sights")
        case .fixedPrice: L("Fixed price")
        case .market: L("Markets")
        case .transport: L("Transport")
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
    /// Accepted length of the national number, without the dial code or a leading trunk "0".
    var digits: ClosedRange<Int> = 6...12

    /// Digits of the national number. Drops the "0" many countries dial domestically
    /// (07911… in the UK); Italy keeps its leading zero.
    func national(_ input: String) -> String {
        let number = input.filter { $0.isASCII && $0.isNumber }
        guard region != "IT", number.hasPrefix("0") else { return number }
        return String(number.dropFirst())
    }

    func isValid(_ input: String) -> Bool {
        digits.contains(national(input).count)
    }
}

struct CurrencyOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let flag: String
    let fallbackINR: Double
}
