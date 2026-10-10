import SwiftUI

/// First run, in four short steps: the trip (cities, dates, stays), who's going, how you like
/// to travel, and you. Then Candor sets itself up and offers to plan the days.
/// Trip details are saved on the Trip; only the person is saved on the Persona.
struct PersonaSetupView: View {
    private enum Step: Int, CaseIterable {
        case trip, people, taste, you

        var title: String {
            switch self {
            case .trip: L("Where are you going?")
            case .people: L("Who's going?")
            case .taste: L("How do you like to travel?")
            case .you: L("A little about you")
            }
        }

        var subtitle: String {
            switch self {
            case .trip: L("Add each city in the order you'll visit, with your dates and where you're staying.")
            case .people: L("Candor plans the pace, places and rides around your group.")
            case .taste: L("Pick what matters. Candor uses it to choose places and get around.")
            case .you: L("Candor speaks your language and shows prices in your money too.")
            }
        }
    }

    @Environment(AppState.self) private var app
    @State private var step: Step = .trip
    @State private var draft = Persona()
    @State private var stops: [CityStay] = []
    @State private var party: TravelParty?
    @State private var travellers: Int?
    @State private var editingStop: CityStay?
    @State private var addingStop = false
    @State private var isBuilding = false
    @State private var buildSteps: [AgentStep] = []
    /// After the setup steps: ask whether Candor should plan the days.
    @State private var askToPlan = false
    @State private var isPlanning = false
    @State private var didLoad = false
    @FocusState private var nameFocused: Bool

    private var languages: [String] {
        var list = DelhiData.languages
        if !list.contains(draft.languageCode) { list.insert(draft.languageCode, at: 0) }
        return list
    }

    private var canContinue: Bool {
        switch step {
        case .trip: !stops.isEmpty
        case .people, .taste: true
        case .you: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.title)
                                .font(.heading(.title2))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(step.subtitle)
                                .font(.candor(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        switch step {
                        case .trip: tripStep
                        case .people: peopleStep
                        case .taste: tasteStep
                        case .you: youStep
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }

            if isBuilding {
                buildingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .sheet(isPresented: $addingStop) {
            CityStopSheet(editing: nil, suggestedArrival: stops.last?.departure ?? .now) { stop in
                withAnimation(.snappy) { stops.append(stop) }
            }
        }
        .sheet(item: $editingStop) { stop in
            CityStopSheet(editing: stop, suggestedArrival: stop.arrival) { updated in
                if let index = stops.firstIndex(where: { $0.id == updated.id }) { stops[index] = updated }
            } onDelete: {
                withAnimation(.snappy) { stops.removeAll { $0.id == stop.id } }
            }
        }
        .onAppear(perform: load)
        // Switch the screen to the chosen language straight away, before the persona is saved.
        .onChange(of: draft.languageCode) { _, code in Localizer.shared.use(code) }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        draft = app.persona
        if let trip = app.trip {
            stops = trip.cities
            party = trip.party
            travellers = trip.travellers
        }
    }

    // MARK: Frame

    /// Four short bars, filled up to the current step.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.saffron : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibilityElement()
        .accessibilityLabel(L("Step %1$@ of %2$@", step.rawValue + 1, Step.allCases.count))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .trip {
                Button(L("Back")) {
                    withAnimation(.smooth) { step = Step(rawValue: step.rawValue - 1) ?? .trip }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button(action: next) {
                Text(step == .you ? L("Build my travel persona") : L("Continue"))
                    .font(.candor(.headline, .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(!canContinue)
            .accessibilityIdentifier("onboardingNext")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func next() {
        nameFocused = false
        if step == .you {
            build()
        } else {
            withAnimation(.smooth) { step = Step(rawValue: step.rawValue + 1) ?? .you }
        }
    }

    // MARK: Step 1: the trip

    private var tripStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { number, stop in
                Button { editingStop = stop } label: { stopRow(stop, number: number + 1) }
                    .buttonStyle(.plain)
            }
            Button { addingStop = true } label: {
                Label(stops.isEmpty ? L("Add your first city") : L("Add another city"), systemImage: "plus")
                    .font(.candor(.headline, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("addCity")
            if !stops.isEmpty {
                Text(tripSummary)
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tripSummary: String {
        let trip = Trip(cities: stops, party: party, travellers: travellers)
        let cities = stops.count == 1 ? L(stops[0].city.name) : L("%@ cities", stops.count)
        return L("%1$@ · %2$@ days", cities, trip.plannedDayCount)
    }

    private func stopRow(_ stop: CityStay, number: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.candor(.subheadline, .bold).monospacedDigit())
                .foregroundStyle(Theme.saffron)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.city.displayName).font(.candor(.headline, .semibold))
                Text(dateRange(stop) + " · " + L("%@ days", stop.dayCount))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                if let stay = stop.stay {
                    Label(stay.name, systemImage: "bed.double")
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                } else if stop.wantsStaySuggestions {
                    Label(L("Wants stay suggestions"), systemImage: "bed.double")
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                }
                CoverageLabel(coverage: stop.city.coverage)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.candor(.footnote))
                .foregroundStyle(.tertiary)
        }
        .card(cornerRadius: 14, padding: 16)
    }

    private func dateRange(_ stop: CityStay) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Localizer.shared.locale)
        return stop.arrival.formatted(style) + "–" + stop.departure.formatted(style)
    }

    // MARK: Step 2: who's going

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            FlowLayout(spacing: 8) {
                ForEach(TravelParty.allCases) { option in
                    Chip(title: option.title, icon: option.icon, isSelected: party == option, tint: Theme.saffron) {
                        withAnimation(.snappy) {
                            party = party == option ? nil : option
                            if option.fixedCount == nil, travellers == nil {
                                travellers = option == .family ? 3 : 4
                            }
                        }
                    }
                }
            }
            if let party, party.fixedCount == nil {
                Stepper(value: Binding(get: { travellers ?? 3 }, set: { travellers = $0 }), in: 2...20) {
                    Text(L("Travellers: %@", travellers ?? 3))
                }
                .card(cornerRadius: 14, padding: 16)
                .transition(.opacity)
            }
        }
    }

    // MARK: Step 3: taste

    private var tasteStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Travel style")).font(.candor(.headline, .semibold))
                Picker(L("Travel style"), selection: $draft.travelStyle) {
                    ForEach(TravelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            chipGroup(title: L("What do you love?"), options: DelhiData.interests,
                      isOn: { draft.interests.contains($0) }) { interest in
                if let index = draft.interests.firstIndex(of: interest) {
                    draft.interests.remove(at: index)
                } else {
                    draft.interests.append(interest)
                }
            }

            chipGroup(title: L("Your preferences"), options: Persona.tasteOptions,
                      isOn: { draft.hasTaste($0) }) { taste in
                var list = draft.tastes ?? []
                if let index = list.firstIndex(of: taste) { list.remove(at: index) } else { list.append(taste) }
                draft.tastes = list
            }
        }
    }

    private func chipGroup(title: String, options: [String], isOn: @escaping (String) -> Bool,
                           toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.candor(.headline, .semibold))
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Chip(title: L(option), isSelected: isOn(option), tint: Theme.saffron) {
                        withAnimation(.snappy) { toggle(option) }
                    }
                }
            }
        }
    }

