import SwiftUI
import CoreLocation

/// One step of a journey, the way a maps app shows it: walk 450 m, ride the Yellow Line six
/// stops towards Samaypur Badli, get off, walk on.
struct JourneyStep: Identifiable {
    enum Kind { case walk, metro, bus, train, ride }

    let kind: Kind
    /// "Walk to Rajiv Chowk", "Yellow Line", "Bus 534"
    let title: String
    /// "towards Samaypur Badli"
    var detail: String?
    var from: String?
    var to: String?
    /// Stations or stops passed in between, when known.
    var stops: [String] = []
    var stopCount: Int?
    let minutes: Int
    var meters: Int?
    let color: Color

    var isTransit: Bool { kind == .metro || kind == .bus || kind == .train }

    /// Stable across redraws, so an opened stop list stays open.
    var id: String { "\(kind)|\(title)|\(from ?? "")|\(to ?? "")|\(minutes)" }
}

// MARK: - Building journeys

enum JourneyBuilder {
    /// A Google public-transport route as journey steps, with Metro stops filled in from Candor's line data.
    static func steps(from route: RouteService.TransitRoute, destination: String) -> [JourneyStep] {
        route.steps.enumerated().map { index, step in
            switch step.kind {
            case .walk:
                let next = route.steps.dropFirst(index + 1).first { $0.kind != .walk }
                let target = next?.from ?? destination
                return JourneyStep(kind: .walk, title: L("Walk to %@", target), detail: step.instruction,
                                   minutes: step.minutes, meters: step.meters, color: Theme.mint)
            case .metro, .train:
                let line = DelhiMetro.line(named: step.line)
                var stops: [String] = []
                var towards = step.headsign
                if let line, let from = step.from, let to = step.to {
                    stops = DelhiMetro.stops(on: line, from: from, to: to) ?? []
                    towards = towards ?? DelhiMetro.towards(on: line, from: from, to: to)
                }
                return JourneyStep(kind: step.kind == .train ? .train : .metro, title: step.line,
                                   detail: towards.map { L("towards %@", $0) }, from: step.from, to: step.to,
                                   stops: stops, stopCount: step.stops, minutes: step.minutes, meters: step.meters,
                                   color: line?.color ?? TransitChip.color(step))
            case .bus, .other:
                return JourneyStep(kind: .bus, title: step.line, detail: step.headsign.map { L("towards %@", $0) },
                                   from: step.from, to: step.to, stopCount: step.stops, minutes: step.minutes,
                                   meters: step.meters, color: TransitChip.color(step))
            }
        }
    }

    /// The Metro journey from Candor's own map: to the nearest station, each line with every stop, then on foot.
    static func offlineMetro(_ leg: Leg) -> [JourneyStep]? {
        let start = DelhiMetro.nearestStation(to: leg.fromCoordinate)
        let end = DelhiMetro.nearestStation(to: leg.toCoordinate)
        guard leg.hasCoordinates, let route = DelhiMetro.route(from: start.station, to: end.station) else { return nil }
        var steps = [access(km: start.km, to: L(start.station.name), station: true)]
        for (index, segment) in route.segments.enumerated() {
            if index > 0 {
                steps.append(JourneyStep(kind: .walk, title: L("Change to the %@", segment.line.title),
                                         detail: L("Follow the %@ signs inside the station", segment.line.title),
                                         minutes: 5, meters: 250, color: Theme.mint))
            }
            let stops = DelhiMetro.stops(on: segment.line, from: segment.from.name, to: segment.to.name) ?? []
            let towards = DelhiMetro.towards(on: segment.line, from: segment.from.name, to: segment.to.name)
            steps.append(JourneyStep(kind: .metro, title: segment.line.title,
                                     detail: towards.map { L("towards %@", $0) },
                                     from: L(segment.from.name), to: L(segment.to.name), stops: stops.map { L($0) },
                                     stopCount: stops.count + 1,
                                     minutes: max(Int((segment.km / 32 * 60).rounded(.up)) + 2, 3),
                                     meters: Int(segment.km * 1000), color: segment.line.color))
        }
        steps.append(access(km: end.km, to: L(leg.to), station: false))
        return steps
    }

