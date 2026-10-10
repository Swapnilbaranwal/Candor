import SwiftUI
import MapKit

/// The traveller's days in Delhi: where to go, in what order, how to get between places and what it should cost.
struct TripView: View {
    @Binding var tab: AppTab
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent
    @State private var dayIndex = 0
    @State private var expandedStop: UUID?
    @State private var legSheet: Leg?
    @State private var showAddPlace = false
    @State private var showEditDay = false
    @State private var confirmStartOver = false
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if let trip = app.trip, !trip.days.isEmpty {
                    tripContent(trip)
                } else {
                    TripSetupView()
                }
            }
            .background(AppBackground())
            .navigationTitle(L("Trip"))
            .toolbar {
                if app.trip != nil {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .sheet(item: $legSheet) { leg in
                LegDetailSheet(leg: leg)
            }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceSheet(dayIndex: currentIndex)
            }
            .sheet(isPresented: $showEditDay) {
                EditDaySheet(dayIndex: currentIndex) { deleteDay(currentIndex) }
            }
            .confirmationDialog(L("Start over?"), isPresented: $confirmStartOver, titleVisibility: .visible) {
                Button(L("Start over"), role: .destructive) {
                    // Keeps the cities, dates and stay; only the planned days go.
                    withAnimation(.smooth) { app.trip?.days = [] }
                    dayIndex = 0
                }
            } message: {
                Text(L("This removes every day and place in your trip."))
            }
            .onChange(of: app.trip?.startDate, initial: true) { _, _ in
                dayIndex = app.trip?.todayIndex ?? 0
            }
            .onChange(of: dayIndex) { _, _ in
                expandedStop = nil
                mapPosition = .automatic
            }
        }
    }

    /// `dayIndex` kept inside the trip's days.
    private var currentIndex: Int {
        guard let count = app.trip?.days.count, count > 0 else { return 0 }
        return min(max(dayIndex, 0), count - 1)
    }

    private var menu: some View {
        Menu {
            Button(L("Add a day"), systemImage: "calendar.badge.plus") { addDay() }
            Button(L("Edit this day"), systemImage: "pencil") { showEditDay = true }
            Divider()
            Button(L("Start over"), systemImage: "arrow.counterclockwise", role: .destructive) { confirmStartOver = true }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L("Trip options"))
    }

    // MARK: Actions

    private func addDay() {
        guard app.trip != nil else { return }
        app.trip?.days.append(TripDay())
        dayIndex = (app.trip?.days.count ?? 1) - 1
    }

    private func deleteDay(_ index: Int) {
        guard let trip = app.trip, trip.days.indices.contains(index) else { return }
        if trip.days.count == 1 {
            app.trip?.days = []
        } else {
            app.trip?.days.remove(at: index)
        }
        dayIndex = max(0, index - 1)
    }

    private func ask(about stop: TripStop) {
        tab = .agent
        let question = "I'm going to %@. What should I know, what should things cost, and how do I avoid getting overcharged?"
        Task {
            await agent.send(L(question, L(stop.name)),
                             canonical: question.replacingOccurrences(of: "%@", with: stop.name))
        }
    }

    // MARK: Trip

    private func tripContent(_ trip: Trip) -> some View {
        let index = currentIndex
        let day = trip.days[index]
        let date = trip.date(ofDay: index)
        let start = location.dayStart(trip: trip, day: index)
        let plan = TripPlanner.dayPlan(day, date: date, origin: start.coordinate, originName: start.name,
                                       style: app.persona.travelStyle, city: trip.cityStay(ofDay: index)?.city,
                                           likesWalking: app.persona.hasTaste("Happy to walk"))
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dayChips(trip)
                dayHeader(day: day, date: date, plan: plan)
                if !plan.entries.isEmpty {
                    dayMap(plan)
                }
                timeline(plan, date: date)
                dayButtons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .animation(.snappy, value: expandedStop)
        }
    }

    private func dayChips(_ trip: Trip) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trip.days.indices, id: \.self) { index in
                    Chip(title: L("Day %@", index + 1), isSelected: index == currentIndex, tint: Theme.accent) {
                        withAnimation(.snappy) { dayIndex = index }
                    }
                }
                Chip(title: L("Add day"), icon: "plus", tint: Theme.accent) {
                    withAnimation(.snappy) { addDay() }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func dayHeader(day: TripDay, date: Date, plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localizer.shared.locale)))
                .font(.candor(.subheadline, .semibold))
                .foregroundStyle(Theme.accent)
            Text(day.displayTitle)
                .font(.heading(.title2))
                .fixedSize(horizontal: false, vertical: true)
            if !plan.entries.isEmpty {
                Text(L("%1$@ stops · %2$@ travel · %3$@", plan.entries.count, durationText(plan.travelMinutes), plan.fareText))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayMap(_ plan: DayPlan) -> some View {
        let origin = location.dayStart(trip: app.trip, day: currentIndex).coordinate
        let coordinates = [origin] + plan.entries.map(\.stop.coordinate)
        return Group {
            if GoogleMapsSetup.isReady {
                GoogleTripMap(pins: [GoogleTripMap.Pin(latitude: origin.latitude, longitude: origin.longitude,
                                                       title: plan.startName, number: nil)]
                    + plan.entries.enumerated().map { number, entry in
                        GoogleTripMap.Pin(latitude: entry.stop.latitude, longitude: entry.stop.longitude,
                                          title: L(entry.stop.name), number: number + 1)
                    })
            } else {
                appleMap(plan, origin: origin, coordinates: coordinates)
            }
        }
        .frame(height: 210)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Apple Maps, when the Google Maps SDK has no key.
    private func appleMap(_ plan: DayPlan, origin: CLLocationCoordinate2D, coordinates: [CLLocationCoordinate2D]) -> some View {
        Map(position: $mapPosition) {
            Annotation(plan.startName, coordinate: origin) {
                Image(systemName: "location.fill")
                    .font(.candor(.caption1, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.teal, in: .circle)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .annotationTitles(.hidden)
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            ForEach(Array(plan.entries.enumerated()), id: \.element.id) { number, entry in
                Annotation(L(entry.stop.name), coordinate: entry.stop.coordinate) {
                    Text("\(number + 1)")
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: .circle)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    // MARK: Timeline

    @ViewBuilder
    private func timeline(_ plan: DayPlan, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.candor(.footnote, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.teal, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Start")).font(.candor(.caption1)).foregroundStyle(.secondary)
                    Text(plan.startName).font(.candor(.subheadline, .semibold))
                }
                Spacer()
                Text(timeText(plan.start))
                    .font(.candor(.subheadline, .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .card(cornerRadius: 16, padding: 12)

            if plan.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.candor(.largeTitle))
                        .foregroundStyle(Theme.accent)
                    Text(L("No places yet")).font(.candor(.headline, .semibold))
                    Text(L("Add the places you want to see. Candor works out the order of the day, how to get between them and what it should cost."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .card()
            }

            ForEach(Array(plan.entries.enumerated()), id: \.element.id) { number, entry in
                legRow(entry.leg)
                stopCard(entry, number: number + 1, date: date)
            }
        }
    }

    private func legRow(_ leg: Leg) -> some View {
        let option = leg.bestOption
        return Button { legSheet = leg } label: {
            HStack(spacing: 12) {
                Image(systemName: option.mode.icon)
                    .font(.candor(.footnote, .semibold))
                    .foregroundStyle(option.mode.color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(option.mode.title) · \(durationText(option.minutes)) · \(option.fareText)")
                        .font(.candor(.subheadline, .semibold))
                        .foregroundStyle(.primary)
                    Text(option.summary)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if leg.options.count > 1 {
                    Text(L("%@ ways", leg.options.count))
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(option.mode.color)
                }
                Image(systemName: "chevron.right")
                    .font(.candor(.caption1))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(option.mode.color.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(option.mode.color.opacity(0.5))
                    .frame(width: 2)
                    .padding(.vertical, -6)
                    .offset(x: 28)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("Shows every way to get there"))
        .accessibilityIdentifier("tripLeg")
    }

    private func stopCard(_ entry: DayPlan.Entry, number: Int, date: Date) -> some View {
        let stop = entry.stop
        let expanded = expandedStop == stop.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                expandedStop = expanded ? nil : stop.id
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number)")
                        .font(.candor(.subheadline, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(stop.name))
                            .font(.candor(.headline, .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text("\(timeText(entry.arrival))–\(timeText(entry.departure)) · \(L("%@ there", durationText(stop.stayMinutes)))")
                            .font(.candor(.caption1).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let closed = stop.closedNote(on: date) {
                            Label(closed, systemImage: "exclamationmark.triangle.fill")
                                .font(.candor(.caption1, .semibold))
                                .foregroundStyle(Theme.rose)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.candor(.caption1))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let note = stop.note, !note.isEmpty {
                        Label(note, systemImage: "quote.bubble")
                            .font(.candor(.subheadline))
                            .foregroundStyle(Theme.accent)
                    }
                    if let spot = stop.spot {
                        Text(L(spot.blurb)).font(.candor(.subheadline))
                        Label(L(spot.tip), systemImage: "lightbulb.fill")
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    Button { ask(about: stop) } label: {
                        Label(L("Ask Candor about this place"), systemImage: "text.bubble")
                            .font(.candor(.subheadline, .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(cornerRadius: 16, padding: 14)
    }

    private var dayButtons: some View {
        Group {
            HStack(spacing: 10) {
                Button { showAddPlace = true } label: {
                    Label(L("Add a place"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button { showEditDay = true } label: {
                    Label(L("Edit day"), systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.bordered)
            }
            .font(.candor(.subheadline, .semibold))
        }
    }
}

// MARK: - Setup

/// First visit to the Trip tab: pick the dates, then let Candor plan or start empty.
private struct TripSetupView: View {
    @Environment(AppState.self) private var app
    @State private var firstDay = Date()
    @State private var days = 2
    @State private var isPlanning = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Plan your days in %@", L((app.trip?.cities.first?.city ?? .delhi).name)))
                        .font(.heading(.largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Candor orders your places, works out how to get between them, and tells you the fair fare for every ride."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    DatePicker(L("First day"), selection: $firstDay, displayedComponents: .date)
                        .font(.candor(.subheadline, .semibold))
                    Divider()
                    Stepper(value: $days, in: 1...10) {
                        Text(L("Days: %@", days)).font(.candor(.subheadline, .semibold))
                    }
                }
                .card(cornerRadius: 16)

                if isPlanning {
                    HStack(spacing: 14) {
                        AgentMark(size: 48, isActive: true)
                        Text(L("Planning your days…")).font(.candor(.headline, .semibold))
                        Spacer(minLength: 0)
                    }
                    .card()
                    .transition(.opacity)
                } else {
                    optionCard(title: L("Plan it for me"),
                               subtitle: L("Candor picks places for your interests, groups them by area and skips closing days."),
                               icon: "calendar", tint: Theme.accent, action: planForMe)
                        .accessibilityIdentifier("tripPlanForMe")
                    optionCard(title: L("Build my own"),
                               subtitle: L("Start with empty days and add the places you want."),
                               icon: "square.and.pencil", tint: Theme.teal, action: buildOwn)
                        .accessibilityIdentifier("tripBuildOwn")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .animation(.smooth, value: isPlanning)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let trip = app.trip, let first = trip.cities.first {
                firstDay = first.arrival
                days = min(max(trip.plannedDayCount, 1), 10)
            } else {
                days = min(max(app.persona.tripDays, 1), 10)
            }
        }
    }

    private func optionCard(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.candor(.title2))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.candor(.headline, .semibold)).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    /// The trip with the dates picked here. Keeps the saved city, stay and party; when the dates
    /// change, the first city moves to the new dates (later cities are dropped).
    private func tripForDates() -> Trip {
        let start = Calendar.current.startOfDay(for: firstDay)
        let end = Calendar.current.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start
        var trip = app.trip ?? Trip(cities: [], party: nil, travellers: nil)
        let unchanged = trip.cities.first?.arrival == start && trip.cities.last?.departure == end
        if !unchanged {
            var first = trip.cities.first ?? CityStay(city: .delhi, arrival: start, departure: end)
            first.arrival = start
            first.departure = end
            trip.cities = [first]
        }
        trip.startDate = start
        return trip
    }

    private func planForMe() {
        isPlanning = true
        let trip = tripForDates()
        Task {
            let planned = app.hasGemini
                ? await TripPlanner.suggestWithGemini(app: app, trip: trip)
                : TripPlanner.suggest(persona: app.persona, trip: trip)
            withAnimation(.smooth) {
                app.trip = planned
                isPlanning = false
            }
        }
    }

    private func buildOwn() {
        var trip = tripForDates()
        trip.source = .own
        trip.days = (0..<trip.plannedDayCount).map { _ in TripDay() }
        withAnimation(.smooth) { app.trip = trip }
    }
}

// MARK: - Leg detail

/// Every way to make one hop, best first, with steps, tips and a fare check for rides.
struct LegDetailSheet: View {
    let leg: Leg
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L(leg.from)) \(Localizer.shared.arrow) \(L(leg.to))")
                            .font(.heading(.title3))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("About %@ km by road", leg.km.formatted(.number.precision(.fractionLength(1)))))
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(leg.sortedOptions) { option in
                        optionCard(option)
                    }
                    Text(L("Times and fares are estimates from the official fare chart and DMRC fare slabs."))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle(L("Getting there"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func optionCard(_ option: LegOption) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: option.mode.icon)
                    .font(.candor(.headline, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(option.mode.color, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.mode.title).font(.candor(.headline, .semibold))
                        if option.mode == leg.best {
                            Text(L("Best"))
                                .font(.candor(.caption2, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.mint, in: .capsule)
                        }
                    }
                    Text(option.summary)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(option.fareText).font(.candor(.subheadline, .bold).monospacedDigit())
                    Text(durationText(option.minutes)).font(.candor(.caption1)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(option.steps.enumerated()), id: \.offset) { number, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(number + 1)")
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(option.mode.color)
                            .frame(width: 20, height: 20)
                            .background(option.mode.color.opacity(0.15), in: .circle)
                        Text(step)
                            .font(.candor(.subheadline))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !option.tips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(option.tips, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if option.mode == .auto || option.mode == .cab {
                NavigationLink {
                    RideCheckView(initialDestination: leg.to)
                } label: {
                    Label(L("Check a driver's quote"), systemImage: "checkmark.shield.fill")
                        .font(.candor(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card(cornerRadius: 16, tint: option.mode == leg.best ? option.mode.color.opacity(0.35) : nil, padding: 16)
    }
}

// MARK: - Add a place

/// Candor's places by category, plus Apple Maps search for anywhere else.
struct AddPlaceSheet: View {
    let dayIndex: Int
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var category: SpotCategory?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    private var stops: [TripStop] {
        guard let trip = app.trip, trip.days.indices.contains(dayIndex) else { return [] }
        return trip.days[dayIndex].stops
    }

    private var spots: [Spot] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return DelhiData.spots.filter { spot in
            (category == nil || spot.category == category)
                && (q.isEmpty || spot.name.lowercased().contains(q) || L(spot.name).lowercased().contains(q)
                    || spot.aliases.contains { $0.contains(q) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(title: L("All"), isSelected: category == nil, tint: Theme.accent) { category = nil }
                            ForEach(SpotCategory.allCases) { item in
                                Chip(title: item.title, icon: item.icon, isSelected: category == item, tint: item.color) {
                                    category = category == item ? nil : item
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section(L("Candor's places")) {
                    ForEach(spots) { spot in
                        let added = stops.contains { $0.spotID == spot.id }
                        placeRow(name: L(spot.name), detail: L(spot.blurb), icon: spot.category.icon,
                                 color: spot.category.color, added: added) {
                            add(TripStop(spot: spot))
                        }
                    }
                    if spots.isEmpty {
                        Text(L("No matching places")).foregroundStyle(.secondary)
                    }
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section(L("Apple Maps")) {
                        if isSearching && results.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        ForEach(results.prefix(8), id: \.self) { item in
                            let name = item.name ?? L("Place")
                            let coordinate = item.placemark.coordinate
                            let added = stops.contains {
                                $0.spotID == nil && $0.name == name
                                    && abs($0.latitude - coordinate.latitude) < 0.0005
                                    && abs($0.longitude - coordinate.longitude) < 0.0005
                            }
                            placeRow(name: name, detail: item.placemark.title ?? "", icon: "mappin",
                                     color: Theme.rose, added: added) {
                                add(TripStop(name: name, coordinate: coordinate))
                            }
                        }
                        if !isSearching && results.isEmpty {
                            Text(L("No results")).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Search places in Delhi"))
            .navigationTitle(L("Add a place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else {
                    results = []
                    return
                }
                isSearching = true
                // Debounce: wait for typing to pause before asking Apple Maps.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let found = await Routing.search(q, near: location.origin)
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
            }
        }
    }

    private func placeRow(name: String, detail: String, icon: String, color: Color, added: Bool,
                          action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.candor(.subheadline, .semibold))
                if !detail.isEmpty {
                    Text(detail).font(.candor(.caption1)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.candor(.title2))
                    .foregroundStyle(added ? Theme.mint : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(added)
            .accessibilityLabel(added ? L("Added") : L("Add %@", name))
        }
    }

    private func add(_ stop: TripStop) {
        guard let trip = app.trip, trip.days.indices.contains(dayIndex) else { return }
        withAnimation(.snappy) {
            app.trip?.days[dayIndex].stops.append(stop)
        }
    }
}

// MARK: - Edit a day

/// Reorder and remove places, set the time at each, or delete the day.
struct EditDaySheet: View {
    let dayIndex: Int
    var onDeleteDay: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var stops: [TripStop] {
        guard let trip = app.trip, trip.days.indices.contains(dayIndex) else { return [] }
        return trip.days[dayIndex].stops
    }

    private func update(_ change: (inout TripDay) -> Void) {
        guard let trip = app.trip, trip.days.indices.contains(dayIndex) else { return }
        var day = trip.days[dayIndex]
        change(&day)
        app.trip?.days[dayIndex] = day
    }

    private func stayBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { stops.first { $0.id == id }?.stayMinutes ?? 60 },
            set: { value in
                update { day in
                    if let index = day.stops.firstIndex(where: { $0.id == id }) {
                        day.stops[index].stayMinutes = value
                    }
                }
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: {
                guard let trip = app.trip, trip.days.indices.contains(dayIndex) else { return "" }
                return trip.days[dayIndex].title ?? ""
            },
            set: { value in update { $0.title = value.isEmpty ? nil : value } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L("Day title")) {
                    TextField(L("Optional"), text: titleBinding)
                }
                Section {
                    ForEach(stops) { stop in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L(stop.name)).font(.candor(.subheadline, .semibold))
                            Stepper(value: stayBinding(stop.id), in: 15...300, step: 15) {
                                Text(L("Time there: %@", durationText(stop.stayMinutes)))
                                    .font(.candor(.caption1))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { from, to in update { $0.stops.move(fromOffsets: from, toOffset: to) } }
                    .onDelete { offsets in update { $0.stops.remove(atOffsets: offsets) } }
                    if stops.isEmpty {
                        Text(L("No places yet")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("Places"))
                } footer: {
                    Text(L("Drag to change the order. Swipe or tap the minus to remove a place."))
                }
                Section {
                    Button(L("Delete this day"), role: .destructive) { confirmDelete = true }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L("Day %@", dayIndex + 1))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .confirmationDialog(L("Delete this day?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Delete this day"), role: .destructive) {
                    dismiss()
                    onDeleteDay()
                }
            }
        }
    }
}
