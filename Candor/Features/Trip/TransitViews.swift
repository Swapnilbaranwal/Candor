import SwiftUI
import CoreLocation

/// Live public transport between two places, from Google: Metro lines, bus numbers, stops,
/// times and fares. Shown in the leg sheet under Candor's own options.
struct LiveTransitSection: View {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    var departure: Date = .now

    private enum Load { case loading, loaded([RouteService.TransitRoute]), failed(String) }
    @State private var load: Load = .loading
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SoftIcon(symbol: "bus.doubledecker.fill", tint: TravelMode.bus.color, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Metro and bus routes")).font(.heading(.headline))
                    Text(L("Live from Google Maps · leaving now")).font(.candor(.caption1)).foregroundStyle(.secondary)
                }
            }

            switch load {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L("Finding buses and trains…")).font(.candor(.subheadline)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            case .failed(let message):
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            case .loaded(let routes):
                if routes.isEmpty {
                    Label(L("No public transport found for this hop right now."), systemImage: "info.circle")
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                ForEach(routes.prefix(4)) { route in
                    routeCard(route)
                }
            }
        }
        .card(padding: 16)
        .task { await fetch() }
        .animation(.snappy, value: expanded)
    }

    private func fetch() async {
        guard !GooglePlaces.apiKey.isEmpty else {
            load = .failed(L("Add a Google Maps key with the Routes API to see live buses and trains."))
            return
        }
        do {
            load = .loaded(try await RouteService.transit(from: from, to: to, departure: departure))
        } catch {
            load = .failed(L("Live routes aren't available right now. Candor's estimates above still apply."))
        }
    }

    private func routeCard(_ route: RouteService.TransitRoute) -> some View {
        let open = expanded == route.id
        return VStack(alignment: .leading, spacing: 10) {
            Button { expanded = open ? nil : route.id } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(durationText(route.minutes))
                            .font(.candor(.headline, .bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        if let fare = route.fare {
                            Text(fare)
                                .font(.candor(.subheadline, .semibold))
                                .foregroundStyle(Theme.mint)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.candor(.caption1, .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(route.steps.enumerated()), id: \.element.id) { index, step in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                TransitChip(step: step)
                            }
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(route.steps) { step in
                        stepRow(step)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func stepRow(_ step: RouteService.TransitStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: TransitChip.icon(step.kind))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(TransitChip.color(step), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                if step.kind == .walk {
                    Text(L("Walk %@", durationText(step.minutes))).font(.candor(.subheadline, .semibold))
                    if let instruction = step.instruction {
                        Text(instruction).font(.candor(.caption1)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(step.line + (step.headsign.map { " · " + L("towards %@", $0) } ?? ""))
                        .font(.candor(.subheadline, .semibold))
                    if let from = step.from {
                        Text(L("Board at %@", from)).font(.candor(.caption1)).foregroundStyle(.secondary)
                    }
                    if let to = step.to {
                        Text(L("Get off at %@", to) + (step.stops.map { " · " + L("%@ stops", $0) } ?? ""))
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(durationText(step.minutes))
                .font(.candor(.caption1).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A small capsule for one part of a transit route: icon and line ("534", "Yellow Line").
struct TransitChip: View {
    let step: RouteService.TransitStep

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.icon(step.kind)).font(.system(size: 11, weight: .bold))
            if step.kind == .walk {
                Text(durationText(step.minutes))
            } else {
                Text(step.line).lineLimit(1)
            }
        }
        .font(.candor(.caption1, .semibold))
        .foregroundStyle(step.kind == .walk ? Color.secondary : Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(step.kind == .walk ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Self.color(step)), in: .capsule)
    }

    static func icon(_ kind: RouteService.TransitStep.Kind) -> String {
        switch kind {
        case .walk: "figure.walk"
        case .bus: "bus.fill"
        case .metro: "tram.fill"
        case .train: "train.side.front.car"
        case .other: "arrow.triangle.swap"
        }
    }

    static func color(_ step: RouteService.TransitStep) -> Color {
        if let hex = step.lineColorHex?.replacingOccurrences(of: "#", with: ""), let value = UInt32(hex, radix: 16) {
            let r = Double(value >> 16 & 0xFF), g = Double(value >> 8 & 0xFF), b = Double(value & 0xFF)
            // Keep the operator's colour unless it's too pale for white text.
            if 0.299 * r + 0.587 * g + 0.114 * b < 215 { return Color(hex: value) }
        }
        switch step.kind {
        case .walk: return Theme.mint
        case .bus: return TravelMode.bus.color
        case .metro, .train: return TravelMode.metro.color
        case .other: return Theme.teal
        }
    }
}
