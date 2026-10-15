import SwiftUI
import CoreLocation

// MARK: - Home: where the traveller sleeps tonight

extension AppState {
    /// The city stay covering today.
    var currentCityStay: CityStay? { trip?.cityStay(on: .now) }

    /// Where the traveller is staying now. "Way back home" leads here.
    var home: Stay? { currentCityStay?.stay }

    /// Saves where the traveller is staying: on today's city of the trip, or as a new trip.
    func setHome(_ stay: Stay) {
        if var trip = trip,
           let current = trip.cityStay(on: .now),
           let index = trip.cities.firstIndex(where: { $0.id == current.id }) {
            trip.cities[index].stay = stay
            trip.cities[index].wantsStaySuggestions = false
            self.trip = trip
            return
        }
        let city = City.featured.first { $0.bounds.contains(stay.coordinate) } ?? .delhi
        let today = Calendar.current.startOfDay(for: .now)
        let leave = Calendar.current.date(byAdding: .day, value: max(persona.tripDays - 1, 1), to: today) ?? today
        var cityStay = CityStay(city: city, arrival: today, departure: leave)
        cityStay.stay = stay
        if var trip = trip {
            trip.cities.append(cityStay)
            self.trip = trip
        } else {
            self.trip = Trip(cities: [cityStay], party: nil, travellers: nil)
        }
    }
}

/// Presents the stay question and the way home from anywhere in the app, and keeps asking
/// (gently, at most every ten minutes) until the traveller says where they're staying.
@Observable
final class WayHomeRouter {
    var showSetup = false
    var showWayHome = false
    /// The small "You're new to the city" popup. Its "Add my stay" opens `showSetup`.
    var showPrompt = false
    @ObservationIgnored private var lastAsked: Date?

    func askIfNeeded(_ app: AppState) {
        guard app.phase == .main, app.home == nil, !showSetup, !showWayHome, !showPrompt else { return }
        // Not straight after onboarding: the traveller has just skipped the hotel there.
        if let onboarded = UserDefaults.standard.object(forKey: "candor.onboardedAt") as? Date,
           Date.now.timeIntervalSince(onboarded) < 15 * 60 { return }
        // UI tests drive the screens themselves; a sheet popping up would cover them.
        guard !UserDefaults.standard.bool(forKey: "candor.uiTesting") else { return }
        if let lastAsked, Date.now.timeIntervalSince(lastAsked) < 600 { return }
        lastAsked = .now
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if app.home == nil { showPrompt = true }
        }
    }
}

/// The way from here to the stay, with every mode and its fair fare.
struct WayHomeRoute {
    let leg: Leg
    let origin: CLLocationCoordinate2D
    let originName: String

    var isHome: Bool { leg.km < 0.25 }
}

extension LocationService {
    /// Measures from where the traveller is (or the demo spot outside the city) to their stay.
    func wayHome(to stay: Stay, app: AppState) -> WayHomeRoute {
        let here: CLLocationCoordinate2D
        let name: String
        if let current = location?.coordinate, DelhiMetro.km(current, stay.coordinate) < 80 {
            here = current
            name = L("Your location")
        } else if let city = app.trip?.cities.map(\.city).first(where: { DelhiMetro.km($0.coordinate, stay.coordinate) < 80 })
                    ?? [City.delhi].first(where: { DelhiMetro.km($0.coordinate, stay.coordinate) < 80 }) {
            // Not in that city yet (or no GPS): time it from the city centre, never from another city.
            here = city.coordinate
            name = L("%@ centre", L(city.name))
        } else {
            here = origin
            name = originName
        }
        let leg = PlanCache.shared.leg(from: here, fromName: name,
                                  to: TripStop(name: stay.name, coordinate: stay.coordinate),
                                  at: .now, style: app.persona.travelStyle,
                                  city: app.currentCityStay?.city ?? .delhi,
                                  likesWalking: app.persona.hasTaste("Happy to walk"))
        return WayHomeRoute(leg: leg, origin: here, originName: name)
    }
}

// MARK: - Home screen cards