    /// A bus journey when Google's live routes aren't available: to the nearest stop, the bus, on foot.
    static func offlineBus(_ leg: Leg) -> [JourneyStep] {
        let ride = max(leg.km - 0.6, 1)
        return [
            JourneyStep(kind: .walk, title: L("Walk to the nearest bus stop"), minutes: 5, meters: 350, color: Theme.mint),
            JourneyStep(kind: .bus, title: L("City bus"), detail: L("towards %@", L(leg.to)),
                        stopCount: max(Int(ride / 0.7), 2), minutes: Int((ride / 15 * 60).rounded(.up)) + 8,
                        meters: Int(ride * 1000), color: TravelMode.bus.color),
            JourneyStep(kind: .walk, title: L("Walk to %@", L(leg.to)), minutes: 4, meters: 300, color: Theme.mint)
        ]
    }

    private static func access(km: Double, to target: String, station: Bool) -> JourneyStep {
        if km <= 1.2 {
            return JourneyStep(kind: .walk, title: L("Walk to %@", target),
                               minutes: max(Int((km / 4.5 * 60).rounded(.up)), 1), meters: Int(km * 1000),
                               color: Theme.mint)
        }
        let road = km * 1.35
        return JourneyStep(kind: .ride, title: station ? L("Short auto to %@ station", target) : L("Short auto to %@", target),
                           detail: L("About %@ on the meter", inr(RideMode.auto.fare(km: road, night: false))),
                           minutes: Int((road / 18 * 60 + 3).rounded(.up)), meters: Int(road * 1000),
                           color: TravelMode.auto.color)
    }
}

// MARK: - Journey screen

/// Getting from one place to the next, mode by mode, with the whole journey on the screen:
/// Metro with every station, buses with route numbers and stops, ride fares from where you are,
/// and Candor's own car with a number to call.
struct JourneyView: View {
    let leg: Leg
    var departure: Date = .now
    @State private var mode: TravelMode
    @State private var transit: [RouteService.TransitRoute]?
    @State private var transitError: String?
    @State private var path: [CLLocationCoordinate2D] = []
    @State private var expandedStops: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Set when the journey belongs to a trip stop: "Go this way" saves the mode on it.
    var onChoose: ((TravelMode) -> Void)?

    init(leg: Leg, mode: TravelMode? = nil, departure: Date = .now, onChoose: ((TravelMode) -> Void)? = nil) {
        self.leg = leg
        self.departure = departure
        self.onChoose = onChoose
        let available = leg.options.map(\.mode)
        _mode = State(initialValue: mode.flatMap { available.contains($0) ? $0 : nil } ?? leg.best)
    }

    private var option: LegOption { leg.options.first { $0.mode == mode } ?? leg.bestOption }

    /// The Google route that matches the chosen mode: Metro-only for Metro, with a bus for Bus.
    private var googleRoute: RouteService.TransitRoute? {
        guard let transit else { return nil }
        switch mode {
        case .metro: return transit.first { $0.usesMetro && !$0.usesBus } ?? transit.first { $0.usesMetro }
        case .bus: return transit.first { $0.usesBus && !$0.usesMetro } ?? transit.first { $0.usesBus }
        default: return nil
        }
    }

    private var transitSteps: [JourneyStep] {
        if let googleRoute { return JourneyBuilder.steps(from: googleRoute, destination: L(leg.to)) }
        if mode == .metro { return JourneyBuilder.offlineMetro(leg) ?? [] }
        return JourneyBuilder.offlineBus(leg)
    }

