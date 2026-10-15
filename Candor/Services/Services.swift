import SwiftUI
import CoreLocation
import AVFoundation

// MARK: - Currency

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}

/// Converts INR into the traveller's home currency. Starts with indicative fallback
/// rates and refreshes from the ECB-based Frankfurter API when online.
@Observable
final class CurrencyService {
    var inrPerUnit: [String: Double]
    var lastUpdated: Date?
    var isLive = false

    init() {
        var rates: [String: Double] = [:]
        for option in CurrencyOption.all { rates[option.code] = option.fallbackINR }
        inrPerUnit = rates
    }

    func convert(inr: Double, to code: String) -> Double? {
        guard let rate = inrPerUnit[code], rate > 0 else { return nil }
        return inr / rate
    }

    func toINR(_ amount: Double, from code: String) -> Double? {
        guard let rate = inrPerUnit[code], rate > 0 else { return nil }
        return amount * rate
    }

    func format(inr: Double, in code: String) -> String {
        guard let value = convert(inr: inr, to: code) else { return "" }
        return Self.format(value, code: code)
    }

    static func format(_ value: Double, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(value < 10 ? 2 : 0)))
    }

    func refresh() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=INR") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            var updated = inrPerUnit
            for (code, perINR) in response.rates where perINR > 0 {
                updated[code] = 1 / perINR
            }
            inrPerUnit = updated
            lastUpdated = .now
            isLive = true
        } catch {
            // Keep fallback rates.
        }
    }
}

// MARK: - Location

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var status: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Only tell the app when the traveller has really moved. Every GPS tick used to redraw
        // Home, Trip and the tab bar's way-home line about once a second.
        manager.distanceFilter = 60
        status = manager.authorizationStatus
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    /// True when the device is actually in the Delhi region.
    var isInDelhi: Bool {
        guard let location else { return false }
        let center = CLLocation(latitude: DelhiData.center.latitude, longitude: DelhiData.center.longitude)
        return location.distance(from: center) < 60_000
    }

    /// Where ride distances are measured from. Falls back to Connaught Place
    /// outside Delhi (e.g. in the Simulator) so the demo still works.
    var origin: CLLocationCoordinate2D {
        isInDelhi ? (location?.coordinate ?? DelhiData.connaughtPlace) : DelhiData.connaughtPlace
    }

    var originName: String {
        isInDelhi ? L("Your location") : L("Connaught Place (demo)")
    }

    var placeLabel: String {
        guard isInDelhi, let location else { return L("New Delhi · demo location") }
        let nearest = DelhiData.spots.min { a, b in
            location.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude)) <
            location.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        if let nearest {
            let meters = location.distance(from: CLLocation(latitude: nearest.latitude, longitude: nearest.longitude))
            if meters < 3_000 { return L("Near %@", L(nearest.name)) }
        }
        return L("New Delhi")
    }

    func distanceKm(to coordinate: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return from.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1000
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            if let current = self.location, current.distance(from: latest) < 40 { return }
            self.location = latest
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
        Task { @MainActor in
            self.status = newStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Routing

enum Routing {
    struct RouteInfo {
        let name: String
        let km: Double
        let coordinate: CLLocationCoordinate2D
    }

    /// Google Maps places matching `query` around `origin`.
    static func search(_ query: String, near origin: CLLocationCoordinate2D) async -> [GooglePlace] {
        (try? await GooglePlaces.search(query, near: origin)) ?? []
    }

    /// Resolves a place name (known spots first, then Google Maps search) and measures the drive.
    static func distance(to query: String, from origin: CLLocationCoordinate2D) async -> RouteInfo? {
        if let spot = DelhiData.spot(matching: query) {
            return await distance(to: spot.coordinate, name: spot.name, from: origin)
        }
        guard let place = await search(query, near: origin).first else { return nil }
        return await distance(to: place, from: origin)
    }

    static func distance(to place: GooglePlace, from origin: CLLocationCoordinate2D) async -> RouteInfo? {
        await distance(to: place.coordinate, name: place.name, from: origin)
    }

    /// The drive by road, from Google's route. Offline: straight line × 1.3 road factor.
    static func distance(to coordinate: CLLocationCoordinate2D, name: String, from origin: CLLocationCoordinate2D) async -> RouteInfo? {
        let path = await RouteService.path(from: origin, to: coordinate, mode: .cab)
        let meters = CLLocationCoordinate2D.length(of: path)
        let km = path.count > 2 ? meters / 1000 : meters / 1000 * 1.3
        return RouteInfo(name: name, km: km, coordinate: coordinate)
    }
}

// MARK: - Speech

final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "hi-IN") {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.45
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

// MARK: - Images

extension UIImage {
    /// Downscales so the longest side is at most `maxDimension` points (keeps Gemini payloads small).
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
