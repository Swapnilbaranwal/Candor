import Foundation
import CoreLocation

/// A place found with Google Maps.
struct GooglePlace: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    /// The area Google suggests for showing the place; set for cities.
    var viewport: City.Bounds?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum GooglePlacesError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: L("Google Maps search isn't set up yet.")
        case .http(let code, let message): "Google Maps error \(code): \(message)"
        }
    }
}

/// Google Maps place search (Places API (New), Text Search).
///
/// With the Cloud Run backend set up, requests go through it (`Backend.geminiProxy`), which holds
/// the Maps key on the server. Otherwise they go straight to Google with a development key: the
/// `GOOGLE_MAPS_API_KEY` build setting (read from Info.plist), or `-candor.googleMapsKey <key>` at launch.
enum GooglePlaces {
    private static let placesAPI = "https://places.googleapis.com"
    private static let fieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.viewport"

    static var apiKey: String {
        let override = UserDefaults.standard.string(forKey: "candor.googleMapsKey") ?? ""
        let bundled = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String ?? ""
        let key = (override.isEmpty ? bundled : override).trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can come through as the literal "$(GOOGLE_MAPS_API_KEY)".
        return key.hasPrefix("$(") ? "" : key
    }

    static var isConfigured: Bool { !apiKey.isEmpty || Backend.geminiProxy != nil }

    /// Places in `city` matching `query`. Results are restricted to the city's area, so "Imperial"
    /// in Delhi finds the hotel on Janpath and not one in Mumbai.
    /// `reachKm` widens the area, for planned sights that can sit outside town (Fatehpur Sikri from Agra).
    static func search(_ query: String, in city: City = .delhi, reachKm: Double = 0) async throws -> [GooglePlace] {
        let area = reachKm > 0 ? city.bounds.expanded(by: reachKm) : city.bounds
        let bounds: [String: Any] = [
            "rectangle": [
                "low": ["latitude": area.lowLatitude, "longitude": area.lowLongitude],
                "high": ["latitude": area.highLatitude, "longitude": area.highLongitude]
            ]
        ]
        return try await textSearch(["textQuery": query, "maxResultCount": 6, "locationRestriction": bounds])
    }

    /// Cities and towns anywhere matching `query`, as destinations. Candor's verified cities keep
    /// their own ids, so "Delhi" from Google comes back as Candor's Delhi.
    static func searchCities(_ query: String) async throws -> [City] {
        let places = try await textSearch(["textQuery": query, "maxResultCount": 6,
                                           "includedType": "locality", "strictTypeFiltering": true])
        return places.map { place in
            let parts = (place.address ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let country = parts.count > 1 ? parts.last ?? "" : ""
            if let known = City.featured.first(where: { $0.name.caseInsensitiveCompare(place.name) == .orderedSame && country == $0.country }) {
                return known
            }
            let bounds = place.viewport ?? .around(latitude: place.latitude, longitude: place.longitude)
            return City(id: place.id, name: place.name, country: country,
                        latitude: place.latitude, longitude: place.longitude, bounds: bounds, coverage: .ai)
        }
    }

    private static func textSearch(_ parameters: [String: Any]) async throws -> [GooglePlace] {
        let key = apiKey
        let base: String
        if !key.isEmpty {
            base = placesAPI
        } else if let proxy = Backend.geminiProxy {
            base = proxy
        } else {
            throw GooglePlacesError.notConfigured
        }
        guard let url = URL(string: "\(base)/v1/places:searchText") else { throw GooglePlacesError.notConfigured }

        var body = parameters
        body["languageCode"] = Localizer.shared.language
        body["regionCode"] = "IN"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
            throw GooglePlacesError.http(status, message)
        }

        let places = json["places"] as? [[String: Any]] ?? []
        return places.compactMap { place in
            guard let id = place["id"] as? String,
                  let location = place["location"] as? [String: Any],
                  let latitude = location["latitude"] as? Double,
                  let longitude = location["longitude"] as? Double else { return nil }
            let name = (place["displayName"] as? [String: Any])?["text"] as? String
            var viewport: City.Bounds?
            if let box = place["viewport"] as? [String: Any],
               let low = box["low"] as? [String: Any], let high = box["high"] as? [String: Any],
               let lowLat = low["latitude"] as? Double, let lowLon = low["longitude"] as? Double,
               let highLat = high["latitude"] as? Double, let highLon = high["longitude"] as? Double {
                viewport = City.Bounds(lowLatitude: lowLat, lowLongitude: lowLon, highLatitude: highLat, highLongitude: highLon)
            }
            return GooglePlace(id: id, name: name ?? (parameters["textQuery"] as? String ?? ""),
                               address: place["formattedAddress"] as? String,
                               latitude: latitude, longitude: longitude, viewport: viewport)
        }
    }
}
