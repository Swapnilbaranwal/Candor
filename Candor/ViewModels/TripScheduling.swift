import Foundation

/// Changes to the trip that respect opening hours: adding a place where it's open, moving
/// closed stops to a time they're open, and looking up real hours in Google Maps.
extension AppState {
    /// What happened when a place was added.
    enum AddResult {
        /// Added to `day` (moved there when the asked day had no open slot).
        case added(day: Int, moved: Bool)
        case alreadyThere(day: Int)
        /// No day has a time when it's open; the hours explain why.
        case noOpenSlot(hours: String?)
    }

    /// The day's plan, timed the way the Trip tab shows it.
    func plan(for day: TripDay, at index: Int, location: LocationService) -> DayPlan {
        guard let trip else {
            return TripPlanner.dayPlan(day, date: .now, origin: location.origin, originName: location.originName,
                                       style: persona.travelStyle)
        }
        let start = location.dayStart(trip: trip, day: index)
        return PlanCache.shared.dayPlan(day, date: trip.date(ofDay: index), origin: start.coordinate, originName: start.name,
                                        style: persona.travelStyle, city: trip.cityStay(ofDay: index)?.city,
                                        likesWalking: persona.hasTaste("Happy to walk"))
    }

    /// Adds a place at a time it's open: the asked day first, then the trip's other days.
    @discardableResult
    func addPlace(_ stop: TripStop, preferring dayIndex: Int, location: LocationService) async -> AddResult {
        var stop = stop
        if let trip, let day = trip.days.firstIndex(where: { $0.stops.contains { same($0, stop) } }) {
            return .alreadyThere(day: day)
        }
        // Real hours first, so a late slot isn't chosen on guessed ones.
        if stop.hours == nil, let found = await Self.lookUpHours(stop) { stop.hours = found }
        guard let trip,
              let slot = TripPlanner.slot(for: stop, preferring: dayIndex, in: trip,
                                          plan: { plan(for: $0, at: $1, location: location) }) else {
            return .noOpenSlot(hours: self.trip.map { stop.hoursText(on: $0.date(ofDay: dayIndex)) } ?? nil)
        }
        self.trip?.days[slot.day].stops.insert(stop, at: slot.index)
        return .added(day: slot.day, moved: slot.day != dayIndex)
    }

    /// Moves the day's closed stops to a time they're open. Returns the names it couldn't place.
    @discardableResult
    func fixClosedStops(day dayIndex: Int, location: LocationService) -> [String] {
        guard var trip, trip.days.indices.contains(dayIndex) else { return [] }
        let closedIDs = Set(plan(for: trip.days[dayIndex], at: dayIndex, location: location).entries
            .filter(\.isClosed).map(\.stop.id))
        let closed = trip.days[dayIndex].stops.filter { closedIDs.contains($0.id) }
        trip.days[dayIndex].stops.removeAll { closedIDs.contains($0.id) }
        var stuck: [String] = []
        for stop in closed {
            if let slot = TripPlanner.slot(for: stop, preferring: dayIndex, in: trip,
                                           plan: { plan(for: $0, at: $1, location: location) }) {
                trip.days[slot.day].stops.insert(stop, at: slot.index)
            } else {
                trip.days[dayIndex].stops.append(stop)
                stuck.append(stop.name)
            }
        }
        self.trip = trip
        return stuck
    }

    /// Fills in Google Maps opening hours for the day's places that don't have them yet.
    func loadOpeningHours(day dayIndex: Int) async {
        guard let stops = trip?.days[safe: dayIndex]?.stops else { return }
        for stop in stops where stop.hours == nil && !Self.askedForHours.contains(stop.id) {
            Self.askedForHours.insert(stop.id)
            guard let hours = await Self.lookUpHours(stop),
                  let index = trip?.days[safe: dayIndex]?.stops.firstIndex(where: { $0.id == stop.id }) else { continue }
            trip?.days[dayIndex].stops[index].hours = hours
        }
    }

    /// Stops already looked up this session, so a place Google has no hours for isn't asked again.
    @MainActor private static var askedForHours = Set<UUID>()

    private static func lookUpHours(_ stop: TripStop) async -> OpeningHours? {
        try? await GooglePlaces.details(stop.name, near: stop.coordinate)?.openingHours
    }

    private func same(_ a: TripStop, _ b: TripStop) -> Bool {
        if let id = a.spotID { return id == b.spotID }
        return b.spotID == nil && a.name == b.name
            && abs(a.latitude - b.latitude) < 0.0005 && abs(a.longitude - b.longitude) < 0.0005
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
