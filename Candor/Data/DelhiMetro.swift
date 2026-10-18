import SwiftUI
import CoreLocation

typealias MetroLine = DelhiMetro.Line

/// A small slice of the Delhi Metro: the stations near Candor's places, and how to ride between them.
/// Distances are straight lines between stations × 1.25, so times and fares are estimates.
enum DelhiMetro {
    enum Line: String, CaseIterable {
        case yellow, blue, violet, pink, magenta, red, airport

        var title: String {
            switch self {
            case .yellow: L("Yellow Line")
            case .blue: L("Blue Line")
            case .violet: L("Violet Line")
            case .pink: L("Pink Line")
            case .magenta: L("Magenta Line")
            case .red: L("Red Line")
            case .airport: L("Airport Express")
            }
        }

        var color: Color {
            switch self {
            case .yellow: Color(red: 0.98, green: 0.78, blue: 0.10)
            case .blue: Color(red: 0.10, green: 0.42, blue: 0.86)
            case .violet: Color(red: 0.56, green: 0.30, blue: 0.76)
            case .pink: Color(red: 0.95, green: 0.45, blue: 0.66)
            case .magenta: Color(red: 0.80, green: 0.10, blue: 0.55)
            case .red: Color(red: 0.86, green: 0.16, blue: 0.16)
            case .airport: Color(red: 1.00, green: 0.50, blue: 0.05)
            }
        }
    }

    struct Station: Identifiable, Hashable {
        let id: String
        let name: String
        let lines: Set<Line>
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        func km(to other: Station) -> Double {
            DelhiMetro.km(coordinate, other.coordinate)
        }
    }

    /// One ride on one line.
    struct Segment {
        let line: Line
        let from: Station
        let to: Station
        var km: Double { from.km(to: to) * 1.25 }
    }

    struct Route {
        let segments: [Segment]

        var changes: Int { segments.count - 1 }
        var km: Double { segments.reduce(0) { $0 + $1.km } }
        var minutes: Int { Int((km / 32 * 60 + 4 + Double(6 * changes)).rounded(.up)) }
        var usesAirportExpress: Bool { segments.contains { $0.line == .airport } }

        /// DMRC fare slabs by distance. The Airport Express has its own, higher fares.
        var fare: (low: Double, high: Double) {
            let regularKm = segments.filter { $0.line != .airport }.reduce(0) { $0 + $1.km }
            guard regularKm > 0 else { return (50, 60) }
            let slab = DelhiMetro.slabFare(km: regularKm)
            return usesAirportExpress ? (slab + 60, slab + 60) : (slab, slab)
        }
    }

