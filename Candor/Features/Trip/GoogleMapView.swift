import SwiftUI
import GoogleMaps

/// Google Maps for every map in the app other than the Trip tab's day map (`GoogleTripMap`):
/// markers, route lines, and a camera that frames them or follows one point.
struct GoogleMapView: UIViewRepresentable {
    /// A point on the map, drawn as a coloured disc with a symbol or a number.
    struct Marker: Equatable {
        enum Style: Equatable {
            /// The traveller: a pulsing-style blue dot.
            case you
            /// A disc in `color` with an SF Symbol.
            case symbol(String, UIColor)
            /// A disc in `color` with a number.
            case number(Int, UIColor)
            /// Google's own red pin.
            case pin(UIColor)
        }

        let id: String
        let latitude: Double
        let longitude: Double
        var title: String = ""
        var style: Style

        init(id: String? = nil, _ coordinate: CLLocationCoordinate2D, title: String = "", style: Style) {
            self.id = id ?? "\(coordinate.latitude),\(coordinate.longitude)"
            latitude = coordinate.latitude
            longitude = coordinate.longitude
            self.title = title
            self.style = style
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// A route on the map, with an optional white casing so it reads on any background.
    struct Line: Equatable {
        let latitudes: [Double]
        let longitudes: [Double]
        var color: UIColor
        var width: CGFloat = 4.5
        var dashed = false
        var casing = true

        init(_ coordinates: [CLLocationCoordinate2D], color: UIColor, width: CGFloat = 4.5,
             dashed: Bool = false, casing: Bool = true) {
            latitudes = coordinates.map(\.latitude)
            longitudes = coordinates.map(\.longitude)
            self.color = color
            self.width = width
            self.dashed = dashed
            self.casing = casing
        }

        var coordinates: [CLLocationCoordinate2D] {
            zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        }
    }

    /// Where the camera looks.
    enum Camera: Equatable {
        /// Frame every marker and line.
        case fit
        /// Centre on a point, optionally tilted and turned for a 3D look.
        case focus(latitude: Double, longitude: Double, zoom: Float, bearing: Double = 0, tilt: Double = 0)
        /// A fixed area that the traveller moves around themselves.
        case region(latitude: Double, longitude: Double, zoom: Float)
    }

    var markers: [Marker] = []
    var lines: [Line] = []
    var camera: Camera = .fit
    /// Room kept clear of the map's content and Google logo, e.g. for a panel over the bottom of the map.
    var insets: UIEdgeInsets = .zero
    /// Room around fitted content, inside `insets`.
    var padding = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
    var interactive = true
    var showsTraffic = false
    var showsBuildings = false
    var showsMyLocation = false
    var onSelect: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        let start = markers.first?.coordinate ?? City.delhi.coordinate
        options.camera = GMSCameraPosition(latitude: start.latitude, longitude: start.longitude, zoom: 13)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.settings.compassButton = interactive
        map.settings.setAllGesturesEnabled(interactive)
        map.mapStyle = try? GMSMapStyle(jsonString: Self.quietStyle)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        map.isTrafficEnabled = showsTraffic
        map.isBuildingsEnabled = showsBuildings
        map.isMyLocationEnabled = showsMyLocation
        map.settings.myLocationButton = showsMyLocation && interactive
        map.padding = insets

        let contentChanged = coordinator.markers != markers || coordinator.lines != lines
        if contentChanged {
            coordinator.markers = markers
            coordinator.lines = lines
            render(on: map)
        }
        if contentChanged || coordinator.camera != camera {
            let animated = coordinator.camera != nil && coordinator.camera != camera
            coordinator.camera = camera
            // Wait a beat so the view has its size before framing.
            DispatchQueue.main.async { move(map, animated: animated) }
        }
    }

