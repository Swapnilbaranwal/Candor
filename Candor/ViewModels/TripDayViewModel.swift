import Foundation
import CoreLocation

/// One day of the trip as the Trip tab shows it: the plan, its numbers, whether it's done and
/// where to go next. `TripView` only lays it out and sends the traveller's taps back to `AppState`.
///
/// A value type built in `body` from the trip; the day's routing comes from `PlanCache`, so
/// building it again on a redraw costs a dictionary lookup.
struct TripDayViewModel {
    struct DayChip: Identifiable {
        let index: Int
        let title: String
        let isComplete: Bool
        var id: Int { index }
    }

    let index: Int
    let day: TripDay
    let date: Date
    let dateLine: String
    let cityName: String?
    let origin: CLLocationCoordinate2D
    let plan: DayPlan
    let insights: [TripInsight]
    let chips: [DayChip]
    let visitedCount: Int
    let isComplete: Bool
    /// The next day that still has places to see, for the "Day done" card's button.
    let nextOpenDay: Int?
    /// Changes when the day's places or the way between them change, to reload the map routes.
    let routeKey: String

    var hasStops: Bool { !plan.entries.isEmpty }
    var progress: Double { day.stops.isEmpty ? 0 : Double(visitedCount) / Double(day.stops.count) }

    init(trip: Trip, dayIndex: Int, persona: Persona, location: LocationService) {
        // Clamped into the trip's days; an empty trip (not shown by TripView) gets a blank day.
        let index = max(min(dayIndex, trip.days.count - 1), 0)
        let day = trip.days.indices.contains(index) ? trip.days[index] : TripDay()
        let date = trip.date(ofDay: index)
        let city = trip.cityStay(ofDay: index)?.city
        let start = location.dayStart(trip: trip, day: index)

        self.index = index
        self.day = day
        self.date = date
        dateLine = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localizer.shared.locale))
        cityName = trip.cityStay(on: date)?.city.name
        origin = start.coordinate
        plan = PlanCache.shared.dayPlan(day, date: date, origin: start.coordinate, originName: start.name,
                                        style: persona.travelStyle, city: city,
                                        likesWalking: persona.hasTaste("Happy to walk"))
        insights = trip.insights.filter { $0.city == city?.name }
        chips = trip.days.indices.map { DayChip(index: $0, title: L("Day %@", $0 + 1), isComplete: trip.days[$0].isComplete) }
        visitedCount = day.visitedCount
        isComplete = day.isComplete
        nextOpenDay = trip.days.indices.first { $0 > index && !trip.days[$0].isComplete && !trip.days[$0].stops.isEmpty }
            ?? trip.days.indices.first { $0 != index && !trip.days[$0].isComplete && !trip.days[$0].stops.isEmpty }
        routeKey = "\(start.coordinate.latitude),\(start.coordinate.longitude)|" + plan.entries
            .map { "\($0.stop.id)-\($0.leg.best.rawValue)" }.joined(separator: ",")
    }
}
