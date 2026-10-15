import SwiftUI
import CoreLocation

/// One hop of the day on real roads or rails, coloured by how you travel it.
struct DayRoute: Identifiable {
    let id: UUID
    let mode: TravelMode
    let coordinates: [CLLocationCoordinate2D]
}

/// A point on the day map: the start (no number) or a numbered stop.
struct DayMapStop: Identifiable {
    let id: UUID
    let number: Int?
    let name: String
    let coordinate: CLLocationCoordinate2D
    var visited = false
}

/// The day in 3D: photorealistic city, the route on real roads, a marker per stop, and a card
/// strip to fly from stop to stop. Uses Google's Maps 3D SDK when the `GoogleMaps3D` package is
/// in the project (see README), otherwise Google Maps tilted with 3D buildings.
struct Trip3DMapView: View {
    let title: String
    let stops: [DayMapStop]
    let routes: [DayRoute]
    @Environment(\.dismiss) private var dismiss
    @State private var focus: UUID?
    /// Google's photoreal 3D needs "Maps 3D SDK for iOS" on the key. If it can't load, the
    /// traveller flips to Google Maps' tilted 3D buildings here, and the choice is remembered.
    @AppStorage("candor.google3DStyle") private var provider = "google"

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.heading(.headline)).lineLimit(1)
                    Text(L("%@ stops in 3D", stops.filter { $0.number != nil }.count))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: .capsule)
                Spacer()
                #if canImport(GoogleMaps3D)
                Menu {
                    Picker(L("3D map"), selection: $provider) {
                        Text(L("Photoreal 3D")).tag("google")
                        Text(L("3D buildings")).tag("buildings")
                    }
                } label: {
                    CircleIcon(systemName: "map", size: 44)
                }
                .accessibilityLabel(L("3D map"))
                #endif
                Button { dismiss() } label: {
                    CircleIcon(systemName: "xmark", size: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(L("Close"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { stopStrip }
    }

    // MARK: Stops

    private var stopStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stops) { stop in
                    Button { focus = stop.id } label: {
                        HStack(spacing: 10) {
                            Group {
                                if let number = stop.number {
                                    Text("\(number)").font(.candor(.subheadline, .bold))
                                } else {
                                    Image(systemName: "location.fill").font(.candor(.caption1, .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(stop.number == nil ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(Theme.brandFill), in: .circle)
                            Text(stop.name)
                                .font(.candor(.subheadline, .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .overlay {
                            if focus == stop.id { Capsule().strokeBorder(Theme.ink, lineWidth: 2) }
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var focused: DayMapStop? {
        stops.first { $0.id == focus } ?? stops.first
    }

    // MARK: Map

    @ViewBuilder
    private var map: some View {
        #if canImport(GoogleMaps3D)
        if !GooglePlaces.apiKey.isEmpty && provider == "google" {
            Google3DDayMap(stops: stops, routes: routes, focus: focused)
        } else {
            GoogleTiltedDayMap(stops: stops, routes: routes, focus: focused)
        }
        #else
        GoogleTiltedDayMap(stops: stops, routes: routes, focus: focused)
        #endif
    }
}

// MARK: - Google Maps, tilted

/// Google Maps pitched like a drone shot, with 3D buildings, for keys without photoreal 3D.
private struct GoogleTiltedDayMap: View {
    let stops: [DayMapStop]
    let routes: [DayRoute]
    let focus: DayMapStop?

    var body: some View {
        GoogleMapView(
            markers: stops.map { stop in
                let color = UIColor(stop.number == nil ? Theme.teal : (stop.visited ? Theme.mint : Theme.accent))
                return .init(id: stop.id.uuidString, stop.coordinate, title: stop.name,
                             style: stop.number.map { .number($0, color) } ?? .symbol("location.fill", color))
            },
            lines: routes.map { .init($0.coordinates, color: UIColor($0.mode.color), width: 5) },
            camera: focus.map { .focus(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                       zoom: 17, bearing: 35, tilt: 60) } ?? .fit,
            insets: UIEdgeInsets(top: 0, left: 0, bottom: 90, right: 0),
            showsBuildings: true
        )
    }
}
