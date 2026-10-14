import Foundation
import CoreLocation
import UIKit

/// Remembers recent day plans and legs so the routing and fare maths runs once per change,
/// not on every redraw (a GPS tick, a sheet opening, a scroll that re-renders a card).
///
/// Small and bounded: it keeps the last few results, drops the oldest first, and empties
/// itself when iOS warns about memory.
final class PlanCache {
    static let shared = PlanCache()

    private struct PlanKey: Hashable {
        let day: TripDay
        let date: Date
        let origin: GridPoint
        let originName: String
        let style: TravelStyle
        let cityID: String?
        let likesWalking: Bool
    }

    private struct LegKey: Hashable {
        let origin: GridPoint
        let originName: String
        /// The place, not the stop record: a landmark rebuilt with a fresh id still hits.
        let stopName: String
        let spotID: String?
        let destination: GridPoint
        let quarterHour: Int
        let style: TravelStyle
        let cityID: String?
        let likesWalking: Bool
    }

    /// A coordinate snapped to about 100 m, so GPS jitter doesn't redo the plan.
    private struct GridPoint: Hashable {
        let lat: Int
        let lon: Int
        init(_ c: CLLocationCoordinate2D) {
            lat = Int((c.latitude * 1000).rounded())
            lon = Int((c.longitude * 1000).rounded())
        }
    }

    private var plans = BoundedStore<PlanKey, DayPlan>(limit: 12)
    private var legs = BoundedStore<LegKey, Leg>(limit: 24)
    private var memoryObserver: NSObjectProtocol?

    private init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    func removeAll() {
        plans.removeAll()
        legs.removeAll()
    }

    func dayPlan(_ day: TripDay, date: Date, origin: CLLocationCoordinate2D, originName: String,
                 style: TravelStyle, city: City?, likesWalking: Bool) -> DayPlan {
        let key = PlanKey(day: day, date: date, origin: GridPoint(origin), originName: originName,
                          style: style, cityID: city?.id, likesWalking: likesWalking)
        if let hit = plans[key] { return hit }
        let plan = TripPlanner.dayPlan(day, date: date, origin: origin, originName: originName,
                                       style: style, city: city, likesWalking: likesWalking)
        plans[key] = plan
        return plan
    }

    func leg(from origin: CLLocationCoordinate2D, fromName: String, to stop: TripStop, at time: Date,
             style: TravelStyle, city: City?, likesWalking: Bool) -> Leg {
        let key = LegKey(origin: GridPoint(origin), originName: fromName, stopName: stop.name,
                         spotID: stop.spotID, destination: GridPoint(stop.coordinate),
                         quarterHour: Int(time.timeIntervalSinceReferenceDate / 900),
                         style: style, cityID: city?.id, likesWalking: likesWalking)
        if let hit = legs[key] { return hit }
        let leg = TripPlanner.leg(from: origin, fromName: fromName, to: stop, at: time,
                                  style: style, city: city, likesWalking: likesWalking)
        legs[key] = leg
        return leg
    }
}

/// A dictionary that forgets its oldest entry once it holds `limit` of them.
struct BoundedStore<Key: Hashable, Value> {
    let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) { self.limit = limit }

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let newValue else {
                values[key] = nil
                order.removeAll { $0 == key }
                return
            }
            if values.updateValue(newValue, forKey: key) == nil {
                order.append(key)
                if order.count > limit {
                    values[order.removeFirst()] = nil
                }
            }
        }
    }

    mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