    static let stations: [Station] = [
        Station(id: "rajivchowk", name: "Rajiv Chowk", lines: [.yellow, .blue], latitude: 28.6328, longitude: 77.2197),
        Station(id: "newdelhi", name: "New Delhi", lines: [.yellow, .airport], latitude: 28.6430, longitude: 77.2215),
        Station(id: "chandnichowk", name: "Chandni Chowk", lines: [.yellow], latitude: 28.6580, longitude: 77.2301),
        Station(id: "kashmeregate", name: "Kashmere Gate", lines: [.yellow, .violet, .red], latitude: 28.6675, longitude: 77.2282),
        Station(id: "centralsecretariat", name: "Central Secretariat", lines: [.yellow, .violet], latitude: 28.6149, longitude: 77.2119),
        Station(id: "ina", name: "Dilli Haat–INA", lines: [.yellow, .pink], latitude: 28.5753, longitude: 77.2093),
        Station(id: "hauzkhas", name: "Hauz Khas", lines: [.yellow, .magenta], latitude: 28.5433, longitude: 77.2067),
        Station(id: "qutabminar", name: "Qutab Minar", lines: [.yellow], latitude: 28.5134, longitude: 77.1863),
        Station(id: "mandihouse", name: "Mandi House", lines: [.blue, .violet], latitude: 28.6258, longitude: 77.2342),
        Station(id: "supremecourt", name: "Supreme Court", lines: [.blue], latitude: 28.6234, longitude: 77.2437),
        Station(id: "akshardham", name: "Akshardham", lines: [.blue], latitude: 28.6181, longitude: 77.2794),
        Station(id: "mayurvihar", name: "Mayur Vihar-I", lines: [.blue, .pink], latitude: 28.6045, longitude: 77.2894),
        Station(id: "janpath", name: "Janpath", lines: [.violet], latitude: 28.6253, longitude: 77.2187),
        Station(id: "khanmarket", name: "Khan Market", lines: [.violet], latitude: 28.6030, longitude: 77.2283),
        Station(id: "jln", name: "JLN Stadium", lines: [.violet], latitude: 28.5904, longitude: 77.2337),
        Station(id: "lajpatnagar", name: "Lajpat Nagar", lines: [.violet, .pink], latitude: 28.5708, longitude: 77.2365),
        Station(id: "kalkaji", name: "Kalkaji Mandir", lines: [.violet, .magenta], latitude: 28.5492, longitude: 77.2588),
        Station(id: "lalquila", name: "Lal Quila", lines: [.violet], latitude: 28.6566, longitude: 77.2373),
        Station(id: "nizamuddin", name: "Hazrat Nizamuddin", lines: [.pink], latitude: 28.5880, longitude: 77.2510),
        Station(id: "shivaji", name: "Shivaji Stadium", lines: [.airport], latitude: 28.6290, longitude: 77.2117),
        Station(id: "dhaulakuan", name: "Dhaula Kuan", lines: [.airport], latitude: 28.5918, longitude: 77.1615),
        Station(id: "aerocity", name: "Delhi Aerocity", lines: [.airport], latitude: 28.5488, longitude: 77.1205),
        Station(id: "igi", name: "IGI Airport (T3)", lines: [.airport], latitude: 28.5563, longitude: 77.0869)
    ]

    static func km(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }

    static func nearestStation(to coordinate: CLLocationCoordinate2D) -> (station: Station, km: Double) {
        let pairs = stations.map { ($0, km(coordinate, $0.coordinate)) }
        let nearest = pairs.min { $0.1 < $1.1 }!
        return (nearest.0, nearest.1)
    }

    static func slabFare(km: Double) -> Double {
        switch km {
        case ..<2: 10
        case ..<5: 20
        case ..<12: 30
        case ..<21: 40
        case ..<32: 50
        default: 60
        }
    }

    /// The shortest ride with the fewest changes: direct if a line serves both stations,
    /// else one change, else two.
    static func route(from a: Station, to b: Station) -> Route? {
        guard a != b else { return nil }

        // No change.
        let direct = a.lines.intersection(b.lines)
            .map { Route(segments: [Segment(line: $0, from: a, to: b)]) }
        if let best = direct.min(by: { $0.km < $1.km }) { return best }

        // One change.
        var oneChange: [Route] = []
        for first in a.lines {
            for last in b.lines where first != last {
                for change in stations where change != a && change != b
                    && change.lines.contains(first) && change.lines.contains(last) {
                    oneChange.append(Route(segments: [Segment(line: first, from: a, to: change),
                                                      Segment(line: last, from: change, to: b)]))
                }
            }
        }
        if let best = oneChange.min(by: { $0.km < $1.km }) { return best }

        // Two changes.
        var twoChanges: [Route] = []
        for first in a.lines {
            for last in b.lines {
                for middle in Line.allCases where middle != first && middle != last {
                    let ins = stations.filter { $0 != a && $0.lines.contains(first) && $0.lines.contains(middle) }
                    let outs = stations.filter { $0 != b && $0.lines.contains(middle) && $0.lines.contains(last) }
                    for x in ins {
                        for y in outs where x != y {
                            twoChanges.append(Route(segments: [Segment(line: first, from: a, to: x),
                                                               Segment(line: middle, from: x, to: y),
                                                               Segment(line: last, from: y, to: b)]))
                        }
                    }
                }
            }
        }
        return twoChanges.min { $0.km < $1.km }
    }
}