/// Before the stay is known: a friendly, persistent question. After: the way back home.
struct HomeBaseCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let stay = app.home {
            WayHomeCard(stay: stay)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            StayPromptCard()
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

struct StayPromptCard: View {
    @Environment(WayHomeRouter.self) private var router
    @State private var glow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Floating3D(art: .suitcase, size: 92) { StayQuestionArt() }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("New in town? Where are you staying?"))
                        .font(.heading(.title3))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Tell us your hotel or home, and Candor will always know the way back."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                router.showSetup = true
            } label: {
                Label(L("Add where I'm staying"), systemImage: "house.fill")
            }
            .buttonStyle(.pill)
            .accessibilityIdentifier("addStay")
        }
        .velvetCard(.pearl, padding: 18)
        .overlay {
            // A soft pulse around the card: the question stays until it's answered.
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.saffron.opacity(glow ? 0.65 : 0.12), lineWidth: 2)
        }
        .onAppear {
            // A one-time glow that settles, instead of pulsing forever while you scroll.
            withAnimation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true)) { glow = true }
        }
    }
}

struct WayHomeCard: View {
    let stay: Stay
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(WayHomeRouter.self) private var router

    var body: some View {
        let way = location.wayHome(to: stay, app: app)
        let best = way.leg.bestOption
        Button {
            router.showWayHome = true
        } label: {
            HStack(spacing: 14) {
                // Drawn art in the card's own colours: a lit house at the end of a dotted path.
                HomeNestArt(animated: false)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Way back home"))
                        .font(.heading(.title3))
                        .foregroundStyle(.primary)
                    Text(stay.name)
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if way.isHome {
                        Text(L("You're home. Rest well!"))
                            .font(.candor(.caption1, .semibold))
                            .foregroundStyle(Theme.emerald)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: best.mode.icon)
                            Text("\(best.mode.title) · \(durationText(best.minutes)) · \(best.fareText)")
                        }
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(Theme.emerald)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color(hex: 0x1F7A5C), Theme.emerald],
                                               startPoint: .top, endPoint: .bottom), in: .circle)
                    .shadow(color: Theme.emerald.opacity(0.3), radius: 8, y: 4)
            }
            .glossCard(Theme.emerald, padding: 16)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("wayHome")
    }
}

