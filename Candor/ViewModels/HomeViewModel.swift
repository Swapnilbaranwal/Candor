import Foundation
import CoreLocation

/// Everything Home shows, worked out once per update from the trip, the traveller and where
/// they are. `HomeView` only lays it out.
///
/// A value type built in `body`: it holds no references, so it can't leak, and the expensive
/// parts (today's plan, the next hop's fares) come from `PlanCache`, so rebuilding it is cheap.
struct HomeViewModel {
    /// The city the traveller is in today (or heading to first). Everything on Home follows it,
    /// so a Goa trip shows Goa, not Delhi.
    let city: City
    /// Candor's drawn skyline and 3D India Gate are Delhi's; other cities get the plain scene.
    let isDelhi: Bool
    let greeting: String
    let today: String
    let displayName: String
    let placeLine: String
    let heroTitle: String
    let heroSubtitle: String
    let hasPlan: Bool
    /// Today's plan, when there is one.
    let todayPlan: DayPlan?
    /// Today is planned and every place on it is ticked off.
    let todayDone: Bool
    /// Places on today's plan, and how many are ticked off.
    let todayStopCount: Int
    let todayVisited: Int
    /// "Next up: Day 2 · Old Goa churches", once today is done.
    let nextDayLine: String?
    /// Where "Getting around" goes next, and every way to get there.
    let nextLeg: Leg

    init(app: AppState, location: LocationService, now: Date = .now) {
        let trip = app.trip
        let city = trip?.cityStay(on: now)?.city ?? trip?.cities.first?.city ?? .delhi
        self.city = city
        isDelhi = city.id == City.delhi.id

        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: greeting = L("Good morning")
        case 12..<17: greeting = L("Good afternoon")
        default: greeting = L("Good evening")
        }
        today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localizer.shared.locale))

        let fullName = app.persona.name.trimmingCharacters(in: .whitespaces)
        displayName = fullName.isEmpty ? app.persona.firstName : fullName
        placeLine = isDelhi ? location.placeLabel : L(city.name)

        let style = app.persona.travelStyle
        let likesWalking = app.persona.hasTaste("Happy to walk")

        if let trip, !trip.days.isEmpty {
            let index = trip.todayIndex
            let day = trip.days[index]
            let start = location.dayStart(trip: trip, day: index)
            hasPlan = true
            heroTitle = day.displayTitle
            heroSubtitle = Self.cityLine(trip, index: index)
            todayDone = day.isComplete
            todayStopCount = day.stops.count
            todayVisited = day.visitedCount
            nextDayLine = trip.days.indices.contains(index + 1)
                ? L("Next up: Day %1$@ · %2$@", index + 2, trip.days[index + 1].displayTitle) : nil
            todayPlan = PlanCache.shared.dayPlan(day, date: trip.date(ofDay: index), origin: start.coordinate,
                                                 originName: start.name, style: style,
                                                 city: trip.cityStay(ofDay: index)?.city, likesWalking: likesWalking)
        } else {
            hasPlan = false
            heroTitle = L("Plan your days in %@", L(city.name))
            heroSubtitle = L("Where to go each day, how to get there and what it should cost.")
            todayDone = false
            todayStopCount = 0
            todayVisited = 0
            nextDayLine = nil
            todayPlan = nil
        }

        // From where the traveller is to the next place not yet visited.
        let here = Self.here(trip: trip, city: city, location: location)
        let next = Self.nextStop(trip: trip, city: city)
        nextLeg = PlanCache.shared.leg(from: here.coordinate, fromName: here.name, to: next, at: now,
                                       style: style, city: city, likesWalking: likesWalking)
            .choosing(next.travelMode)
    }

    /// Their real location when it's in the trip city, else where the day starts there.
    private static func here(trip: Trip?, city: City, location: LocationService)
        -> (coordinate: CLLocationCoordinate2D, name: String) {
        if let current = location.location?.coordinate, city.bounds.expanded(by: 30).contains(current) {
            return (current, L("Your location"))
        }
        guard let trip, !trip.cities.isEmpty else { return (location.origin, location.originName) }
        return location.dayStart(trip: trip, day: trip.days.isEmpty ? 0 : trip.todayIndex)
    }

    /// The next place on today's plan not yet visited, else the first unvisited one on the trip,
    /// else a landmark in the city.
    private static func nextStop(trip: Trip?, city: City) -> TripStop {
        if let trip, !trip.days.isEmpty {
            if let next = trip.days[trip.todayIndex].stops.first(where: { !$0.isVisited }) { return next }
            if let first = trip.days.lazy.flatMap(\.stops).first(where: { !$0.isVisited })
                ?? trip.days.first?.stops.first { return first }
        }
        if let pack = city.pack, let first = pack.spot("indiagate") ?? pack.spots.first { return TripStop(spot: first) }
        return TripStop(name: L(city.name), coordinate: city.coordinate)
    }

    /// "Delhi · Day 2 of 3"
    static func cityLine(_ trip: Trip, index: Int) -> String {
        let day = L("Day %1$@ of %2$@", index + 1, trip.days.count)
        guard let city = trip.cityStay(ofDay: index)?.city else { return day }
        return L(city.name) + " · " + day
    }
}
