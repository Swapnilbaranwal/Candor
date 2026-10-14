import SwiftUI
import GoogleMaps

/// Google Maps for the Trip tab: where the day starts, numbered stops, and a dashed line between them.
/// Needs a key with "Maps SDK for iOS" enabled (`GoogleMapsSetup`); TripView falls back to Apple Maps without one.
struct GoogleTripMap: UIViewRepresentable {
    struct Pin: Equatable {
        let latitude: Double
        let longitude: Double
        let title: String
        /// Stop number, or nil for the day's start.
        let number: Int?
        /// Ticked off as visited: drawn in green.
        var visited = false

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// A hop on real roads, in its travel mode's colour.
    struct Line: Equatable {
        let latitudes: [Double]
        let longitudes: [Double]
        let color: UIColor
    }

    /// The start first, then the stops in visiting order.
    let pins: [Pin]
    /// Real routes between them. Empty until they load: then a dashed straight line stands in.
    var lines: [Line] = []

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        let first = pins.first?.coordinate ?? City.delhi.coordinate
        options.camera = GMSCameraPosition(latitude: first.latitude, longitude: first.longitude, zoom: 12)
        let map = GMSMapView(options: options)
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        map.settings.compassButton = false
        map.isBuildingsEnabled = false
        // Hide Google's own points of interest and transit icons, so the day's stops stand out.
        map.mapStyle = try? GMSMapStyle(jsonString: """
        [{"featureType":"poi","stylers":[{"visibility":"off"}]},
         {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]
        """)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        guard context.coordinator.pins != pins || context.coordinator.lines != lines else { return }
        context.coordinator.pins = pins
        context.coordinator.lines = lines
        render(on: map)
    }

    private func render(on map: GMSMapView) {
        map.clear()
        guard !pins.isEmpty else { return }

        let path = GMSMutablePath()
        pins.forEach { path.add($0.coordinate) }

        if lines.isEmpty {
            let line = GMSPolyline(path: path)
            line.strokeWidth = 3
            line.spans = GMSStyleSpans(path,
                                       [GMSStrokeStyle.solidColor(UIColor(Theme.accent)), GMSStrokeStyle.solidColor(.clear)],
                                       [180, 120],
                                       .rhumb)
            line.map = map
        } else {
            for route in lines {
                let routePath = GMSMutablePath()
                for (lat, lng) in zip(route.latitudes, route.longitudes) {
                    routePath.add(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    path.add(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                }
                let casing = GMSPolyline(path: routePath)
                casing.strokeWidth = 7
                casing.strokeColor = .white
                casing.map = map
                let line = GMSPolyline(path: routePath)
                line.strokeWidth = 4
                line.strokeColor = route.color
                line.map = map
            }
        }

        for pin in pins {
            let marker = GMSMarker(position: pin.coordinate)
            marker.title = pin.title
            marker.icon = Self.icon(for: pin)
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.zIndex = pin.number.map { Int32($0) } ?? 0
            marker.map = map
        }

        // Fit once the view has its size.
        DispatchQueue.main.async {
            if pins.count == 1 {
                map.moveCamera(GMSCameraUpdate.setTarget(pins[0].coordinate, zoom: 14))
            } else {
                map.moveCamera(GMSCameraUpdate.fit(GMSCoordinateBounds(path: path), withPadding: 36))
            }
        }
    }

    /// A numbered disc for a stop, or the location arrow for the start.
    private static func icon(for pin: Pin) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let disc = UIBezierPath(ovalIn: rect)
            UIColor(pin.number == nil ? Theme.teal : (pin.visited ? Theme.mint : Theme.accent)).setFill()
            disc.fill()
            UIColor.white.setStroke()
            disc.lineWidth = 2
            disc.stroke()

            if let number = pin.number {
                let text = "\(number)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                          withAttributes: attributes)
            } else if let arrow = UIImage(systemName: "location.fill",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                arrow.draw(at: CGPoint(x: (size.width - arrow.size.width) / 2, y: (size.height - arrow.size.height) / 2))
            }
        }
    }

    final class Coordinator {
        var pins: [Pin] = []
        var lines: [Line] = []
    }
}

/// Starts the Google Maps SDK with the app's Google key, once, at launch.
enum GoogleMapsSetup {
    private(set) static var isReady = false

    static func start() {
        let key = GooglePlaces.apiKey
        guard !key.isEmpty, !isReady else { return }
        isReady = GMSServices.provideAPIKey(key)
        Google3DSetup.start(key: key)
    }
}
