import SwiftUI
import CoreLocation

/// Fare check: destination → road distance → official metered fare → verdict on the quote.
struct RideCheckView: View {
    var initialDestination: String?

    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var query = ""
    @State private var results: [GooglePlace] = []
    @State private var route: Routing.RouteInfo?
    @State private var mode: RideMode = .auto
    @State private var night = FareChart.isNight()
    @State private var askedText = ""
    @State private var isBusy = false
    @State private var saved = false
    @FocusState private var focused: Bool

    private var asked: Double? {
        guard let value = Double(askedText), value > 0 else { return nil }
        return value
    }

    private var fare: Double? {
        route.map { mode.fare(km: $0.km, night: night) }
    }

    private var verdict: PriceVerdict? {
        guard let route, let fare else { return nil }
        return PriceVerdict(item: L("%1$@ to %2$@", mode.title, L(route.name)),
                            fairLowINR: fare,
                            fairHighINR: (fare * 1.2).rounded(),
                            askedINR: asked,
                            source: FareChart.source,
                            tip: DelhiData.meterPhrase)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                routeCard
                optionsCard
                if let route, let verdict {
                    mapPreview(route)
                    VerdictCardView(verdict: verdict)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    if verdict.askedINR != nil {
                        Button {
                            app.record(PriceCheckRecord(verdict: verdict, kind: .ride))
                            saved = true
                        } label: {
                            Label(saved ? L("Saved to your checks") : L("Save this check"), systemImage: saved ? "checkmark" : "tray.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                        .buttonStyle(.bordered)
                        .disabled(saved)
                    }
                }
                fareChartCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .animation(.smooth, value: route?.name)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(L("Ride fare"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { focused = false }
            }
        }
        .onChange(of: askedText) { _, _ in saved = false }
        .onChange(of: mode) { _, _ in saved = false }
        .task {
            if let initialDestination, route == nil {
                query = initialDestination
                isBusy = true
                route = await Routing.distance(to: initialDestination, from: location.origin)
                isBusy = false
            }
        }
    }

    private static let cardPadding: CGFloat = 18

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill").font(.candor(.title2)).foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("From")).font(.candor(.caption1)).foregroundStyle(.secondary)
                    Text(location.originName).font(.candor(.subheadline, .semibold))
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill").font(.candor(.title2)).foregroundStyle(Theme.rose)
                TextField(L("Where to?"), text: $query)
                    .font(.candor(.headline, .semibold))
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { Task { await search() } }
                if isBusy {
                    ProgressView()
                } else if let route {
                    Text("\(route.km.formatted(.number.precision(.fractionLength(1)))) km")
                        .font(.candor(.subheadline, .bold).monospacedDigit())
                        .foregroundStyle(Theme.teal)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Theme.field, in: .capsule)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results.prefix(5)) { item in
                        Button {
                            Task { await choose(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.candor(.subheadline, .semibold))
                                Text(item.address ?? "").font(.candor(.caption1)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }

            // Quick picks scroll inside the card: the row spans the card edge to edge and clips there,
            // instead of spilling past the card to the edge of the screen.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DelhiData.spots.filter { $0.category != .transport || $0.id == "airport" }) { spot in
                        Chip(title: L(spot.name), icon: spot.category.icon, isSelected: route?.name == spot.name, tint: Theme.teal) {
                            Task { await chooseSpot(spot) }
                        }
                        .frame(maxWidth: 190) // long names truncate instead of filling the row
                    }
                }
                .padding(.vertical, 6) // room for the chips' glass edges inside the clip
            }
            .contentMargins(.horizontal, Self.cardPadding, for: .scrollContent)
            .padding(.horizontal, -Self.cardPadding)
            .padding(.vertical, -4)
        }
        .card(padding: Self.cardPadding)
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L("Vehicle"), selection: $mode) {
                ForEach(RideMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $night) {
                Label(L("Night fare (11 pm – 5 am)"), systemImage: "moon.stars.fill")
            }
            .tint(Theme.accent)

            HStack(spacing: 10) {
                Image(systemName: "indianrupeesign").foregroundStyle(Theme.saffron).frame(width: 22)
                TextField(L("Driver's quote (optional)"), text: $askedText)
                    .keyboardType(.numberPad)
                    .focused($focused)
                if let asked {
                    Text(app.homeAmount(asked)).font(.candor(.caption1)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Theme.field, in: .capsule)
        }
        .card()
    }

    private func mapPreview(_ route: Routing.RouteInfo) -> some View {
        GoogleMapView(
            markers: [
                .init(location.origin, title: L("Start"), style: .symbol("location.fill", UIColor(Theme.teal))),
                .init(route.coordinate, title: L(route.name), style: .pin(UIColor(Theme.rose)))
            ],
            insets: UIEdgeInsets(top: 0, left: 0, bottom: 44, right: 0),
            interactive: false
        )
        .id(route.name)
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .bottomLeading) {
            Label(L("%@ km by road", route.km.formatted(.number.precision(.fractionLength(1)))), systemImage: "road.lanes")
                .font(.candor(.caption1, .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.field, in: .capsule)
                .padding(10)
        }
    }

    private var fareChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Official fare chart"), systemImage: "list.bullet.rectangle.portrait.fill").font(.candor(.headline, .semibold))
            ForEach(RideMode.allCases) { mode in
                HStack(alignment: .top) {
                    Image(systemName: mode.icon).frame(width: 24).foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title).font(.candor(.subheadline, .semibold))
                        Text(mode.ruleText).font(.candor(.caption1)).foregroundStyle(.secondary)
                    }
                }
            }
            Text(L("%@. Fair range allows +20% for traffic and rounding. Verify current rates before relying on them.", L(FareChart.source)))
                .font(.candor(.caption2))
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let spot = DelhiData.spot(matching: text) {
            await chooseSpot(spot)
            return
        }
        isBusy = true
        results = await Routing.search(text, near: location.origin)
        isBusy = false
    }

    private func choose(_ item: GooglePlace) async {
        focused = false
        isBusy = true
        results = []
        route = await Routing.distance(to: item, from: location.origin)
        query = route?.name ?? query
        saved = false
        isBusy = false
    }

    private func chooseSpot(_ spot: Spot) async {
        focused = false
        isBusy = true
        results = []
        query = spot.name
        route = await Routing.distance(to: spot.coordinate, name: spot.name, from: location.origin)
        saved = false
        isBusy = false
    }
}
