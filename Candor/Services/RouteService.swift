import Foundation
import CoreLocation

/// Real routes on real roads and rails, for the day map and the leg sheet.
///
/// 1. Google Routes API (`computeRoutes`) with the app's Google key: road paths, and public
///    transport with the actual Metro lines and bus numbers, stops and fares.
/// 2. The straight line, as a last resort, so the map never comes up empty.
enum RouteService {
    private static let endpoint = "https://routes.googleapis.com/directions/v2:computeRoutes"

    /// One ride or walk in a public-transport route: "Bus 534 · 9 stops", "Yellow Line · 6 stops".
    struct TransitStep: Identifiable, Hashable {
        let id = UUID()
        enum Kind: String { case walk, bus, metro, train, other }
        let kind: Kind
        /// "534", "Yellow Line"
        let line: String
        /// Line colour from the operator, when Google has it.
        let lineColorHex: String?
        let headsign: String?
        let from: String?
        let to: String?
        let stops: Int?
        let minutes: Int
        let instruction: String?
        /// Walking distance or ride length, when Google gives it.
        var meters: Int? = nil
    }

    /// A public-transport route from Google.
    struct TransitRoute: Identifiable, Hashable {
        let id = UUID()
        let minutes: Int
        let fare: String?
        let steps: [TransitStep]
        let path: [CLLocationCoordinate2D]

        /// "Bus 534 → Yellow Line"
        var title: String {
            steps.filter { $0.kind != .walk }.map(\.line).joined(separator: " \(Localizer.shared.arrow) ")
        }

        var usesBus: Bool { steps.contains { $0.kind == .bus } }
        var usesMetro: Bool { steps.contains { $0.kind == .metro || $0.kind == .train } }

        static func == (a: TransitRoute, b: TransitRoute) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    // MARK: Paths for the map

    /// The road path between two points for a travel mode. Never empty: falls back to the straight line.
    static func path(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                     mode: TravelMode) async -> [CLLocationCoordinate2D] {
        let key = cacheKey(from, to, mode)
        if let cached = cache[key] { return cached }
        var result: [CLLocationCoordinate2D] = []
        if !GooglePlaces.apiKey.isEmpty {
            if mode.isPublic, let route = try? await transit(from: from, to: to).first {
                result = route.path
            } else {
                result = (try? await googlePath(from: from, to: to, mode: mode)) ?? []
            }
        }
        if result.count < 2 { result = [from, to] }
        // Keep the cache small: a trip's worth of hops, never an ever-growing pile of paths.
        if cache.count >= 80 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }

    private static var cache: [String: [CLLocationCoordinate2D]] = [:]

    private static func cacheKey(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: TravelMode) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f:%@", a.latitude, a.longitude, b.latitude, b.longitude, mode.rawValue)
    }