    private func render(on map: GMSMapView) {
        map.clear()
        for line in lines where line.latitudes.count > 1 {
            let path = GMSMutablePath()
            line.coordinates.forEach { path.add($0) }
            if line.casing {
                let casing = GMSPolyline(path: path)
                casing.strokeWidth = line.width + 3
                casing.strokeColor = .white
                casing.map = map
            }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = line.width
            polyline.strokeColor = line.color
            if line.dashed {
                polyline.spans = GMSStyleSpans(path, [GMSStrokeStyle.solidColor(line.color), GMSStrokeStyle.solidColor(.clear)],
                                               [12, 10], .rhumb)
            }
            polyline.map = map
        }
        for item in markers {
            let marker = GMSMarker(position: item.coordinate)
            marker.title = item.title.isEmpty ? nil : item.title
            marker.userData = item.id
            switch item.style {
            case .pin(let color):
                marker.icon = GMSMarker.markerImage(with: color)
            default:
                marker.icon = Self.icon(for: item.style)
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            }
            marker.map = map
        }
    }

    private func move(_ map: GMSMapView, animated: Bool) {
        let update: GMSCameraUpdate
        switch camera {
        case .fit:
            let path = GMSMutablePath()
            markers.forEach { path.add($0.coordinate) }
            lines.forEach { $0.coordinates.forEach { path.add($0) } }
            guard path.count() > 0 else { return }
            if path.count() == 1, let only = markers.first {
                update = GMSCameraUpdate.setTarget(only.coordinate, zoom: 15)
            } else {
                update = GMSCameraUpdate.fit(GMSCoordinateBounds(path: path), with: padding)
            }
        case .focus(let latitude, let longitude, let zoom, let bearing, let tilt):
            update = GMSCameraUpdate.setCamera(GMSCameraPosition(latitude: latitude, longitude: longitude,
                                                                 zoom: zoom, bearing: bearing, viewingAngle: tilt))
        case .region(let latitude, let longitude, let zoom):
            update = GMSCameraUpdate.setTarget(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoom: zoom)
        }
        if animated { map.animate(with: update) } else { map.moveCamera(update) }
    }

    /// Hide Google's own points of interest and transit icons, so Candor's markers stand out.
    static let quietStyle = """
    [{"featureType":"poi","stylers":[{"visibility":"off"}]},
     {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]
    """

    private static func icon(for style: Marker.Style) -> UIImage {
        let size = CGSize(width: 34, height: 34)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let fill: UIColor
            switch style {
            case .you: fill = .systemBlue
            case .symbol(_, let color), .number(_, let color), .pin(let color): fill = color
            }
            let disc = UIBezierPath(ovalIn: style == .you ? rect.insetBy(dx: 7, dy: 7) : rect)
            if style == .you {
                UIColor.systemBlue.withAlphaComponent(0.2).setFill()
                UIBezierPath(ovalIn: rect).fill()
            }
            fill.setFill()
            disc.fill()
            UIColor.white.setStroke()
            disc.lineWidth = style == .you ? 3 : 2.5
            disc.stroke()

            switch style {
            case .number(let number, _):
                let text = "\(number)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                          withAttributes: attributes)
            case .symbol(let name, _):
                if let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
                }
            case .you, .pin:
                break
            }
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var markers: [Marker] = []
        var lines: [Line] = []
        var camera: Camera?
        var onSelect: ((String) -> Void)?

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String, let onSelect {
                onSelect(id)
                return true
            }
            return false
        }
    }
}

extension CLLocationCoordinate2D {
    /// Road length along a path, in metres.
    static func length(of path: [CLLocationCoordinate2D]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { total, hop in
            total + CLLocation(latitude: hop.0.latitude, longitude: hop.0.longitude)
                .distance(from: CLLocation(latitude: hop.1.latitude, longitude: hop.1.longitude))
        }
    }
}

/// Opens directions in the Google Maps app, or on google.com/maps when the app isn't installed.
enum GoogleMapsLink {
    static func directions(to coordinate: CLLocationCoordinate2D, mode: TravelMode) -> URL? {
        let travel: String = switch mode {
        case .walk: "walking"
        case .metro, .bus: "transit"
        case .bikeTaxi: "two-wheeler"
        case .auto, .cab, .eRickshaw, .privateCar: "driving"
        }
        let destination = "\(coordinate.latitude),\(coordinate.longitude)"
        if let app = URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=\(travel == "two-wheeler" ? "driving" : travel)"),
           UIApplication.shared.canOpenURL(app) {
            return app
        }
        return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(destination)&travelmode=\(travel)")
    }

    static func place(_ coordinate: CLLocationCoordinate2D) -> URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(coordinate.latitude),\(coordinate.longitude)")
    }
}