/// Lives above the tab bar on every tab: one tap home, or the question until it's answered.
struct HomeAccessory: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(WayHomeRouter.self) private var router

    var body: some View {
        Button {
            if app.home == nil { router.showSetup = true } else { router.showWayHome = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: app.home == nil ? "questionmark.circle.fill" : "house.fill")
                    .foregroundStyle(Theme.saffron)
                    .symbolEffect(.pulse, isActive: app.home == nil)
                Group {
                    if let stay = app.home {
                        let way = location.wayHome(to: stay, app: app)
                        Text(L("Way back home · %@", "\(durationText(way.leg.bestOption.minutes)) · \(way.leg.bestOption.fareText)"))
                    } else {
                        Text(L("Where are you staying?"))
                    }
                }
                .font(.candor(.subheadline, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.candor(.caption1, .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeAccessory")
    }
}

// MARK: - "You're new to the city" sheet

struct StaySetupSheet: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Candidate] = []
    @State private var searching = false
    @State private var message: String?
    @State private var saved: Stay?
    @State private var locating = false
    @FocusState private var focused: Bool

    struct Candidate: Identifiable {
        let id = UUID()
        let name: String
        let address: String?
        let coordinate: CLLocationCoordinate2D
    }

    private var city: City { app.currentCityStay?.city ?? .delhi }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Floating3D(art: .suitcase, size: 132) { StayQuestionArt() }
                        .padding(.top, 4)
                        .reveal(0)

                    VStack(spacing: 8) {
                        Text(L("You're new to the city"))
                            .font(.heading(.title1))
                            .multilineTextAlignment(.center)
                        Text(L("Please let us know where you're staying. We'll use it to guide you back home from anywhere."))
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .reveal(1)

                    searchField.reveal(2)

                    if searching {
                        ProgressView().padding(.top, 4)
                    }
                    if let message {
                        Text(message)
                            .font(.candor(.footnote))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        ForEach(results) { candidate in
                            resultRow(candidate)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: results.map(\.id))

                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack(spacing: 8) {
                            if locating { ProgressView() } else { Image(systemName: "location.fill") }
                            Text(L("Use my current location"))
                        }
                    }
                    .buttonStyle(.pillSoft)
                    .disabled(locating)
                    .reveal(3)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Not now")) { dismiss() }
                }
            }
            .overlay {
                if let saved { successOverlay(saved) }
            }
            .task(id: query) { await search() }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(32)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Hotel name or address"), text: $query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.candor(.body))
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Theme.surface, in: .capsule)
        .shadow(color: Theme.shadow, radius: 12, y: 6)
        .accessibilityIdentifier("staySearch")
    }

    private func resultRow(_ candidate: Candidate) -> some View {
        Button {
            save(Stay(name: candidate.name, address: candidate.address,
                      latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .foregroundStyle(Theme.saffron)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.candor(.subheadline, .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let address = candidate.address {
                        Text(address)
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
            }
            .card(padding: 12)
        }
        .buttonStyle(.pressable)
    }

    private func successOverlay(_ stay: Stay) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Floating3D(art: .homePin, size: 150) { HomeNestArt() }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Text(L("Home set!"))
                    .font(.display(size: 32))
                Text(stay.name)
                    .font(.candor(.headline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
        }
        .transition(.opacity)
    }

    // MARK: Actions

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            message = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }

        var found: [Candidate] = []
        if GooglePlaces.isConfigured, let places = try? await GooglePlaces.search(q, in: city) {
            found = places.prefix(6).map {
                Candidate(name: $0.name, address: $0.address,
                          coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
        }
        if found.isEmpty {
            let center = location.location?.coordinate ?? city.coordinate
            let items = await Routing.search(q, near: center)
            found = items.prefix(6).map {
                Candidate(name: $0.name, address: $0.address, coordinate: $0.coordinate)
            }
        }
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { results = found }
        message = found.isEmpty ? L("No places found. Try the hotel's name and area.") : nil
    }

    private func useCurrentLocation() async {
        location.start()
        locating = true
        defer { locating = false }
        // Give a fresh fix a moment to arrive.
        for _ in 0..<10 where location.location == nil {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let here = location.location else {
            message = L("Couldn't find your location yet. Search for your hotel instead.")
            return
        }
        var name = L("My stay")
        var address: String?
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(here).first {
            name = placemark.name ?? name
            address = [placemark.thoroughfare, placemark.subLocality, placemark.locality]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
        save(Stay(name: name, address: address?.isEmpty == true ? nil : address,
                  latitude: here.coordinate.latitude, longitude: here.coordinate.longitude))
    }

    private func save(_ stay: Stay) {
        focused = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            app.setHome(stay)
            saved = stay
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
    }
}

// MARK: - The way back home

struct WayHomeView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(WayHomeRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var selected: TravelMode?
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var showDriverCard = false
    @Namespace private var modeSelection

    var body: some View {
        Group {
            if let stay = app.home {
                content(stay)
            } else {
                // Shouldn't happen (the card only shows once there's a stay), but never a dead end.
                VStack(spacing: 18) {
                    Floating3D(art: .suitcase, size: 120) { StayQuestionArt() }
                    Text(L("Where are you staying?")).font(.heading(.title2))
                    Button(L("Add where I'm staying")) {
                        dismiss()
                        router.showSetup = true
                    }
                    .buttonStyle(.pill)
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            }
        }
    }

    private func content(_ stay: Stay) -> some View {
        let way = location.wayHome(to: stay, app: app)
        let options = way.leg.sortedOptions
        let option = options.first { $0.mode == selected } ?? way.leg.bestOption

        return GoogleMapView(
            markers: [
                .init(id: "you", way.origin, title: L("You"), style: .you),
                .init(id: "stay", stay.coordinate, title: stay.name, style: .symbol("house.fill", UIColor(Theme.ink)))
            ],
            lines: route.count > 1
                ? [.init(route, color: UIColor(Theme.saffron), width: 6)]
                : [.init([way.origin, stay.coordinate], color: UIColor(Theme.saffron).withAlphaComponent(0.7),
                         width: 4, dashed: true, casing: false)],
            insets: UIEdgeInsets(top: 110, left: 0, bottom: 380, right: 0)
        )
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { panel(stay: stay, way: way, options: options, option: option) }
        .task(id: "\(stay.latitude),\(stay.longitude)") {
            await loadRoute(from: way.origin, to: stay.coordinate)
        }
        .sheet(isPresented: $showDriverCard) {
            DriverCardView(stay: stay)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { CircleIcon(systemName: "chevron.left", size: 46) }
                .buttonStyle(.pressable)
                .accessibilityLabel(L("Close"))
            Spacer()
            Text(L("Way back home"))
                .font(.heading(.headline))
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(Theme.surface, in: .capsule)
                .shadow(color: Theme.shadow, radius: 12, y: 6)
            Spacer()
            Button {
                dismiss()
                router.showSetup = true
            } label: { CircleIcon(systemName: "pencil", size: 46) }
                .buttonStyle(.pressable)
                .accessibilityLabel(L("Change"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func panel(stay: Stay, way: WayHomeRoute, options: [LegOption], option: LegOption) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Floating3D(art: .homePin, size: 62) { HomeNestArt() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(stay.name)
                        .font(.heading(.title3))
                        .lineLimit(1)
                    if let address = stay.address {
                        Text(address)
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("\(way.leg.km.formatted(.number.precision(.fractionLength(1)))) km")
                    .font(.candor(.headline, .semibold).monospacedDigit())
            }

            if way.isHome {
                Label(L("You're home. Rest well!"), systemImage: "moon.zzz.fill")
                    .font(.candor(.subheadline, .semibold))
                    .foregroundStyle(Theme.mint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(options) { item in
                            modeTile(item, isSelected: item.mode == option.mode)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(option.steps.enumerated()), id: \.offset) { index, step in
                        Label {
                            Text(step).font(.candor(.subheadline))
                        } icon: {
                            Image(systemName: "\(index + 1).circle.fill").foregroundStyle(option.mode.color)
                        }
                    }
                    if let tip = option.tips.first {
                        Label {
                            Text(tip).font(.candor(.caption1)).foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.saffron)
                        }
                    }
                }
                .animation(.snappy, value: option.mode)
            }

            HStack(spacing: 10) {
                Button {
                    showDriverCard = true
                } label: {
                    Label(L("Show the driver"), systemImage: "text.bubble.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .outline, height: 52))

                Button {
                    openInMaps(stay, mode: option.mode)
                } label: {
                    Label(L("Start"), systemImage: "location.north.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .filled, height: 52))
            }
        }
        .padding(18)
        .background(Theme.surface, in: .rect(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func modeTile(_ item: LegOption, isSelected: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selected = item.mode }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.mode.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : item.mode.color)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Color.white.opacity(0.18) : item.mode.color.opacity(0.14), in: .circle)
                Text(item.mode.title)
                    .font(.candor(.subheadline, .semibold))
                Text(durationText(item.minutes))
                    .font(.candor(.caption1))
                    .opacity(0.75)
                Text(item.fareText)
                    .font(.candor(.caption1, .bold).monospacedDigit())
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(width: 96, alignment: .leading)
            .padding(12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.ink)
                        .matchedGeometryEffect(id: "mode", in: modeSelection)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.canvas)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private func loadRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let found = await RouteService.path(from: origin, to: destination, mode: .cab)
        if found.count > 2 {
            withAnimation(.smooth) { route = found }
        }
    }

    private func openInMaps(_ stay: Stay, mode: TravelMode) {
        if let url = GoogleMapsLink.directions(to: stay.coordinate, mode: mode) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Show the driver

/// Big, readable card for an auto or cab driver: "Please take me to this address" in Hindi,
/// then the stay's name and address. Tap the speaker to say it out loud.
struct DriverCardView: View {
    let stay: Stay
    @Environment(\.dismiss) private var dismiss

    private var phrase: Phrase? {
        DelhiData.phrases.first { $0.english == "Take me to this address." }
    }

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.quaternary).frame(width: 40, height: 5).padding(.top, 10)
            Floating3D(.pin, size: 90, symbol: "mappin.and.ellipse", tint: Theme.rose)
            if let phrase {
                VStack(spacing: 6) {
                    Text(phrase.hindi)
                        .font(.hindi(.title1, semibold: true, size: 34))
                        .multilineTextAlignment(.center)
                    Text(phrase.roman)
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text(stay.name)
                    .font(.display(size: 30))
                    .multilineTextAlignment(.center)
                if let address = stay.address {
                    Text(address)
                        .font(.candor(.title3))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas, in: .rect(cornerRadius: 24, style: .continuous))

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    let text = [phrase?.hindi, stay.name, stay.address].compactMap { $0 }.joined(separator: ". ")
                    Speaker.shared.speak(text)
                } label: {
                    Label(L("Speak"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.pillOutline)
                Button(L("Done")) { dismiss() }
                    .buttonStyle(.pill)
            }
        }
        .padding(24)
        .background(Theme.surface)
        .presentationDetents([.large])
        .presentationCornerRadius(32)
    }
}
