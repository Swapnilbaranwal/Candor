import SwiftUI
import MapKit

/// Fare check: destination → road distance → official metered fare → verdict on the quote.
struct RideCheckView: View {
    var initialDestination: String?

    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var query = ""
    @State private var results: [MKMapItem] = []
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
        return PriceVerdict(item: "\(mode.title) to \(route.name)",
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
                            Label(saved ? "Saved to your shield" : "Save this check", systemImage: saved ? "checkmark" : "tray.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                        .buttonStyle(.glass)
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
        .background(LiquidBackground())
        .navigationTitle("Ride fare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
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
                Image(systemName: "location.circle.fill").font(.title2).foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From").font(.caption).foregroundStyle(.secondary)
                    Text(location.originName).font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Theme.rose)
                TextField("Where to?", text: $query)
                    .font(.headline)
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { Task { await search() } }
                if isBusy {
                    ProgressView()
                } else if let route {
                    Text("\(route.km.formatted(.number.precision(.fractionLength(1)))) km")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.teal)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results.prefix(5), id: \.self) { item in
                        Button {
                            Task { await choose(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                        GlassChip(title: spot.name, icon: spot.category.icon, isSelected: route?.name == spot.name, tint: Theme.teal) {
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
        .glassCard(padding: Self.cardPadding)
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Vehicle", selection: $mode) {
                ForEach(RideMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $night) {
                Label("Night fare (11 pm – 5 am)", systemImage: "moon.stars.fill")
            }
            .tint(Theme.indigo)

            HStack(spacing: 10) {
                Image(systemName: "indianrupeesign").foregroundStyle(Theme.saffron).frame(width: 22)
                TextField("Driver's quote (optional)", text: $askedText)
                    .keyboardType(.numberPad)
                    .focused($focused)
                if let asked {
                    Text(app.homeAmount(asked)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .glassCard()
    }

    private func mapPreview(_ route: Routing.RouteInfo) -> some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            Marker("Start", systemImage: "location.fill", coordinate: location.origin).tint(Theme.teal)
            Marker(route.name, systemImage: "mappin", coordinate: route.coordinate).tint(Theme.rose)
        }
        .id(route.name)
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 26))
        .overlay(alignment: .bottomLeading) {
            Label("\(route.km.formatted(.number.precision(.fractionLength(1)))) km by road", systemImage: "road.lanes")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
        }
    }

    private var fareChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Official fare chart", systemImage: "list.bullet.rectangle.portrait.fill").font(.headline)
            ForEach(RideMode.allCases) { mode in
                HStack(alignment: .top) {
                    Image(systemName: mode.icon).frame(width: 24).foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title).font(.subheadline.weight(.semibold))
                        Text(mode.ruleText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("\(FareChart.source). Fair range allows +20% for traffic and rounding. Verify current rates before relying on them.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .glassCard()
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

    private func choose(_ item: MKMapItem) async {
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
