import Foundation

/// Station order on the central sections of each line, so a journey can list every stop in between
/// ("Rajiv Chowk → Patel Chowk → Central Secretariat") and say which way to board ("towards Samaypur Badli").
/// Covers the stretches around Candor's places; outside them only the boarding and alighting stations show.
extension DelhiMetro {
    static let sequences: [Line: [String]] = [
        .yellow: ["Kashmere Gate", "Chandni Chowk", "Chawri Bazar", "New Delhi", "Rajiv Chowk", "Patel Chowk",
                  "Central Secretariat", "Udyog Bhawan", "Lok Kalyan Marg", "Jor Bagh", "Dilli Haat–INA", "AIIMS",
                  "Green Park", "Hauz Khas", "Malviya Nagar", "Saket", "Qutab Minar"],
        .blue: ["Rajiv Chowk", "Barakhamba Road", "Mandi House", "Supreme Court", "Indraprastha", "Yamuna Bank",
                "Akshardham", "Mayur Vihar-I"],
        .violet: ["Kashmere Gate", "Lal Quila", "Jama Masjid", "Delhi Gate", "ITO", "Mandi House", "Janpath",
                  "Central Secretariat", "Khan Market", "JLN Stadium", "Jangpura", "Lajpat Nagar", "Moolchand",
                  "Kailash Colony", "Nehru Place", "Kalkaji Mandir"],
        .pink: ["Mayur Vihar-I", "Hazrat Nizamuddin", "Ashram", "Vinobapuri", "Lajpat Nagar", "South Extension",
                "Dilli Haat–INA"],
        .magenta: ["Kalkaji Mandir", "Nehru Enclave", "Greater Kailash", "Chirag Delhi", "Panchsheel Park", "Hauz Khas"],
        .airport: ["New Delhi", "Shivaji Stadium", "Dhaula Kuan", "Delhi Aerocity", "IGI Airport (T3)"]
    ]

    /// The line's end station in each direction along `sequences`: (towards the start, towards the end).
    static let terminals: [Line: (String, String)] = [
        .yellow: ("Samaypur Badli", "Millennium City Centre Gurugram"),
        .blue: ("Dwarka Sector 21", "Noida Electronic City"),
        .violet: ("Kashmere Gate", "Raja Nahar Singh"),
        .pink: ("Shiv Vihar", "Majlis Park"),
        .magenta: ("Botanical Garden", "Janakpuri West"),
        .airport: ("New Delhi", "Yashobhoomi Dwarka Sector 25")
    ]

    /// The stations passed between two stations on a line (not counting either end), in riding order.
    static func stops(on line: Line, from: String, to: String) -> [String]? {
        guard let list = sequences[line],
              let a = list.firstIndex(where: { matches($0, from) }),
              let b = list.firstIndex(where: { matches($0, to) }), a != b else { return nil }
        let between = a < b ? Array(list[(a + 1)..<b]) : Array(list[(b + 1)..<a].reversed())
        return between
    }

    /// Which end of the line to look for on the platform signs.
    static func towards(on line: Line, from: String, to: String) -> String? {
        guard let list = sequences[line], let ends = terminals[line],
              let a = list.firstIndex(where: { matches($0, from) }),
              let b = list.firstIndex(where: { matches($0, to) }), a != b else { return nil }
        return a < b ? ends.1 : ends.0
    }

    /// Finds the line Google calls "Yellow Line" or "DMRC Yellow Line".
    static func line(named name: String) -> Line? {
        let lower = name.lowercased()
        return Line.allCases.first { lower.contains("\($0.rawValue) line") || lower.contains($0.title.lowercased()) }
    }

    /// "Rajiv Chowk Metro Station" matches "Rajiv Chowk".
    static func matches(_ station: String, _ name: String) -> Bool {
        let a = station.lowercased().replacingOccurrences(of: "–", with: " ").replacingOccurrences(of: "-", with: " ")
        let b = name.lowercased().replacingOccurrences(of: "–", with: " ").replacingOccurrences(of: "-", with: " ")
        return b.contains(a) || a.contains(b)
    }
}

/// Candor's own services, set per build in `Keys.xcconfig`.
enum CandorService {
    /// The Candor Cars booking line (`CANDOR_CARS_PHONE` in Keys.xcconfig), e.g. "+91 98XXXXXXXX".
    static var carsPhone: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "CandorCarsPhone") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }

    static var carsPhoneDigits: String { carsPhone.filter { $0.isNumber } }
    static var hasCarsPhone: Bool { carsPhoneDigits.count >= 8 }
}
