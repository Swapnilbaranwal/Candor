import SwiftUI
import CoreLocation
#if canImport(GoogleMaps3D)
import GoogleMaps3D
#endif

// Kept in its own file: GoogleMaps3D and MapKit both declare a SwiftUI `Map`.

/// Gives the Maps 3D SDK the app's Google key (it needs "Maps 3D SDK for iOS" enabled on the key).
enum Google3DSetup {
    static func start(key: String) {
        #if canImport(GoogleMaps3D)
        GoogleMaps3D.Map.apiKey = key
        #endif
    }
}

// MARK: - Google Maps 3D

#if canImport(GoogleMaps3D)
/// Google's photorealistic 3D city with the day's route clamped to the ground and a marker per stop.
struct Google3DDayMap: View {
    let stops: [DayMapStop]
    let routes: [DayRoute]
    let focus: DayMapStop?
    @State private var camera: GoogleMaps3D.Camera
    @State private var target: GoogleMaps3D.Camera
    @State private var flights = 0

    init(stops: [DayMapStop], routes: [DayRoute], focus: DayMapStop?) {
        self.stops = stops
        self.routes = routes
        self.focus = focus
        let start = Self.camera(for: focus?.coordinate ?? City.delhi.coordinate)
        _camera = State(initialValue: start)
        _target = State(initialValue: start)
    }

    static func camera(for coordinate: CLLocationCoordinate2D) -> GoogleMaps3D.Camera {
        GoogleMaps3D.Camera(center: LatLngAltitude(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0),
                            heading: 35, tilt: 65, roll: 0, range: 1200, altitudeMode: .relativeToGround)
    }

    var body: some View {
        GoogleMaps3D.Map(camera: $camera, mode: .hybrid) {
            ForEach(routes) { route in
                Polyline(path: route.coordinates.map { LatLngAltitude(latitude: $0.latitude, longitude: $0.longitude, altitude: 0) },
                         altitudeMode: .clampToGround)
                    .stroke(Polyline.StrokeStyle(strokeColor: UIColor(route.mode.color), strokeWidth: 9,
                                                 outerColor: .white, outerWidth: 0.3))
            }
            ForEach(stops) { stop in
                Marker3D(position: LatLngAltitude(latitude: stop.coordinate.latitude,
                                                  longitude: stop.coordinate.longitude, altitude: 40),
                         altitudeMode: .relativeToGround,
                         collisionBehavior: .required,
                         extruded: true,
                         drawsWhenOccluded: true,
                         sizePreserved: true,
                         label: stop.number.map { "\($0) · \(stop.name)" } ?? stop.name)
            }
        }
        .flyCameraTo(target, duration: 2.5, trigger: flights, completion: {})
        .onChange(of: focus?.id) { _, _ in
            guard let focus else { return }
            target = Self.camera(for: focus.coordinate)
            flights += 1
        }
    }
}
#endif
