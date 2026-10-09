import Foundation
import CoreLocation

// MARK: - Cities

/// How much Candor knows about a city.
enum Coverage: String, Codable {
    /// Candor's own checked data: official fare chart, reference prices, scams, places, transit.
    case verified
    /// Any other city: Gemini and Google Maps, with every price marked as an estimate.
    case ai

    var title: String {
        switch self {
        case .verified: L("Verified guide")
        case .ai: L("AI guide")
        }
    }

    var detail: String {
        switch self {
        case .verified: L("Official fares, checked prices and known scams.")
        case .ai: L("Places and price estimates from Google Maps and Gemini.")
        }
    }
}

/// A destination. Verified cities carry a `CityPack`; any other city found in Google Maps
/// still works as an AI guide, so no traveller hits a dead end.
struct City: Codable, Hashable, Identifiable {
    /// Candor's id for verified cities ("delhi"), else the Google place id.
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    /// South-west and north-east corners of the metro area, for place search.
    let bounds: Bounds
    var coverage: Coverage

    struct Bounds: Codable, Hashable {
        let lowLatitude: Double
        let lowLongitude: Double
        let highLatitude: Double
        let highLongitude: Double

        /// The same box grown on every side by `km`, for places just outside town (day trips).
        func expanded(by km: Double) -> Bounds {
            let midLatitude = (lowLatitude + highLatitude) / 2
            let dLat = km / 111
            let dLon = km / (111 * max(cos(midLatitude * .pi / 180), 0.2))
            return Bounds(lowLatitude: lowLatitude - dLat, lowLongitude: lowLongitude - dLon,
                          highLatitude: highLatitude + dLat, highLongitude: highLongitude + dLon)
        }

        func contains(_ point: CLLocationCoordinate2D) -> Bool {
            (lowLatitude...highLatitude).contains(point.latitude)
                && (lowLongitude...highLongitude).contains(point.longitude)
        }

        /// A box about `km` across around a point, for cities without hand-drawn bounds.
        static func around(latitude: Double, longitude: Double, km: Double = 40) -> Bounds {
            let dLat = km / 2 / 111
            let dLon = km / 2 / (111 * max(cos(latitude * .pi / 180), 0.2))
            return Bounds(lowLatitude: latitude - dLat, lowLongitude: longitude - dLon,
                          highLatitude: latitude + dLat, highLongitude: longitude + dLon)
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Candor's checked data for this city, or nil for an AI-guide city.
    var pack: CityPack? { CityPack.all[id] }

    /// "Delhi, India"
    var displayName: String { country.isEmpty ? L(name) : "\(L(name)), \(L(country))" }
}

extension City {
    static let delhi = City(id: "delhi", name: "Delhi", country: "India",
                            latitude: 28.6139, longitude: 77.2090,
                            // Delhi NCR: Gurugram and Dwarka in the south-west to Noida and Ghaziabad in the east.
                            bounds: Bounds(lowLatitude: 28.40, lowLongitude: 76.84, highLatitude: 28.88, highLongitude: 77.55),
                            coverage: .verified)

    /// Cities Candor suggests before the traveller types anything. Only Delhi is verified today;
    /// the rest work as AI guides until their packs are added.
    static let featured: [City] = [
        delhi,
        City(id: "agra", name: "Agra", country: "India", latitude: 27.1767, longitude: 78.0081,
             bounds: .around(latitude: 27.1767, longitude: 78.0081, km: 30), coverage: .ai),
        City(id: "jaipur", name: "Jaipur", country: "India", latitude: 26.9124, longitude: 75.7873,
             bounds: .around(latitude: 26.9124, longitude: 75.7873, km: 40), coverage: .ai),
        City(id: "mumbai", name: "Mumbai", country: "India", latitude: 19.0760, longitude: 72.8777,
             bounds: .around(latitude: 19.0760, longitude: 72.8777, km: 50), coverage: .ai),
        City(id: "goa", name: "Goa", country: "India", latitude: 15.2993, longitude: 74.1240,
             bounds: .around(latitude: 15.2993, longitude: 74.1240, km: 90), coverage: .ai),
        City(id: "varanasi", name: "Varanasi", country: "India", latitude: 25.3176, longitude: 82.9739,
             bounds: .around(latitude: 25.3176, longitude: 82.9739, km: 25), coverage: .ai)
    ]

    /// The city a saved id refers to, when Candor knows it.
    static func known(_ id: String) -> City? {
        featured.first { $0.id == id }
    }
}

// MARK: - City packs

/// Everything Candor has checked for one city. Screens and the agent read a city's pack instead
/// of a hard-coded city, so adding a city means adding a pack.
struct CityPack {
    /// Where trip days start when no hotel is set (a central, well-known spot).
    let defaultStart: CLLocationCoordinate2D
    let defaultStartName: String
    let spots: [Spot]
    let prices: [ReferencePrice]
    let scams: [Scam]
    let phrases: [Phrase]
    let phraseCategories: [String]
    /// Spoken language for phrases, as a speech locale ("hi-IN").
    let speechLanguage: String
    /// Weekly closing day by spot id (`Calendar` weekday: 1 = Sunday, 2 = Monday).
    let closedWeekday: [String: Int]
    /// Spot ids that suit each interest in `DelhiData.interests`.
    let interestSpots: [String: [String]]
    /// Source line for metered fares (`RideMode`), or nil when the city has no official chart.
    let fareSource: String?
    /// True when `DelhiMetro`-style routing is available for this city.
    let hasMetro: Bool

    func spot(_ id: String) -> Spot? { spots.first { $0.id == id } }

    static let delhi = CityPack(
        defaultStart: DelhiData.connaughtPlace,
        defaultStartName: "Connaught Place",
        spots: DelhiData.spots,
        prices: DelhiData.prices,
        scams: DelhiData.scams,
        phrases: DelhiData.phrases,
        phraseCategories: DelhiData.phraseCategories,
        speechLanguage: "hi-IN",
        closedWeekday: DelhiData.closedWeekday,
        interestSpots: [
            "Heritage": ["redfort", "humayun", "qutub", "indiagate"],
            "Street food": ["chandnichowk", "dillihaat"],
            "Markets": ["chandnichowk", "khan", "dillihaat", "cp", "emporium"],
            "Spiritual": ["lotus", "akshardham"],
            "Art & crafts": ["emporium", "dillihaat"],
            "Nightlife": ["cp", "khan"]
        ],
        fareSource: FareChart.source,
        hasMetro: true
    )

    /// Packs by city id.
    static let all: [String: CityPack] = ["delhi": delhi]
}