    private static func googleMode(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: "WALK"
        case .metro, .bus: "TRANSIT"
        case .bikeTaxi: "TWO_WHEELER"
        case .eRickshaw, .auto, .cab, .privateCar: "DRIVE"
        }
    }

    private static func googlePath(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                                   mode: TravelMode) async throws -> [CLLocationCoordinate2D] {
        let body: [String: Any] = [
            "origin": waypoint(from),
            "destination": waypoint(to),
            "travelMode": googleMode(mode)
        ]
        let json = try await post(body, fields: "routes.polyline.encodedPolyline")
        let routes = json["routes"] as? [[String: Any]] ?? []
        guard let encoded = (routes.first?["polyline"] as? [String: Any])?["encodedPolyline"] as? String else { return [] }
        return decodePolyline(encoded)
    }

    // MARK: Public transport

    /// Public-transport routes (Metro, bus, train) leaving around `departure`, best first.
    static func transit(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                        departure: Date = .now) async throws -> [TransitRoute] {
        let time = max(departure, Date.now.addingTimeInterval(60))
        let body: [String: Any] = [
            "origin": waypoint(from),
            "destination": waypoint(to),
            "travelMode": "TRANSIT",
            "computeAlternativeRoutes": true,
            "departureTime": ISO8601DateFormatter().string(from: time),
            "transitPreferences": ["allowedTravelModes": ["BUS", "SUBWAY", "TRAIN", "LIGHT_RAIL", "RAIL"]]
        ]
        let fields = [
            "routes.duration", "routes.polyline.encodedPolyline", "routes.travelAdvisory.transitFare",
            "routes.legs.steps.travelMode", "routes.legs.steps.staticDuration", "routes.legs.steps.distanceMeters",
            "routes.legs.steps.transitDetails", "routes.legs.steps.navigationInstruction.instructions"
        ].joined(separator: ",")
        let json = try await post(body, fields: fields)
        let routes = json["routes"] as? [[String: Any]] ?? []
        return routes.compactMap(parseTransit)
    }

    private static func parseTransit(_ route: [String: Any]) -> TransitRoute? {
        let legs = route["legs"] as? [[String: Any]] ?? []
        var steps: [TransitStep] = []
        for raw in legs.flatMap({ $0["steps"] as? [[String: Any]] ?? [] }) {
            let minutes = max(seconds(raw["staticDuration"]) / 60, 1)
            let meters = raw["distanceMeters"] as? Int
            let instruction = (raw["navigationInstruction"] as? [String: Any])?["instructions"] as? String
            guard let details = raw["transitDetails"] as? [String: Any] else {
                // Merge consecutive walking steps into one.
                if let last = steps.last, last.kind == .walk {
                    steps[steps.count - 1] = TransitStep(kind: .walk, line: last.line, lineColorHex: nil, headsign: nil,
                                                         from: nil, to: nil, stops: nil,
                                                         minutes: last.minutes + minutes, instruction: last.instruction,
                                                         meters: (last.meters ?? 0) + (meters ?? 0))
                } else {
                    steps.append(TransitStep(kind: .walk, line: L("Walk"), lineColorHex: nil, headsign: nil, from: nil,
                                             to: nil, stops: nil, minutes: minutes, instruction: instruction, meters: meters))
                }
                continue
            }
            let line = details["transitLine"] as? [String: Any] ?? [:]
            let vehicle = (line["vehicle"] as? [String: Any])?["type"] as? String ?? ""
            let kind: TransitStep.Kind = switch vehicle {
            case "BUS", "INTERCITY_BUS", "TROLLEYBUS", "SHARE_TAXI": .bus
            case "SUBWAY", "METRO_RAIL", "LIGHT_RAIL", "MONORAIL", "TRAM": .metro
            case "RAIL", "HEAVY_RAIL", "COMMUTER_TRAIN", "HIGH_SPEED_TRAIN", "LONG_DISTANCE_TRAIN": .train
            default: .other
            }
            let name = (line["nameShort"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (line["name"] as? String) ?? L("Public transport")
            let stopDetails = details["stopDetails"] as? [String: Any] ?? [:]
            let fromStop = (stopDetails["departureStop"] as? [String: Any])?["name"] as? String
            let toStop = (stopDetails["arrivalStop"] as? [String: Any])?["name"] as? String
            steps.append(TransitStep(kind: kind,
                                     line: kind == .bus && Int(name.prefix(1)) != nil ? L("Bus %@", name) : name,
                                     lineColorHex: line["color"] as? String,
                                     headsign: details["headsign"] as? String,
                                     from: fromStop, to: toStop,
                                     stops: details["stopCount"] as? Int,
                                     minutes: minutes, instruction: instruction, meters: meters))
        }
        guard steps.contains(where: { $0.kind != .walk }) else { return nil }
        var fare: String?
        if let money = (route["travelAdvisory"] as? [String: Any])?["transitFare"] as? [String: Any],
           let units = money["units"] as? String ?? (money["units"] as? Int).map(String.init) {
            fare = (money["currencyCode"] as? String) == "INR" ? "₹" + units : "\(units) \(money["currencyCode"] as? String ?? "")"
        }
        let encoded = (route["polyline"] as? [String: Any])?["encodedPolyline"] as? String
        return TransitRoute(minutes: max(seconds(route["duration"]) / 60, 1), fare: fare, steps: steps,
                            path: encoded.map(decodePolyline) ?? [])
    }

    // MARK: Plumbing

    private static func waypoint(_ c: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
    }

    /// "1234s" → 1234
    private static func seconds(_ value: Any?) -> Int {
        guard let text = value as? String else { return 0 }
        return Int(Double(text.replacingOccurrences(of: "s", with: "")) ?? 0)
    }

    private static func post(_ body: [String: Any], fields: String) async throws -> [String: Any] {
        let key = GooglePlaces.apiKey
        guard !key.isEmpty, let url = URL(string: endpoint) else { throw GooglePlacesError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        if let bundle = Bundle.main.bundleIdentifier {
            request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
            throw GooglePlacesError.http(status, message)
        }
        return json
    }

    /// Google's encoded polyline format → coordinates.
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0, lat = 0, lng = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = next(), let dLng = next() else { break }
            lat += dLat
            lng += dLng
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return points
    }
}
