import Foundation

/// When a place is open through the week: from Google Maps when it has them, else Candor's usual hours.
struct OpeningHours: Codable, Hashable {
    struct Period: Codable, Hashable {
        /// 0 is Sunday, as in Google Maps.
        var day: Int
        /// Minutes from midnight. `close` passes 24 h when the place shuts after midnight.
        var open: Int
        var close: Int
    }

    var periods: [Period] = []
    var alwaysOpen = false

    static let always = OpeningHours(alwaysOpen: true)

    /// The same hours every day except the `closed` weekdays (0 = Sunday).
    static func daily(_ open: Int, _ close: Int, closed: Set<Int> = []) -> OpeningHours {
        OpeningHours(periods: (0...6).filter { !closed.contains($0) }.map { Period(day: $0, open: open, close: close) })
    }

    /// Opening windows on `date`, in minutes from midnight, earliest first. Empty when shut all day.
    func windows(on date: Date) -> [(open: Int, close: Int)] {
        if alwaysOpen { return [(0, 24 * 60)] }
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return periods.filter { $0.day == weekday }.map { ($0.open, $0.close) }.sorted { $0.open < $1.open }
    }
}

/// "9:30 AM", in the app's language.
func minuteText(_ minutes: Int) -> String {
    let date = Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
    return timeText(date)
}

extension TripStop {
    /// Google's hours for the stop, else Candor's usual ones for its own places.
    var openingHours: OpeningHours? {
        hours ?? spotID.flatMap { DelhiData.usualHours[$0] }
    }

    /// Minutes before closing that the gate stops letting people in. Monuments stop selling
    /// tickets about half an hour before; shops and markets serve until they close.
    var lastEntryGap: Int {
        if let spotID, let gap = DelhiData.lastEntryGap[spotID] { return gap }
        switch spot?.category {
        case .market, .fixedPrice, .transport: return 0
        default: return 30
        }
    }

    /// "9:30 AM–4:30 PM, last entry 4:00 PM", "Open 24 hours" or "Closed on Mondays". Nil when unknown.
    func hoursText(on date: Date) -> String? {
        guard let hours = openingHours else { return nil }
        if hours.alwaysOpen { return L("Open 24 hours") }
        let windows = hours.windows(on: date)
        if windows.isEmpty {
            return L("Closed on %@", date.formatted(.dateTime.weekday(.wide).locale(Localizer.shared.locale)))
        }
        return windows.map { window in
            let span = "\(minuteText(window.open))–\(minuteText(window.close))"
            return lastEntryGap > 0 ? span + ", " + L("last entry %@", minuteText(window.close - lastEntryGap)) : span
        }.joined(separator: "; ")
    }
}

extension DelhiData {
    private static func time(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    /// Usual opening hours for Candor's Delhi places, until Google Maps answers. Weekdays: 0 = Sunday, 1 = Monday.
    static let usualHours: [String: OpeningHours] = [
        "redfort": .daily(time(9, 30), time(16, 30), closed: [1]),
        "indiagate": .always,
        "humayun": .daily(time(6), time(18)),
        "qutub": .daily(time(7), time(17)),
        "lotus": .daily(time(9), time(17), closed: [1]),
        "akshardham": .daily(time(10), time(18, 30), closed: [1]),
        "chandnichowk": .daily(time(10), time(21), closed: [0]),
        "dillihaat": .daily(time(10, 30), time(22)),
        "khan": .daily(time(10), time(22)),
        "cp": .daily(time(10), time(22)),
        "emporium": .daily(time(10), time(19)),
        "itb": .daily(time(8), time(20)),
        "prepaid": .always,
        "airport": .always
    ]

    /// Places whose last entry isn't the usual half hour before closing.
    static let lastEntryGap: [String: Int] = ["akshardham": 60, "indiagate": 0, "prepaid": 0, "airport": 0]
}
