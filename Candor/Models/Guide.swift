import SwiftUI

// MARK: - Travel with a guide

/// A verified local guide. Prototype data: the names and profiles are illustrative.
struct Guide: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    /// Language codes the guide speaks well ("en", "fr").
    let languages: [String]
    /// Interest keys from `DelhiData.interests` the guide is known for.
    let specialties: [String]
    let rating: Double
    let tours: Int
    let years: Int
    let hourlyINR: Double
    /// One line in English, shown through `L`.
    let bio: String
    /// Index into `Guide.tints` for the avatar.
    let tint: Int

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var color: Color { Guide.tints[tint % Guide.tints.count] }

    static let tints: [Color] = [Theme.indigo, Theme.coral, Theme.teal, Theme.violet, Theme.mint, Theme.sky]

    /// What "verified" means at Candor, shown on every guide.
    static let checks = ["Government ID and police check", "Ministry of Tourism guide licence",
                         "Trained on fair prices and scams", "Reviewed after every tour"]
}

/// How the traveller pays for a guide.
enum GuidePlan: String, Codable, CaseIterable, Identifiable {
    /// The guide's hourly rate, two hours minimum.
    case hourly
    /// Up to eight hours in one day for a flat price.
    case dayPass
    /// Monthly membership: a quarter off every hour and first pick of guides.
    case plus

    var id: String { rawValue }

    static let dayPassINR: Double = 3999
    static let plusMonthlyINR: Double = 999
    static let plusDiscount = 0.25

    var title: String {
        switch self {
        case .hourly: L("By the hour")
        case .dayPass: L("Day pass")
        case .plus: L("Candor Plus")
        }
    }

    var subtitle: String {
        switch self {
        case .hourly: L("Pay only for the hours you need. 2 hours minimum.")
        case .dayPass: L("Up to 8 hours with one guide, one flat price.")
        case .plus: L("%@ a month: 25% off every hour and first pick of guides.", inr(GuidePlan.plusMonthlyINR))
        }
    }

    var icon: String {
        switch self {
        case .hourly: "clock.fill"
        case .dayPass: "sun.max.fill"
        case .plus: "crown.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .hourly: CardPalette.fair
        case .dayPass: CardPalette.home
        case .plus: CardPalette.guide
        }
    }

    /// The tour price for `hours` with a guide at `rate` per hour.
    func price(hours: Int, rate: Double) -> Double {
        switch self {
        case .hourly: rate * Double(max(hours, 2))
        case .dayPass: GuidePlan.dayPassINR
        case .plus: (rate * Double(max(hours, 2)) * (1 - GuidePlan.plusDiscount)).rounded()
        }
    }

    /// "from ₹500/h", "₹3,999/day"
    var priceLine: String {
        switch self {
        case .hourly: L("from %@/h", inr(GuideDesk.lowestRate))
        case .dayPass: L("%@ a day", inr(GuidePlan.dayPassINR))
        case .plus: L("from %@/h", inr((GuideDesk.lowestRate * (1 - GuidePlan.plusDiscount)).rounded()))
        }
    }
}

/// A booked tour. The best verified guide is locked in an hour before the start, from a
/// shortlist made at booking time, so the traveller never waits for a match on the day.
struct GuideBooking: Codable, Equatable, Identifiable {
    var id = UUID()
    var city: String
    var start: Date
    var hours: Int
    var plan: GuidePlan
    var languageCode: String
    var interests: [String]
    var meetingPoint: String
    /// Ranked best first when booked.
    var shortlist: [Guide]
    var createdAt = Date.now

    enum Status { case matching, assigned, live, done }

    /// When the guide is locked in.
    var assignAt: Date { start.addingTimeInterval(-3600) }
    var end: Date { start.addingTimeInterval(Double(hours) * 3600) }

    func status(at now: Date = .now) -> Status {
        if now >= end { return .done }
        if now >= start { return .live }
        if now >= assignAt { return .assigned }
        return .matching
    }

    /// The assigned guide, once matching has closed.
    func guide(at now: Date = .now) -> Guide? {
        status(at: now) == .matching ? nil : shortlist.first
    }

    var price: Double {
        plan.price(hours: hours, rate: shortlist.first?.hourlyINR ?? GuideDesk.lowestRate)
    }
}

/// Candor's guide desk: the verified guides and how they're matched.
enum GuideDesk {
    static let pool: [Guide] = [
        Guide(id: "g1", name: "Aarav Mehta", languages: ["en", "hi", "fr"], specialties: ["Heritage", "Photography"],
              rating: 4.9, tours: 412, years: 9, hourlyINR: 650,
              bio: "Old Delhi lanes, Mughal stories and the best light for photos.", tint: 0),
        Guide(id: "g2", name: "Meera Iyer", languages: ["en", "hi", "de", "es"], specialties: ["Street food", "Markets"],
              rating: 4.9, tours: 538, years: 7, hourlyINR: 600,
              bio: "Food walks from Chandni Chowk to Majnu ka Tilla, with fair prices at every stall.", tint: 1),
        Guide(id: "g3", name: "Kabir Singh", languages: ["en", "hi", "ja"], specialties: ["Spiritual", "Heritage"],
              rating: 4.8, tours: 296, years: 11, hourlyINR: 700,
              bio: "Temples, gurdwaras and Sufi shrines, explained with care.", tint: 2),
        Guide(id: "g4", name: "Ananya Rao", languages: ["en", "hi", "it", "pt"], specialties: ["Art & crafts", "Markets"],
              rating: 4.8, tours: 221, years: 6, hourlyINR: 550,
              bio: "Craft bazaars and artisan workshops, and how to bargain kindly.", tint: 3),
        Guide(id: "g5", name: "Rohan Das", languages: ["en", "hi", "ru", "ko"], specialties: ["Nightlife", "Street food"],
              rating: 4.7, tours: 187, years: 5, hourlyINR: 500,
              bio: "Evenings in Delhi: night markets, live music and safe rides home.", tint: 4),
        Guide(id: "g6", name: "Zoya Khan", languages: ["en", "hi", "ar", "zh"], specialties: ["Nature", "Photography"],
              rating: 4.9, tours: 344, years: 8, hourlyINR: 600,
              bio: "Gardens, step-wells and quiet corners away from the crowds.", tint: 5)
    ]

    static var lowestRate: Double { pool.map(\.hourlyINR).min() ?? 500 }

    /// The earliest a tour can start: an hour from now (so a guide can be locked in), on the quarter hour.
    static var earliestStart: Date {
        let soon = Date.now.addingTimeInterval(3600 + 15 * 60)
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: soon)
        let rounded = calendar.date(bySetting: .second, value: 0, of: soon) ?? soon
        return calendar.date(byAdding: .minute, value: (15 - minute % 15) % 15, to: rounded) ?? soon
    }

    /// Guides ranked for a traveller: speaks their language, knows what they love, rated highly.
    static func shortlist(language: String, interests: [String], plan: GuidePlan, count: Int = 3) -> [Guide] {
        func score(_ guide: Guide) -> Double {
            var score = guide.rating * 2
            if guide.languages.contains(language) { score += 6 }
            score += Double(Set(guide.specialties).intersection(interests).count) * 2
            if plan == .plus { score += Double(guide.tours) / 200 }
            return score
        }
        return Array(pool.sorted { score($0) > score($1) }.prefix(count))
    }
}
