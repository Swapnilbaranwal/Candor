import SwiftUI
import CoreLocation

/// The traveller's days in Delhi: where to go, in what order, how to get between places and what it should cost.
struct TripView: View {
    @Binding var tab: AppTab
    @Environment(AskCandorRouter.self) private var askCandor
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var dayIndex = 0
    /// The day last shown, so switching tabs and back doesn't jump to today. -1 until chosen.
    @SceneStorage("candor.tripDay") private var savedDay = -1
    @State private var expandedStop: UUID?
    /// Places "Fix it" couldn't find an open time for.
    @State private var fixNotice: String?
    @State private var legSheet: Leg?
    /// The stop the open journey leads to, so "Go this way" can save the choice on it.
    @State private var legStopID: UUID?
    @State private var showAddPlace = false
    @State private var showEditDay = false
    @State private var confirmStartOver = false
    /// The day's hops on real roads and rails, loaded for the map.
    @State private var dayRoutes: [DayRoute] = []
    @State private var show3D = false

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
            // A small title in the bar, next to the buttons: no big title and empty gap above the days.
            .navigationTitle(L("Trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { askCandor.open() } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(hex: 0xC4621A))
                    }
                    .accessibilityLabel(L("Ask Candor anything…"))
                    .accessibilityIdentifier("tripAsk")
                }
                if app.trip != nil {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .sheet(item: $legSheet) { leg in
                JourneyView(leg: leg) { mode in
                    if let id = legStopID { choose(mode, for: id) }
                }
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
            .onAppear {
                dayIndex = savedDay >= 0 ? savedDay : (app.trip?.todayIndex ?? 0)
            }
            .onChange(of: app.trip?.startDate) { _, _ in
                // New dates: start from today again.
                dayIndex = app.trip?.todayIndex ?? 0
            }
            .onChange(of: dayIndex) { _, day in
                savedDay = day
                dayRoutes = []
                expandedStop = nil
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

    // MARK: Trip

    private func tripContent(_ trip: Trip) -> some View {
        // The view model works out the day (plan, numbers, done or not); this view lays it out.
        let model = TripDayViewModel(trip: trip, dayIndex: currentIndex, persona: app.persona, location: location)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dayChips(model.chips)
                dayHeader(model)
                if model.isComplete {
                    dayCompleteCard(model)
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                                removal: .opacity))
                }
                TravelStyleSwitcher(compact: true)
                TravelCompanionPicker(day: model.date)
                if !model.insights.isEmpty {
                    TripInsightsSection(insights: model.insights)
                }
                if model.hasStops {
                    dayMap(model)
                }
                timeline(model.plan, date: model.date)
                dayButtons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .animation(.candorExpand, value: expandedStop)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.isComplete)
        }
        .scrollIndicators(.hidden)
        // Real opening hours from Google Maps, so the day is timed around them.
        .task(id: model.routeKey) { await app.loadOpeningHours(day: model.index) }
    }

    private func dayChips(_ chips: [TripDayViewModel.DayChip]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Chip(title: chip.title, icon: chip.isComplete ? "checkmark.seal.fill" : nil,
                         isSelected: chip.index == currentIndex,
                         tint: chip.isComplete ? Theme.emerald : Theme.accent) {
                        withAnimation(.snappy) { dayIndex = chip.index }
                    }
                    .accessibilityValue(chip.isComplete ? L("Done") : "")
                }
                Chip(title: L("Add day"), icon: "plus", tint: Theme.accent) {
                    withAnimation(.snappy) { addDay() }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    /// The day as a hero card: the date, the title, the day's numbers and how much of it is done.
    private func dayHeader(_ model: TripDayViewModel) -> some View {
        let plan = model.plan
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(model.dateLine)
                if let city = model.cityName {
                    Text("· " + L(city))
                }
                Spacer(minLength: 0)
                if model.isComplete {
                    Label(L("Done"), systemImage: "checkmark.seal.fill")
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.emerald, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .font(.candor(.subheadline, .semibold))
            .foregroundStyle(Theme.ink)
            Text(model.day.displayTitle)
                .font(.heading(.title1))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.entries.isEmpty {
                HStack(spacing: 8) {
                    headerStat(icon: "mappin.and.ellipse", text: L("%@ stops", plan.entries.count))
                    headerStat(icon: "clock.fill", text: durationText(plan.travelMinutes))
                    headerStat(icon: "indianrupeesign", text: plan.fareText)
                }
                if model.visitedCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(model.isComplete ? L("Day done") : L("%1$@ of %2$@ visited", model.visitedCount, plan.entries.count),
                              systemImage: "checkmark.circle.fill")
                            .font(.candor(.subheadline, .semibold))
                            .foregroundStyle(Theme.emerald)
                            .contentTransition(.numericText())
                        ProgressView(value: model.progress)
                            .tint(Theme.emerald)
                            .animation(.smooth, value: model.progress)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .velvetCard(.pearl, padding: 18)
    }

    /// Shown once every place on the day is ticked off: the day is complete.
    private func dayCompleteCard(_ model: TripDayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Velvet.emerald.sheen)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.14), in: .circle)
                    .symbolEffect(.bounce, value: model.isComplete)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Day %@ complete", model.index + 1))
                        .font(.heading(.title2))
                    Text(L("You saw all %1$@ places and travelled for %2$@. Rest your feet, you earned it.",
                           model.plan.entries.count, durationText(model.plan.travelMinutes)))
                        .font(.candor(.subheadline))
                        .foregroundStyle(Velvet.emerald.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let next = model.nextOpenDay {
                Button {
                    withAnimation(.snappy) { dayIndex = next }
                } label: {
                    Label(L("Go to Day %@", next + 1), systemImage: "arrow.right")
                }
                .buttonStyle(PillButtonStyle(kind: .cream, height: 46))
            } else {
                Label(L("Every day of your trip is done. What a journey!"), systemImage: "sparkles")
                    .font(.candor(.subheadline, .semibold))
            }
        }
        .foregroundStyle(Velvet.emerald.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .velvetCard(.emerald, radius: 26, padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func headerStat(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).lineLimit(1)
        }
        .font(.candor(.caption1, .semibold).monospacedDigit())
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.accentSoft, in: .capsule)
    }

    private func dayMap(_ model: TripDayViewModel) -> some View {
        let plan = model.plan
        let origin = model.origin
        return Button { show3D = true } label: {
            GoogleTripMap(pins: googlePins(plan, origin: origin), lines: googleLines)
            .allowsHitTesting(false)
            .frame(height: 230)
            .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Label(L("Explore in 3D"), systemImage: "cube.transparent.fill")
                    .font(.candor(.subheadline, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.brandFill, in: .capsule)
                    .shadow(color: Theme.ink.opacity(0.35), radius: 10, y: 5)
                    .padding(12)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    ForEach(Array(Set(plan.entries.map(\.leg.best))).sorted { $0.rawValue < $1.rawValue }) { mode in
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(mode.color, in: .circle)
                    }
                }
                .padding(6)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(12)
            }
            .shadow(color: Theme.shadow, radius: 14, y: 8)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(L("Explore the day in 3D"))
        .task(id: model.routeKey) { await loadRoutes(plan, origin: origin) }
        .task(id: model.routeKey) {
            for entry in plan.entries { _ = await PlaceGuide.info(for: entry.stop, app: app) }
        }
        .fullScreenCover(isPresented: $show3D) {
            Trip3DMapView(title: model.day.displayTitle,
                          stops: [DayMapStop(id: model.day.id, number: nil, name: plan.startName, coordinate: origin)]
                            + plan.entries.enumerated().map { number, entry in
                                DayMapStop(id: entry.stop.id, number: number + 1, name: L(entry.stop.name),
                                           coordinate: entry.stop.coordinate, visited: entry.stop.isVisited)
                            },
                          routes: dayRoutes)
        }
    }

    private func googlePins(_ plan: DayPlan, origin: CLLocationCoordinate2D) -> [GoogleTripMap.Pin] {
        let start = GoogleTripMap.Pin(latitude: origin.latitude, longitude: origin.longitude,
                                      title: plan.startName, number: nil)
        let stops: [GoogleTripMap.Pin] = plan.entries.enumerated().map { number, entry in
            GoogleTripMap.Pin(latitude: entry.stop.latitude, longitude: entry.stop.longitude,
                              title: L(entry.stop.name), number: number + 1, visited: entry.stop.isVisited)
        }
        return [start] + stops
    }

    private var googleLines: [GoogleTripMap.Line] {
        dayRoutes.map { route in
            GoogleTripMap.Line(latitudes: route.coordinates.map(\.latitude),
                               longitudes: route.coordinates.map(\.longitude),
                               color: UIColor(route.mode.color))
        }
    }

    /// Each hop of the day on real roads (or rails, for Metro and bus), in its travel colour.
    private func loadRoutes(_ plan: DayPlan, origin: CLLocationCoordinate2D) async {
        var from = origin
        var loaded: [DayRoute] = []
        for entry in plan.entries {
            let path = await RouteService.path(from: from, to: entry.stop.coordinate, mode: entry.leg.best)
            guard !Task.isCancelled else { return }
            loaded.append(DayRoute(id: entry.stop.id, mode: entry.leg.best, coordinates: path))
            from = entry.stop.coordinate
        }
        withAnimation(.smooth) { dayRoutes = loaded }
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

            if !plan.entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.mint)
                    Text(L("Tick each place when you get there"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { showEditDay = true } label: {
                        Label(L("Rearrange"), systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
                .font(.candor(.caption1, .medium))
                .padding(.horizontal, 4)
            }

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

            if plan.closedCount > 0 {
                closedBanner(plan.closedCount)
            }

            ForEach(Array(plan.entries.enumerated()), id: \.element.id) { number, entry in
                legRow(entry.leg, stop: entry.stop)
                stopCard(entry, number: number + 1, date: date)
            }
        }
    }

    /// The hop to a stop. Until the traveller picks how to go, every way is offered as a chip
    /// with its fare; after that only their choice shows, with a button to change it.
    @ViewBuilder
    private func legRow(_ leg: Leg, stop: TripStop) -> some View {
        if (stop.travelMode == nil || stop.travelMode != leg.best) && !stop.isArrived && leg.options.count > 1 {
            modeChooser(leg, stop: stop)
        } else {
            chosenLeg(leg, stop: stop)
        }
    }

    private func modeChooser(_ leg: Leg, stop: TripStop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .foregroundStyle(Theme.ink)
                Text(L("How will you get to %@?", L(stop.name)))
                    .font(.candor(.subheadline, .medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button(L("Compare")) {
                    legStopID = stop.id
                    legSheet = leg
                }
                .font(.candor(.caption1, .semibold))
                .foregroundStyle(Theme.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(leg.sortedOptions) { option in
                        Button { choose(option.mode, for: stop.id) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: option.mode.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(option.mode.color)
                                    .frame(width: 34, height: 34)
                                    .background(option.mode.color.opacity(0.12), in: .circle)
                                Text(option.mode.title).font(.candor(.caption2, .medium)).foregroundStyle(.primary)
                                Text(option.fareText).font(.candor(.caption2).monospacedDigit()).foregroundStyle(.secondary)
                                Text(durationText(option.minutes)).font(.candor(.caption2).monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            .frame(width: 70)
                            .padding(.vertical, 8)
                            .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(option.mode == leg.best ? Theme.mint.opacity(0.6) : Color.primary.opacity(0.06),
                                                  lineWidth: 1)
                            }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(option.mode.title), \(option.fareText), \(durationText(option.minutes))")
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, -12)
            .clipShape(.rect(cornerRadius: 12))
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 16, style: .continuous))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityIdentifier("tripLegChooser")
    }

    private func chosenLeg(_ leg: Leg, stop: TripStop) -> some View {
        let option = leg.bestOption
        let done = stop.isArrived
        return HStack(spacing: 0) {
            // Tick off the journey here. Keeps the timeline line running through it.
            Button {
                toggleArrived(stop)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : option.mode.icon)
                    .font(.candor(done ? .title3 : .footnote, .semibold))
                    .foregroundStyle(done ? Theme.mint : option.mode.color)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .accessibilityLabel(done ? L("Undo: got to %@", L(stop.name)) : L("Mark as reached: %@", L(stop.name)))

            Button {
                legStopID = stop.id
                legSheet = leg
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.mode.title) · \(durationText(option.minutes)) · \(option.fareText)")
                            .font(.candor(.subheadline, .medium))
                            .foregroundStyle(done ? .secondary : .primary)
                            .strikethrough(done, color: .secondary)
                        Text(done ? L("Done") : L("See the journey"))
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripLeg")

            if !done && leg.options.count > 1 {
                Button {
                    updateStop(stop.id) { $0.travelMode = nil }
                } label: {
                    Label(L("Change"), systemImage: "pencil")
                        .font(.candor(.caption1, .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accentSoft, in: .capsule)
                }
                .buttonStyle(.pressable)
                .padding(.trailing, 10)
                .accessibilityLabel(L("Change how to get to %@", L(stop.name)))
            }
        }
        .background((done ? Theme.mint : option.mode.color).opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill((done ? Theme.mint : option.mode.color).opacity(0.5))
                .frame(width: 2)
                .padding(.vertical, -6)
                .offset(x: 28)
                .allowsHitTesting(false)
        }
    }

    /// Saves how the traveller will get to a stop.
    /// "1 place would be closed when you get there", with a button that moves it to a time it's open.
    private func closedBanner(_ count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.rose)
            Text(count == 1 ? L("1 place would be closed when you get there")
                            : L("%@ places would be closed when you get there", count))
                .font(.candor(.subheadline, .medium))
            Spacer(minLength: 8)
            Button(L("Fix it")) {
                let dayIndex = currentIndex
                withAnimation(.snappy) {
                    let stuck = app.fixClosedStops(day: dayIndex, location: location)
                    fixNotice = stuck.isEmpty ? nil : L("No open time for %@ on your days.", stuck.map { L($0) }.joined(separator: ", "))
                }
            }
            .buttonStyle(PillButtonStyle(kind: .cream, height: 36))
            .fixedSize()
        }
        .padding(14)
        .background(Theme.rose.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let fixNotice {
                Text(fixNotice).font(.candor(.caption1)).foregroundStyle(.secondary).offset(y: 20).padding(.leading, 14)
            }
        }
    }

    private func choose(_ mode: TravelMode, for id: UUID) {
        updateStop(id) { $0.travelMode = mode }
    }

    // MARK: Ticking off

    /// Changes one stop on the current day.
    private func updateStop(_ id: UUID, _ change: (inout TripStop) -> Void) {
        // Read everything first: `currentIndex` reads `app.trip`, so it can't be used inside the write.
        let dayIndex = currentIndex
        guard var trip = app.trip, trip.days.indices.contains(dayIndex),
              let index = trip.days[dayIndex].stops.firstIndex(where: { $0.id == id }) else { return }
        change(&trip.days[dayIndex].stops[index])
        withAnimation(.snappy) { app.trip = trip }
    }

    private func toggleArrived(_ stop: TripStop) {
        updateStop(stop.id) { stop in
            if stop.isArrived {
                stop.arrivedAt = nil
                stop.visitedAt = nil
            } else {
                stop.arrivedAt = .now
            }
        }
    }

    private func toggleVisited(_ stop: TripStop) {
        updateStop(stop.id) { stop in
            if stop.isVisited {
                stop.visitedAt = nil
            } else {
                stop.visitedAt = .now
                if stop.arrivedAt == nil { stop.arrivedAt = .now }
            }
        }
    }

    private func stopCard(_ entry: DayPlan.Entry, number: Int, date: Date) -> some View {
        let stop = entry.stop
        let expanded = expandedStop == stop.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                expandedStop = expanded ? nil : stop.id
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Spacer for the visit toggle, which sits on top (a button can't sit inside this one).
                    Color.clear.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(stop.name))
                            .font(.candor(.headline, .semibold))
                            .foregroundStyle(stop.isVisited ? .secondary : .primary)
                            .strikethrough(stop.isVisited, color: .secondary)
                            .multilineTextAlignment(.leading)
                        if entry.isClosed {
                            // Shut, or past last entry, by the time you'd get there.
                            Label(entry.hoursNote ?? L("Closed then"), systemImage: "exclamationmark.triangle.fill")
                                .font(.candor(.caption1, .semibold))
                                .foregroundStyle(Theme.rose)
                        } else {
                            Text("\(timeText(entry.arrival))–\(timeText(entry.departure)) · \(L("%@ there", durationText(entry.stayMinutes)))")
                                .font(.candor(.caption1).monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let note = entry.hoursNote {
                                Label(note, systemImage: "clock")
                                    .font(.candor(.caption1))
                                    .foregroundStyle(.secondary)
                            }
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
            .overlay(alignment: .topLeading) {
                Button { toggleVisited(stop) } label: {
                    // A checkpoint: a faded, dashed circle with the stop number until the
                    // traveller ticks it on arrival, then a solid green tick.
                    ZStack {
                        if stop.isVisited {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Theme.mint, in: .circle)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("\(number)")
                                .font(.candor(.subheadline, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink.opacity(0.55))
                                .frame(width: 34, height: 34)
                                .background(Theme.surface, in: .circle)
                                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.35),
                                                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        }
                    }
                    .contentShape(.circle)
                    .sensoryFeedback(.success, trigger: stop.isVisited) { _, now in now }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stop.isVisited ? L("Undo visited: %@", L(stop.name)) : L("Mark as visited: %@", L(stop.name)))
                .accessibilityIdentifier("tripVisit")
            }

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
                    Button { toggleVisited(stop) } label: {
                        Label(stop.isVisited ? L("Visited") : L("Mark as visited"),
                              systemImage: stop.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.candor(.subheadline, .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.mint)
                    PlaceGuideSection(stop: stop, leg: entry.leg)
                }
                .transition(.candorReveal)
            }
        }
        .card(cornerRadius: 16, padding: 14)
    }

    private var dayButtons: some View {
        HStack(spacing: 10) {
            Button { showAddPlace = true } label: {
                Label(L("Add a place"), systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(kind: .filled, height: 50))
            Button { showEditDay = true } label: {
                Label(L("Edit day"), systemImage: "pencil")
            }
            .buttonStyle(PillButtonStyle(kind: .outline, height: 50))
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
                    modeStrip
                    ForEach(leg.sortedOptions) { option in
                        optionCard(option)
                    }
                    if leg.hasCoordinates && leg.km >= 1.5 {
                        LiveTransitSection(from: leg.fromCoordinate, to: leg.toCoordinate)
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

    /// Every way at a glance: mode, time, fare.
    private var modeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(leg.sortedOptions) { option in
                    VStack(spacing: 4) {
                        Image(systemName: option.mode.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(option.mode.color.gradient, in: .circle)
                        Text(option.mode.title).font(.candor(.caption1, .semibold))
                        Text(durationText(option.minutes)).font(.candor(.caption2)).foregroundStyle(.secondary)
                        Text(option.fareText).font(.candor(.caption2, .bold).monospacedDigit()).foregroundStyle(option.mode.color)
                    }
                    .frame(width: 78)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay {
                        if option.mode == leg.best {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .strokeBorder(option.mode.color, lineWidth: 1.5)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
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

            if option.mode == .auto || option.mode == .cab || option.mode == .bikeTaxi {
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

/// Candor's places by category, plus Google Maps search for anywhere else.
struct AddPlaceSheet: View {
    let dayIndex: Int
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var category: SpotCategory?
    @State private var query = ""
    @State private var results: [GooglePlace] = []
    @State private var isSearching = false
    /// Where an added place went, when not where it was asked, or why it couldn't go in.
    @State private var notice: String?
    @FocusState private var searchFocused: Bool

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
                if let notice {
                    Section {
                        Label(notice, systemImage: "clock.badge.exclamationmark")
                            .font(.candor(.subheadline, .medium))
                            .foregroundStyle(Theme.rose)
                    }
                }
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
                    Section(L("Google Maps")) {
                        if isSearching && results.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        ForEach(results.prefix(8)) { item in
                            let name = item.name
                            let coordinate = item.coordinate
                            let added = stops.contains {
                                $0.spotID == nil && $0.name == name
                                    && abs($0.latitude - coordinate.latitude) < 0.0005
                                    && abs($0.longitude - coordinate.longitude) < 0.0005
                            }
                            placeRow(name: name, detail: item.address ?? "", icon: "mappin",
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
            .searchFocused($searchFocused)
            .task {
                // Ready to type the moment the sheet is up.
                try? await Task.sleep(for: .milliseconds(450))
                searchFocused = true
            }
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
                // Debounce: wait for typing to pause before asking Google Maps.
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

    /// Adds the place at a time it's open, and says where it went or why it couldn't.
    private func add(_ stop: TripStop) {
        guard app.trip?.days.indices.contains(dayIndex) == true else { return }
        Task {
            let result = await app.addPlace(stop, preferring: dayIndex, location: location)
            withAnimation(.snappy) {
                switch result {
                case .added(let day, let moved):
                    notice = moved ? L("%1$@ would be closed by then on day %2$@, so it's on day %3$@.", L(stop.name), dayIndex + 1, day + 1) : nil
                case .alreadyThere(let day):
                    notice = L("%1$@ is already on day %2$@.", L(stop.name), day + 1)
                case .noOpenSlot(let hours):
                    notice = L("%@ wouldn't be open when you could get there on any day.", L(stop.name)) + (hours.map { " (\($0))" } ?? "")
                }
            }
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
