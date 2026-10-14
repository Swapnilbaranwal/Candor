import SwiftUI
import MapKit

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
/// in the project (see README), otherwise Apple Maps' realistic 3D.
struct Trip3DMapView: View {
    let title: String
    let stops: [DayMapStop]
    let routes: [DayRoute]
    @Environment(\.dismiss) private var dismiss
    @State private var focus: UUID?
    /// Google's photoreal 3D needs "Maps 3D SDK for iOS" on the key. If it can't load, the
    /// traveller flips to Apple's 3D here, and the choice is remembered.
    @AppStorage("candor.use3DProvider") private var provider = "google"

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
                        Text(verbatim: "Google 3D").tag("google")
                        Text(verbatim: "Apple 3D").tag("apple")
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
            Apple3DDayMap(stops: stops, routes: routes, focus: focused)
        }
        #else
        Apple3DDayMap(stops: stops, routes: routes, focus: focused)
        #endif
    }
}

// MARK: - Apple Maps 3D

/// Apple Maps with realistic elevation and buildings, pitched like a drone shot.
private struct Apple3DDayMap: View {
    let stops: [DayMapStop]
    let routes: [DayRoute]
    let focus: DayMapStop?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(routes) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.mode.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Group {
                        if let number = stop.number {
                            Text("\(number)").font(.candor(.subheadline, .bold))
                        } else {
                            Image(systemName: "location.fill").font(.candor(.caption1, .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(stop.number == nil ? AnyShapeStyle(Theme.teal)
                                : (stop.visited ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Theme.brandFill)), in: .circle)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapPitchToggle()
        }
        .onAppear { fly(to: focus, animated: false) }
        .onChange(of: focus?.id) { _, _ in fly(to: focus, animated: true) }
    }

    private func fly(to stop: DayMapStop?, animated: Bool) {
        guard let stop else { return }
        let camera = MapCamera(centerCoordinate: stop.coordinate, distance: 900, heading: 35, pitch: 65)
        if animated {
            withAnimation(.easeInOut(duration: 1.6)) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }
}