    private var totalMinutes: Int { googleRoute?.minutes ?? option.minutes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    modePicker
                    map
                    summary
                    switch mode {
                    case .metro, .bus:
                        transitCard
                    case .walk:
                        walkCard
                    case .privateCar:
                        candorCarCard
                    case .auto, .cab, .bikeTaxi, .eRickshaw:
                        rideCard
                    }
                    if !option.tips.isEmpty { tipsCard }
                }
                .padding(20)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) {
                if let onChoose {
                    Button {
                        onChoose(mode)
                        dismiss()
                    } label: {
                        Label(L("Go by %@", mode.title), systemImage: "checkmark")
                    }
                    .buttonStyle(.pill)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .navigationTitle(L("Getting there"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .task { await loadTransit() }
            .task(id: "\(mode.rawValue)-\(transit?.count ?? -1)") { await loadPath() }
            .animation(.snappy, value: mode)
        }
    }

    // MARK: Loading

    private func loadTransit() async {
        guard leg.hasCoordinates, leg.options.contains(where: { $0.mode.isPublic }) else { return }
        guard !GooglePlaces.apiKey.isEmpty else {
            transitError = L("Showing Candor's Metro map. Add the Routes API to your Google key for live buses and trains.")
            return
        }
        do {
            transit = try await RouteService.transit(from: leg.fromCoordinate, to: leg.toCoordinate, departure: departure)
        } catch {
            transit = []
            transitError = L("Live routes aren't available right now, so this uses Candor's own Metro map.")
        }
    }

    private func loadPath() async {
        guard leg.hasCoordinates else { return }
        if let googleRoute, googleRoute.path.count > 1 {
            path = googleRoute.path
        } else {
            path = await RouteService.path(from: leg.fromCoordinate, to: leg.toCoordinate, mode: mode)
        }
    }

    // MARK: Top

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle().stroke(Theme.teal, lineWidth: 3).frame(width: 12, height: 12)
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2, height: 18)
                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.coral)
            }
            .padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                Text(L(leg.from)).font(.candor(.subheadline, .semibold)).lineLimit(1)
                Text(L(leg.to)).font(.heading(.title3)).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(L("%@ km", leg.km.formatted(.number.precision(.fractionLength(1)))))
                .font(.candor(.caption1, .semibold))
                .foregroundStyle(.secondary)
        }
        .glossCard(Theme.teal, padding: 16)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(leg.sortedOptions) { item in
                    let selected = item.mode == mode
                    Button { mode = item.mode } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.mode.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selected ? .white : item.mode.color)
                                .frame(width: 40, height: 40)
                                .background(selected ? item.mode.color : item.mode.color.opacity(0.14), in: .circle)
                            Text(item.mode.title).font(.candor(.caption1, .semibold)).foregroundStyle(.primary)
                            Text(durationText(item.minutes)).font(.candor(.caption2)).foregroundStyle(.secondary)
                            Text(item.fareText).font(.candor(.caption2, .bold).monospacedDigit()).foregroundStyle(item.mode.color)
                        }
                        .frame(width: 80)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .strokeBorder(selected ? item.mode.color : Theme.hairline, lineWidth: selected ? 2 : 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if item.mode == leg.best {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Theme.mint, in: .circle)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var map: some View {
        GoogleMapView(
            markers: leg.hasCoordinates ? [
                .init(leg.fromCoordinate, title: L(leg.from), style: .symbol("circle.fill", UIColor(Theme.teal))),
                .init(leg.toCoordinate, title: L(leg.to), style: .pin(UIColor(Theme.coral)))
            ] : [],
            lines: path.count > 1 ? [.init(path, color: UIColor(mode.color), dashed: mode == .walk)] : [],
            showsTraffic: mode == .cab || mode == .auto
        )
        .frame(height: 200)
        .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
        .id(path.count)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(durationText(totalMinutes)).font(.display(size: 30, .bold).monospacedDigit())
                Text(L("Arrive about %@", timeText(departure.addingTimeInterval(Double(totalMinutes) * 60))))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(googleRoute?.fare ?? option.fareText)
                    .font(.candor(.title3, .bold).monospacedDigit())
                    .foregroundStyle(mode.color)
                Text(mode == .privateCar ? L("fixed fare") : L("fair fare"))
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Public transport

    private var transitCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if transit == nil && transitError == nil && !GooglePlaces.apiKey.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L("Finding live routes…")).font(.candor(.subheadline)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }
            timelineNode(icon: "circle.circle.fill", color: Theme.teal, title: L(leg.from),
                         trailing: timeText(departure))
            ForEach(transitSteps) { step in
                stepRow(step)
            }
            timelineNode(icon: "mappin.circle.fill", color: Theme.coral, title: L(leg.to),
                         trailing: timeText(departure.addingTimeInterval(Double(totalMinutes) * 60)))
            if googleRoute != nil {
                Label(L("Live from Google Maps"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.candor(.caption2, .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else if let transitError {
                Label(transitError, systemImage: "info.circle")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            if mode == .bus, let transit, transit.contains(where: \.usesBus) {
                otherBuses(transit.filter(\.usesBus))
            }
        }
        .glossCard(mode.color, padding: 16)
    }

    private func timelineNode(icon: String, color: Color, title: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title).font(.candor(.subheadline, .semibold)).lineLimit(1)
            Spacer()
            Text(trailing).font(.candor(.caption1, .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// One step, drawn on the journey line: dotted for walking, the line's colour for a ride.
    private func stepRow(_ step: JourneyStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // The journey line.
            ZStack(alignment: .top) {
                if step.isTransit || step.kind == .ride {
                    Capsule().fill(step.color).frame(width: 6)
                } else {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 6)
                        .overlay {
                            DottedLine()
                                .stroke(Theme.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                                .frame(width: 3)
                        }
                }
            }
            .frame(width: 28)
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                if step.isTransit {
                    transitContent(step)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: step.kind == .ride ? TravelMode.auto.icon : "figure.walk")
                            .foregroundStyle(step.color)
                        Text(step.title).font(.candor(.subheadline, .semibold))
                    }
                    Text(walkLine(step))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                    if let detail = step.detail {
                        Text(detail).font(.candor(.caption1)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func walkLine(_ step: JourneyStep) -> String {
        if let meters = step.meters, meters > 0 {
            return durationText(step.minutes) + " · " + distanceText(meters)
        }
        return durationText(step.minutes)
    }

    @ViewBuilder
    private func transitContent(_ step: JourneyStep) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: step.kind == .bus ? "bus.fill" : "tram.fill")
                Text(step.title).lineLimit(1)
            }
            .font(.candor(.caption1, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(step.color, in: .capsule)
            if let detail = step.detail {
                Text(detail).font(.candor(.caption1, .semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        if let from = step.from {
            Label(step.kind == .bus ? L("Board at %@", from) : L("Board at %@ station", from),
                  systemImage: "arrow.down.right.circle.fill")
                .font(.candor(.subheadline, .semibold))
        }
        let count = step.stopCount ?? (step.stops.isEmpty ? nil : step.stops.count + 1)
        if let count {
            Button {
                expandedStops = expandedStops == step.id ? nil : step.id
            } label: {
                HStack(spacing: 4) {
                    Text(L("%1$@ stops · %2$@", count, durationText(step.minutes)))
                    if !step.stops.isEmpty {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expandedStops == step.id ? 180 : 0))
                    }
                }
                .font(.candor(.caption1, .semibold))
                .foregroundStyle(step.color)
            }
            .buttonStyle(.plain)
            .disabled(step.stops.isEmpty)
            if expandedStops == step.id {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(step.stops, id: \.self) { stop in
                        HStack(spacing: 8) {
                            Circle().stroke(step.color, lineWidth: 2).frame(width: 8, height: 8)
                            Text(stop).font(.candor(.caption1))
                        }
                    }
                }
                .padding(.leading, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        if let to = step.to {
            Label(step.kind == .bus ? L("Get off at %@", to) : L("Get off at %@ station", to),
                  systemImage: "arrow.up.right.circle.fill")
                .font(.candor(.subheadline, .semibold))
        }
    }

    private func otherBuses(_ routes: [RouteService.TransitRoute]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 8)
            Text(L("Other buses")).font(.candor(.footnote, .bold)).foregroundStyle(.secondary)
            ForEach(routes.prefix(4)) { route in
                HStack(spacing: 6) {
                    ForEach(route.steps.filter { $0.kind != .walk }) { step in
                        TransitChip(step: step)
                    }
                    Spacer()
                    Text(durationText(route.minutes)).font(.candor(.caption1, .semibold).monospacedDigit())
                    if let fare = route.fare {
                        Text(fare).font(.candor(.caption1, .bold)).foregroundStyle(Theme.mint)
                    }
                }
            }
        }
    }

    // MARK: Walking

    private var walkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Walk to %@", L(leg.to)), systemImage: "figure.walk")
                .font(.candor(.headline, .semibold))
                .foregroundStyle(Theme.mint)
            Text(option.summary).font(.candor(.subheadline)).foregroundStyle(.secondary)
            Text(L("Follow the dotted line on the map. Shade and water help in the afternoon."))
                .font(.candor(.caption1))
                .foregroundStyle(.secondary)
        }
        .glossCard(Theme.mint, padding: 16)
    }

    // MARK: Rides

    private var rideCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(mode.color)
                    .frame(width: 46, height: 46)
                    .background(mode.color.opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("From %@", L(leg.from))).font(.candor(.caption1, .semibold)).foregroundStyle(.secondary)
                    Text(L("%1$@ to %2$@", mode.title, L(leg.to))).font(.candor(.headline, .semibold)).lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                fact(L("Fair fare"), option.fareText, color: mode.color)
                fact(L("Distance"), L("%@ km", leg.km.formatted(.number.precision(.fractionLength(1)))), color: .primary)
                fact(L("Time"), durationText(option.minutes), color: .primary)
            }

            if mode == .auto {
                Label(RideMode.auto.ruleText, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                phraseCard
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(option.steps.enumerated()), id: \.offset) { number, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(number + 1)")
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(mode.color)
                            .frame(width: 20, height: 20)
                            .background(mode.color.opacity(0.14), in: .circle)
                        Text(step).font(.candor(.subheadline)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if mode == .cab || mode == .bikeTaxi {
                HStack(spacing: 10) {
                    providerButton("Uber", url: uberURL)
                    if mode == .cab {
                        providerButton("Ola", url: olaURL)
                    } else {
                        providerButton("Rapido", url: URL(string: "https://www.rapido.bike/"))
                    }
                }
            }

            if mode != .eRickshaw {
                NavigationLink {
                    RideCheckView(initialDestination: leg.to)
                } label: {
                    Label(L("Check a driver's quote"), systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .outline, height: 48))
            }
        }
        .glossCard(mode.color, padding: 16)
    }

    private func fact(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.candor(.caption2, .semibold)).foregroundStyle(.secondary)
            Text(value).font(.candor(.subheadline, .bold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvas, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var phraseCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble.fill").foregroundStyle(Theme.saffron)
            VStack(alignment: .leading, spacing: 1) {
                Text("मीटर से चलिए").font(.hindi(.headline, semibold: true))
                Text("\(Text(verbatim: "Meter se chaliye · ").font(.candor(.caption1, .semibold)))\(Text(L("Please go by the meter")).font(.candor(.caption1)))")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.saffron.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func providerButton(_ name: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(L("Open %@", name), systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(PillButtonStyle(kind: .soft, height: 44))
    }

    private var uberURL: URL? {
        var parts = URLComponents(string: "https://m.uber.com/ul/")
        parts?.queryItems = [
            URLQueryItem(name: "action", value: "setPickup"),
            URLQueryItem(name: "pickup[latitude]", value: "\(leg.fromLatitude)"),
            URLQueryItem(name: "pickup[longitude]", value: "\(leg.fromLongitude)"),
            URLQueryItem(name: "dropoff[latitude]", value: "\(leg.toLatitude)"),
            URLQueryItem(name: "dropoff[longitude]", value: "\(leg.toLongitude)"),
            URLQueryItem(name: "dropoff[nickname]", value: leg.to)
        ]
        return parts?.url
    }

    private var olaURL: URL? {
        var parts = URLComponents(string: "https://book.olacabs.com/")
        parts?.queryItems = [
            URLQueryItem(name: "lat", value: "\(leg.fromLatitude)"),
            URLQueryItem(name: "lng", value: "\(leg.fromLongitude)"),
            URLQueryItem(name: "drop_lat", value: "\(leg.toLatitude)"),
            URLQueryItem(name: "drop_lng", value: "\(leg.toLongitude)")
        ]
        return parts?.url
    }

    // MARK: Candor car

    private var candorCarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "steeringwheel")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 50, height: 50)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Candor Cars")).font(.heading(.title3))
                    Text(L("Verified drivers · fixed, fair fares · AC")).font(.candor(.caption1)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(option.fareText).font(.candor(.title3, .bold).monospacedDigit()).foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(option.steps, id: \.self) { step in
                    Label(step, systemImage: "checkmark.circle.fill")
                        .font(.candor(.subheadline))
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.multicolor)
                }
            }
            if CandorService.hasCarsPhone {
                VStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "tel://\(CandorService.carsPhoneDigits)") { openURL(url) }
                    } label: {
                        Label(L("Call %@", CandorService.carsPhone), systemImage: "phone.fill")
                    }
                    .buttonStyle(.pill)
                    Button {
                        if let url = whatsAppURL { openURL(url) }
                    } label: {
                        Label(L("Book on WhatsApp"), systemImage: "message.fill")
                    }
                    .buttonStyle(PillButtonStyle(kind: .outline, height: 50))
                }
            } else {
                Label(L("Add the Candor Cars number as CANDOR_CARS_PHONE in Keys.xcconfig to show it here."),
                      systemImage: "phone.badge.plus")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
        }
        .glossCard(Theme.ink, padding: 16)
    }

    private var whatsAppURL: URL? {
        let when = departure.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
            .locale(Locale(identifier: "en")))
        let text = "Hi Candor Cars, please book a car from \(leg.from) to \(leg.to) on \(when). Quoted fare: \(option.fareText)."
        var parts = URLComponents(string: "https://wa.me/\(CandorService.carsPhoneDigits)")
        parts?.queryItems = [URLQueryItem(name: "text", value: text)]
        return parts?.url
    }

    // MARK: Tips

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(option.tips, id: \.self) { tip in
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glossCard(Theme.saffron, padding: 14)
    }
}

/// A vertical line, for the dotted walking parts of a journey.
nonisolated struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// "450 m", "2.3 km"
func distanceText(_ meters: Int) -> String {
    meters < 1000 ? L("%@ m", max(10, (meters / 10) * 10))
        : L("%@ km", (Double(meters) / 1000).formatted(.number.precision(.fractionLength(1))))
}