    // MARK: Step 4: you

    private var youStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("What should we call you?")).font(.candor(.headline, .semibold))
                TextField(L("Your name"), text: $draft.name)
                    .textContentType(.givenName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
            }
            VStack(spacing: 0) {
                HStack {
                    Text(L("App language"))
                    Spacer()
                    Picker(L("App language"), selection: $draft.languageCode) {
                        ForEach(languages, id: \.self) { code in
                            Text(Persona.nativeName(of: code)).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(minHeight: 44)
                Divider()
                HStack {
                    Text(L("Home currency"))
                    Spacer()
                    Picker(L("Home currency"), selection: $draft.homeCurrency) {
                        ForEach(CurrencyOption.all) { option in
                            Text("\(option.flag) \(option.code)").tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(minHeight: 44)
            }
            .card(cornerRadius: 14, padding: 16)
            Text(L("Set from your phone. Change them any time in Me."))
                .font(.candor(.caption1))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Setting up and planning

    private var buildingOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            if askToPlan {
                planChoice
                    .padding(24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                VStack(spacing: 22) {
                    CandorLogo(size: 88)
                    Text(L("Setting up Candor for you"))
                        .font(.heading(.title2))
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(buildSteps) { step in
                            StepRow(step: step)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .card()
                }
                .padding(24)
            }
        }
    }

    /// Last step: plan the days now, start an empty plan, or skip. Dates and hotel are already known.
    private var planChoice: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Want Candor to plan your days?"))
                    .font(.heading(.title2))
                    .fixedSize(horizontal: false, vertical: true)
                Text(planSummary)
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPlanning {
                HStack(spacing: 14) {
                    AgentMark(size: 44, isActive: true)
                    Text(L("Planning your days…")).font(.candor(.headline, .semibold))
                    Spacer(minLength: 0)
                }
                .card()
            } else {
                planOption(title: L("Plan it for me"),
                           subtitle: L("Places for your interests, grouped by area, with travel times and fair fares."),
                           icon: "calendar", tint: Theme.accent, action: planForMe)
                    .accessibilityIdentifier("onboardingPlanForMe")
                planOption(title: L("I have my own plan"),
                           subtitle: L("Start with empty days and add the places you want."),
                           icon: "square.and.pencil", tint: Theme.teal, action: ownPlan)
                Button(L("Later")) { finish(openTrip: false) }
                    .font(.candor(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    /// "Delhi · 4 days from 12 Oct · starting at The Imperial"
    private var planSummary: String {
        guard let trip = app.trip, let first = trip.cities.first else { return "" }
        let start = first.arrival.formatted(.dateTime.day().month(.abbreviated).locale(Localizer.shared.locale))
        let route = trip.cities.map { L($0.city.name) }.joined(separator: " \(Localizer.shared.arrow) ")
        var text = route + " · " + L("%1$@ days from %2$@", trip.plannedDayCount, start)
        if trip.cities.count == 1, let stay = first.stay { text += " · " + L("starting at %@", stay.name) }
        return text
    }

    private func planOption(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.candor(.title3))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tint, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.candor(.headline, .semibold)).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func planForMe() {
        guard let trip = app.trip else { return finish(openTrip: true) }
        withAnimation(.smooth) { isPlanning = true }
        Task {
            app.trip = app.hasGemini
                ? await TripPlanner.suggestWithGemini(app: app, trip: trip)
                : TripPlanner.suggest(persona: app.persona, trip: trip)
            finish(openTrip: true)
        }
    }

    private func ownPlan() {
        if var trip = app.trip {
            trip.days = (0..<trip.plannedDayCount).map { _ in TripDay() }
            app.trip = trip
        }
        finish(openTrip: true)
    }

    private func finish(openTrip: Bool) {
        app.startTab = openTrip ? .trip : nil
        app.completeOnboarding()
    }

    /// The trip's cities, dates, stay and party, kept on the Trip so the plan never asks again.

    /// The trip's cities, dates, stays and party, kept on the Trip so the plan never asks again.
    /// Planned days are kept when only the details change.
    private func saveTrip() {
        let ordered = stops.sorted { $0.arrival < $1.arrival }
        let count = party?.fixedCount == nil ? travellers : nil
        if var trip = app.trip {
            let datesChanged = trip.cities.first?.arrival != ordered.first?.arrival
                || trip.cities.last?.departure != ordered.last?.departure
            trip.cities = ordered
            trip.startDate = ordered.first?.arrival ?? trip.startDate
            trip.party = party
            trip.travellers = count
            if datesChanged { trip.days = [] }
            app.trip = trip
        } else {
            app.trip = Trip(cities: ordered, party: party, travellers: count)
        }
    }

    private func build() {
        nameFocused = false
        var persona = draft
        persona.name = persona.name.trimmingCharacters(in: .whitespaces)
        saveTrip()
        persona.tripDays = app.trip?.plannedDayCount ?? persona.tripDays
        app.persona = persona
        withAnimation(.smooth) { isBuilding = true }

        Task {
            var plan: [(String, String, String)] = [
                ("character.bubble.fill", L("Speaking %@", persona.languageName), L("The app and the agent use your language")),
                ("dollarsign.arrow.circlepath", L("Linking %@", persona.homeCurrency), L("Fetching today's exchange rates"))
            ]
            for stop in stops {
                if let pack = stop.city.pack {
                    plan.append(("checkmark.seal.fill", L("Loading the %@ guide", L(stop.city.name)),
                                 L("Fare chart · %1$@ reference prices · %2$@ known scams", pack.prices.count, pack.scams.count)))
                } else {
                    plan.append(("map.fill", L("Setting up %@", L(stop.city.name)),
                                 L("AI guide with Google Maps. Prices are estimates.")))
                }
            }
            plan.append(("figure.walk", L("Travel style: %@", persona.travelStyle.title),
                         persona.interests.isEmpty ? L("All interests") : persona.interests.map { L($0) }.joined(separator: ", ")))
            for (icon, title, detail) in plan {
                var item = AgentStep(icon: icon, title: title, detail: detail)
                withAnimation(.snappy) { buildSteps.append(item) }
                if icon == "dollarsign.arrow.circlepath" {
                    await app.currency.refresh()
                } else {
                    try? await Task.sleep(for: .milliseconds(380))
                }
                item.state = .done
                withAnimation(.snappy) { upsertStep(item, in: &buildSteps) }
            }
            try? await Task.sleep(for: .milliseconds(400))
            // Someone whose days are already planned (set up before) goes straight in.
            if app.trip?.days.isEmpty == false {
                app.completeOnboarding()
            } else {
                withAnimation(.smooth) { askToPlan = true }
            }
        }
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    PersonaSetupView().environment(AppState())
}
