import SwiftUI

/// First run, in four short steps: the trip (cities, dates, stays), who's going, how you like
/// to travel, and you. Then Candor sets itself up (the "recipe") and offers to plan the days
/// with Gemini, showing everything it found before opening the trip.
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
    @State private var recipe: [RecipeStep] = []
    @State private var recipeDone = 0
    /// After the setup steps: ask whether Candor should plan the days.
    @State private var askToPlan = false
    @State private var isPlanning = false
    /// What the planner is doing right now, newest last.
    @State private var planLog: [String] = []
    /// The finished plan, shown before the trip opens.
    @State private var plannedTrip: Trip?
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
                                .font(.heading(.largeTitle))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(step.subtitle)
                                .font(.candor(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .reveal(0)
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
                withAnimation(.snappy) {
                    stops.append(stop)
                    stops.sort { $0.arrival < $1.arrival }
                }
            }
        }
        .sheet(item: $editingStop) { stop in
            CityStopSheet(editing: stop, suggestedArrival: stop.arrival) { updated in
                if let index = stops.firstIndex(where: { $0.id == updated.id }) { stops[index] = updated }
                withAnimation(.snappy) { stops.sort { $0.arrival < $1.arrival } }
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
                    .fill(item.rawValue <= step.rawValue ? Theme.ink : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(.smooth, value: step)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibilityElement()
        .accessibilityLabel(L("Step %1$@ of %2$@", step.rawValue + 1, Step.allCases.count))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .trip {
                Button {
                    withAnimation(.smooth) { step = Step(rawValue: step.rawValue - 1) ?? .trip }
                } label: {
                    CircleIcon(systemName: "chevron.left", size: 56)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(L("Back"))
            }
            Button(action: next) {
                HStack(spacing: 8) {
                    Text(step == .you ? L("Build my travel persona") : L("Continue"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.pill)
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
        VStack(alignment: .leading, spacing: 14) {
            JourneyArt(from: stops.first.map { L($0.city.name) },
                       to: stops.count > 1 ? stops.last.map { L($0.city.name) } : nil)
                .frame(height: 190)
                .shadow(color: Theme.shadow, radius: 14, y: 8)
                .reveal(1)

            VStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { number, stop in
                    Button { editingStop = stop } label: {
                        stopRow(stop, number: number + 1, isLast: number == stops.count - 1)
                    }
                    .buttonStyle(.pressable)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            Button { addingStop = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.ink, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stops.isEmpty ? L("Add your first city") : L("Add another city"))
                            .font(.candor(.headline, .semibold))
                            .foregroundStyle(.primary)
                        Text(L("City, dates and where you're staying"))
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.surface.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.large))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.large)
                        .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                }
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("addCity")
            .reveal(2)

            if !stops.isEmpty {
                Label(tripSummary, systemImage: "calendar")
                    .font(.candor(.subheadline, .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tripSummary: String {
        let trip = Trip(cities: stops, party: party, travellers: travellers)
        let cities = stops.count == 1 ? L(stops[0].city.name) : L("%@ cities", stops.count)
        return L("%1$@ · %2$@ days", cities, trip.plannedDayCount)
    }

    /// One city as a stop on a route: numbered dot, a line down to the next city, and a card.
    private func stopRow(_ stop: CityStay, number: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(.candor(.subheadline, .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.saffron, in: .circle)
                if !isLast {
                    Rectangle()
                        .fill(Theme.saffron.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stop.city.displayName).font(.heading(.title3))
                    Text(dateRange(stop) + " · " + L("%@ days", stop.dayCount))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                    if let stay = stop.stay {
                        Label(stay.name, systemImage: "bed.double.fill")
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if stop.wantsStaySuggestions {
                        Label(L("Wants stay suggestions"), systemImage: "sparkles")
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    CoverageLabel(coverage: stop.city.coverage)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.candor(.footnote, .semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 16)
            .padding(.bottom, isLast ? 0 : 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dateRange(_ stop: CityStay) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Localizer.shared.locale)
        return stop.arrival.formatted(style) + "–" + stop.departure.formatted(style)
    }

    // MARK: Step 2: who's going

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(TravelParty.allCases.enumerated()), id: \.element.id) { index, option in
                    partyCard(option)
                        .reveal(index + 1)
                }
            }
            if let party, party.fixedCount == nil {
                travellersCounter(for: party)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func partySubtitle(_ option: TravelParty) -> String {
        switch option {
        case .solo: L("Just me, at my own pace")
        case .couple: L("The two of us")
        case .family: L("With kids or parents")
        case .group: L("A group of friends")
        }
    }

    private func partyCard(_ option: TravelParty) -> some View {
        let selected = party == option
        return Button {
            withAnimation(.snappy) {
                party = selected ? nil : option
                if option.fixedCount == nil, travellers == nil {
                    travellers = option == .family ? 3 : 4
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                PartyArt(party: option, isSelected: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.heading(.headline)).foregroundStyle(.primary)
                    Text(partySubtitle(option))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.large)
                    .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Theme.ink : Color.primary.opacity(0.2))
                    .padding(12)
                    .contentTransition(.symbolEffect(.replace))
            }
            .shadow(color: Theme.shadow, radius: 12, y: 6)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "How many of you?" with big minus and plus, and a little crowd that grows.
    private func travellersCounter(for party: TravelParty) -> some View {
        let count = travellers ?? 3
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("How many of you?")).font(.candor(.headline, .semibold))
                    Text(L("Travellers: %@", count))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    counterButton("minus", enabled: count > 2) { travellers = count - 1 }
                    Text("\(count)")
                        .font(.display(size: 28, .bold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(count)))
                        .frame(minWidth: 34)
                    counterButton("plus", enabled: count < 20) { travellers = count + 1 }
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<min(count, 10), id: \.self) { index in
                    Image(systemName: "person.fill")
                        .font(.system(size: index % 3 == 2 ? 13 : 16))
                        .foregroundStyle(PartyArt(party: party).tint.opacity(0.5 + 0.5 * Double(10 - index) / 10))
                        .transition(.scale.combined(with: .opacity))
                }
                if count > 10 {
                    Text("+\(count - 10)").font(.candor(.caption1, .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 16)
        .animation(.snappy, value: count)
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: travellers = min(count + 1, 20)
            case .decrement: travellers = max(count - 1, 2)
            @unknown default: break
            }
        }
    }

    private func counterButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .frame(width: 40, height: 40)
                .background(Theme.canvas, in: .circle)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }

    // MARK: Step 3: taste

    private var tasteStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(L("Travel style"))
                HStack(spacing: 10) {
                    ForEach(TravelStyle.allCases) { style in
                        styleCard(style)
                    }
                }
            }
            .reveal(1)

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(L("What do you love?"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    ForEach(DelhiData.interests, id: \.self) { interest in
                        interestTile(interest)
                    }
                }
            }
            .reveal(2)

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(L("Your preferences"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Persona.tasteOptions, id: \.self) { taste in
                        tasteTile(taste)
                    }
                }
            }
            .reveal(3)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.heading(.title3))
    }

    private func styleCard(_ style: TravelStyle) -> some View {
        let selected = draft.travelStyle == style
        return Button {
            withAnimation(.snappy) { draft.travelStyle = style }
        } label: {
            VStack(spacing: 8) {
                StyleArt(style: style, isSelected: selected)
                Text(style.title).font(.candor(.subheadline, .semibold)).foregroundStyle(.primary)
                Text(style.priceLevel)
                    .font(.candor(.caption1, .bold))
                    .foregroundStyle(style.gradient[1])
                Text(style.detail)
                    .font(.candor(.caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium + 4))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium + 4)
                    .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 2)
            }
            .shadow(color: Theme.shadow, radius: 10, y: 5)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func interestTile(_ interest: String) -> some View {
        let selected = draft.interests.contains(interest)
        let tint = InterestArt.tint(interest)
        return Button {
            withAnimation(.snappy) {
                if let index = draft.interests.firstIndex(of: interest) {
                    draft.interests.remove(at: index)
                } else {
                    draft.interests.append(interest)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: InterestArt.icon(interest))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                    .symbolEffect(.bounce, value: selected)
                    .frame(width: 58, height: 58)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.12))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, Theme.ink)
                                .offset(x: 5, y: -5)
                                .transition(.scale)
                        }
                    }
                    .shadow(color: selected ? tint.opacity(0.4) : .clear, radius: 8, y: 4)
                Text(L(interest))
                    .font(.candor(.caption1, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tasteTile(_ taste: String) -> some View {
        let selected = draft.hasTaste(taste)
        return Button {
            withAnimation(.snappy) {
                var list = draft.tastes ?? []
                if let index = list.firstIndex(of: taste) { list.remove(at: index) } else { list.append(taste) }
                draft.tastes = list
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: InterestArt.tasteIcon(taste))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.canvas), in: .circle)
                Text(L(taste))
                    .font(.candor(.caption1, .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 1.5)
            }
            .shadow(color: Theme.shadow, radius: 8, y: 4)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Step 4: you

    private var youStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            passCard.reveal(1)
            languageCard.reveal(2)
            currencyCard.reveal(3)
            Label(L("Set from your phone. Change them any time in Me."), systemImage: "iphone")
                .font(.candor(.caption1))
                .foregroundStyle(.secondary)
        }
    }

    /// A travel pass with the traveller's initials, name, route and a city stamp.
    private var passCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Travel pass").uppercased())
                    .font(.candor(.caption2, .bold))
                    .tracking(1.6)
                Spacer()
                Image(systemName: "globe.asia.australia.fill")
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [Color(hex: 0x1C1E48), Color(hex: 0x30286E)],
                                       startPoint: .leading, endPoint: .trailing))

            HStack(alignment: .center, spacing: 16) {
                Text(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "?" : draft.initials)
                    .font(.display(size: 26, .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(width: 66, height: 66)
                    .background(LinearGradient(colors: [Theme.saffron, Theme.rose],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: Theme.rose.opacity(0.3), radius: 8, y: 4)
                    .animation(.snappy, value: draft.initials)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("What should we call you?"))
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.secondary)
                    TextField(L("Your name"), text: $draft.name)
                        .font(.heading(.title2))
                        .textContentType(.givenName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    Rectangle()
                        .fill(nameFocused ? Theme.ink : Color.primary.opacity(0.15))
                        .frame(height: nameFocused ? 2 : 1)
                        .animation(.snappy, value: nameFocused)
                }
            }
            .padding(18)

            if let route = passRoute {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(Theme.saffron)
                    Text(route)
                        .font(.candor(.subheadline, .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let city = stops.first?.city.name {
                stamp(L(city))
                    .padding(14)
            }
        }
        .shadow(color: Theme.shadow, radius: 14, y: 8)
    }

    private var passRoute: String? {
        guard !stops.isEmpty else { return nil }
        let route = stops.map { L($0.city.name) }.joined(separator: " \(Localizer.shared.arrow) ")
        let trip = Trip(cities: stops, party: party, travellers: travellers)
        return route + " · " + L("%@ days", trip.plannedDayCount)
    }

    /// A round passport stamp, tilted, with the first city's name.
    private func stamp(_ city: String) -> some View {
        VStack(spacing: 1) {
            Text(city.uppercased())
                .font(.candor(.caption2, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Image(systemName: "star.fill").font(.system(size: 7))
            Text(L("Welcome").uppercased())
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(Theme.rose.opacity(0.8))
        .frame(width: 62, height: 62)
        .overlay(Circle().strokeBorder(Theme.rose.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
        .overlay(Circle().strokeBorder(Theme.rose.opacity(0.5), lineWidth: 1).padding(4))
        .rotationEffect(.degrees(-14))
        .accessibilityHidden(true)
    }

    private var languageCard: some View {
        HStack(spacing: 14) {
            iconTile("character.bubble.fill", tint: Theme.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("App language")).font(.candor(.caption1, .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("नमस्ते")
                    Image(systemName: "arrow.right").font(.candor(.caption1, .bold)).foregroundStyle(.tertiary)
                    Text(Self.greeting(draft.languageCode))
                        .contentTransition(.opacity)
                }
                .font(.heading(.title3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Menu {
                Picker(L("App language"), selection: $draft.languageCode) {
                    ForEach(languages, id: \.self) { code in
                        Text(Persona.nativeName(of: code)).tag(code)
                    }
                }
            } label: {
                menuLabel(draft.languageName)
            }
            .accessibilityLabel(L("App language"))
        }
        .card(padding: 16)
        .animation(.snappy, value: draft.languageCode)
    }

    private var currencyCard: some View {
        let flag = CurrencyOption.all.first { $0.code == draft.homeCurrency }?.flag ?? ""
        return HStack(spacing: 14) {
            iconTile("indianrupeesign", tint: Theme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Home currency")).font(.candor(.caption1, .semibold)).foregroundStyle(.secondary)
                Text(L("An auto ride of %1$@ ≈ %2$@", inr(150), app.currency.format(inr: 150, in: draft.homeCurrency)))
                    .font(.candor(.subheadline, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Menu {
                Picker(L("Home currency"), selection: $draft.homeCurrency) {
                    ForEach(CurrencyOption.all) { option in
                        Text("\(option.flag) \(option.code)").tag(option.code)
                    }
                }
            } label: {
                menuLabel("\(flag) \(draft.homeCurrency)")
            }
            .accessibilityLabel(L("Home currency"))
        }
        .card(padding: 16)
        .animation(.snappy, value: draft.homeCurrency)
    }

    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.candor(.caption2, .bold))
        }
        .font(.candor(.subheadline, .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.canvas, in: .capsule)
    }

    /// "Hello" in each app language, to show the switch at a glance.
    private static func greeting(_ code: String) -> String {
        let words = ["en": "Hello", "es": "Hola", "fr": "Bonjour", "de": "Hallo", "it": "Ciao", "pt": "Olá",
                     "ru": "Привет", "ja": "こんにちは", "ko": "안녕하세요", "zh": "你好", "ar": "مرحبا",
                     "he": "שלום", "nl": "Hallo", "tr": "Merhaba", "th": "สวัสดี", "vi": "Xin chào",
                     "id": "Halo", "pl": "Cześć", "hi": "नमस्ते"]
        return words[code] ?? Persona.nativeName(of: code)
    }

    // MARK: Setting up and planning

    @ViewBuilder
    private var buildingOverlay: some View {
        ZStack {
            AppBackground()
            if let plannedTrip {
                planPreview(plannedTrip)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if askToPlan {
                ScrollView {
                    planChoice
                        .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                recipeView
                    .transition(.opacity)
            }
        }
    }

    /// The setup as a recipe in the making: the ingredients drop into the pot one by one.
    private var recipeView: some View {
        let current = recipe.indices.contains(recipeDone) ? recipe[recipeDone] : nil
        return VStack(spacing: 22) {
            Spacer(minLength: 0)
            Text(L("Setting up Candor for you"))
                .font(.heading(.title1))
                .multilineTextAlignment(.center)
            RecipeRing(steps: recipe, done: recipeDone)
                .frame(maxWidth: 330)
                .padding(.horizontal, 20)
            VStack(spacing: 6) {
                if let current {
                    Text(current.title)
                        .font(.candor(.headline, .semibold))
                    Text(current.detail)
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Ready")).font(.candor(.headline, .semibold))
                    Text(L("Everything's in. Enjoy India."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(minHeight: 50)
            .id(recipeDone)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            Text(L("Step %1$@ of %2$@", min(recipeDone + 1, max(recipe.count, 1)), max(recipe.count, 1)))
                .font(.candor(.caption1, .semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    /// Last step: plan the days now, start an empty plan, or skip. Dates and hotel are already known.
    private var planChoice: some View {
        VStack(alignment: .leading, spacing: 18) {
            JourneyArt(from: app.trip?.cities.first.map { L($0.city.name) },
                       to: (app.trip?.cities.count ?? 0) > 1 ? app.trip?.cities.last.map { L($0.city.name) } : nil)
                .frame(height: 170)
                .shadow(color: Theme.shadow, radius: 14, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Want Candor to plan your days?"))
                    .font(.heading(.largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                Text(planSummary)
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPlanning {
                planningCard
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                planOption(title: L("Plan it for me"),
                           subtitle: app.hasGemini
                               ? L("Gemini searches the web for your dates: what's on, where to eat, markets and the best places for you.")
                               : L("Places for your interests, grouped by area, with travel times and fair fares."),
                           icon: "sparkles", tint: Theme.ink, prominent: true, action: planForMe)
                    .accessibilityIdentifier("onboardingPlanForMe")
                planOption(title: L("I have my own plan"),
                           subtitle: L("Start with empty days and add the places you want."),
                           icon: "square.and.pencil", tint: Theme.teal, prominent: false, action: ownPlan)
                Button(L("Later")) { finish(openTrip: false) }
                    .font(.candor(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    /// While planning: each thing the planner does, ticked off as the next one starts.
    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AgentMark(size: 44, isActive: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Planning your days…")).font(.candor(.headline, .semibold))
                    Text(app.hasGemini ? L("Gemini with Google Search") : L("On this phone"))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !planLog.isEmpty {
                Divider()
                ForEach(Array(planLog.enumerated()), id: \.offset) { index, line in
                    let isLast = index == planLog.count - 1
                    HStack(alignment: .top, spacing: 10) {
                        Group {
                            if isLast {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                            }
                        }
                        .frame(width: 20)
                        Text(line)
                            .font(.candor(.subheadline, isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .card()
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

    private func planOption(title: String, subtitle: String, icon: String, tint: Color, prominent: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.ink : .white)
                    .frame(width: 48, height: 48)
                    .background(prominent ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(tint),
                                in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.candor(.headline, .semibold))
                    Text(subtitle)
                        .font(.candor(.caption1))
                        .opacity(0.75)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(prominent ? Theme.surface : Color.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(prominent ? Theme.surface : Color.secondary)
            }
            .padding(16)
            .background(prominent ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.surface),
                        in: .rect(cornerRadius: Theme.Radius.large))
            .shadow(color: Theme.shadow, radius: 12, y: 6)
        }
        .buttonStyle(.pressable)
    }

    // MARK: The plan, before it opens

    private func planPreview(_ trip: Trip) -> some View {
        let places = trip.days.reduce(0) { $0 + $1.stops.count }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.saffron)
                            .symbolEffect(.breathe, options: .repeating)
                        Text(L("Your plan is ready"))
                            .font(.heading(.largeTitle))
                        Text(planSummary)
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .reveal(0)

                    HStack(spacing: 10) {
                        statTile("\(trip.days.count)", L("days"), icon: "calendar", tint: Theme.indigo)
                        statTile("\(places)", L("places"), icon: "mappin.and.ellipse", tint: Theme.rose)
                        statTile("\(trip.insights.count)", L("finds"), icon: "sparkle.magnifyingglass", tint: Theme.teal)
                    }
                    .reveal(1)

                    ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                        dayPreview(day, index: index, trip: trip)
                            .reveal(min(index + 2, 8))
                    }

                    if !trip.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Found for your dates")).font(.heading(.title2))
                            Text(L("Gemini searched the web for what's on, where to eat and what to know."))
                                .font(.candor(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                        ForEach(TripInsight.Kind.allCases, id: \.self) { kind in
                            let items = trip.insights.filter { $0.kind == kind }
                            if !items.isEmpty {
                                Text(kind.title)
                                    .font(.candor(.footnote, .bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ForEach(items) { InsightRow(insight: $0, showsCity: trip.cities.count > 1) }
                            }
                        }
                    }
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Button {
                    finish(openTrip: true)
                } label: {
                    HStack(spacing: 8) {
                        Text(L("Open my trip"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.pill)
                .accessibilityIdentifier("onboardingOpenTrip")
                Button(L("Plan again")) {
                    withAnimation(.smooth) { plannedTrip = nil }
                    planForMe()
                }
                .font(.candor(.subheadline, .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.canvas)
        }
    }

    private func statTile(_ value: String, _ label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.display(size: 26, .bold).monospacedDigit())
            Text(label).font(.candor(.caption1)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: Theme.Radius.medium, padding: 14)
    }

    private func dayPreview(_ day: TripDay, index: Int, trip: Trip) -> some View {
        let date = trip.date(ofDay: index)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Localizer.shared.locale)).uppercased())
                        .font(.candor(.caption2, .bold))
                    Text(date.formatted(.dateTime.day().locale(Localizer.shared.locale)))
                        .font(.display(size: 22, .bold))
                }
                .foregroundStyle(Theme.surface)
                .frame(width: 52, height: 52)
                .background(Theme.ink, in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Day %@", index + 1) + (trip.cities.count > 1 ? " · " + L(trip.cityStay(ofDay: index)?.city.name ?? "") : ""))
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.secondary)
                    Text(day.displayTitle).font(.heading(.title3)).lineLimit(2)
                }
            }
            if day.stops.isEmpty {
                Text(L("A free day. Add places any time."))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { number, stop in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(number + 1)")
                                .font(.candor(.caption1, .bold).monospacedDigit())
                                .foregroundStyle(Theme.saffron)
                                .frame(width: 22, height: 22)
                                .background(Theme.accentSoft, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(stop.name)).font(.candor(.subheadline, .semibold))
                                if let note = stop.note, !note.isEmpty {
                                    Text(note)
                                        .font(.candor(.caption1))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    // MARK: Actions

    private func planForMe() {
        guard let trip = app.trip else { return finish(openTrip: true) }
        planLog = []
        withAnimation(.smooth) { isPlanning = true }
        Task {
            let planned: Trip
            if app.hasGemini {
                planned = await TripPlanner.suggestWithGemini(app: app, trip: trip) { line in
                    withAnimation(.snappy) { planLog.append(line) }
                }
            } else {
                withAnimation(.snappy) { planLog.append(L("Picking places for your interests")) }
                try? await Task.sleep(for: .milliseconds(700))
                planned = TripPlanner.suggest(persona: app.persona, trip: trip)
            }
            app.trip = planned
            withAnimation(.smooth) {
                isPlanning = false
                plannedTrip = planned
            }
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
            if datesChanged {
                trip.days = []
                trip.insights = []
            }
            app.trip = trip
        } else {
            app.trip = Trip(cities: ordered, party: party, travellers: count)
        }
    }

    /// The ingredients of the setup, in order.
    private func recipeSteps(for persona: Persona) -> [RecipeStep] {
        var steps = [
            RecipeStep(icon: "character.bubble.fill", tint: Theme.teal,
                       title: L("Speaking %@", persona.languageName),
                       detail: L("The app and the agent use your language")),
            RecipeStep(icon: "dollarsign.arrow.circlepath", tint: Theme.mint,
                       title: L("Linking %@", persona.homeCurrency),
                       detail: L("Fetching today's exchange rates"))
        ]
        for stop in stops.prefix(3) {
            if let pack = stop.city.pack {
                steps.append(RecipeStep(icon: "map.fill", tint: Theme.saffron,
                                        title: L("Loading the %@ guide", L(stop.city.name)),
                                        detail: L("Fare chart · %1$@ reference prices · %2$@ known scams",
                                                  pack.prices.count, pack.scams.count)))
            } else {
                steps.append(RecipeStep(icon: "map.fill", tint: Theme.saffron,
                                        title: L("Setting up %@", L(stop.city.name)),
                                        detail: L("AI guide with Google Maps. Prices are estimates.")))
            }
        }
        steps += [
            RecipeStep(icon: "car.fill", tint: Theme.indigo,
                       title: L("Fair fares for autos, cabs and metro"),
                       detail: L("Official meters and app prices")),
            RecipeStep(icon: "fork.knife", tint: Theme.rose,
                       title: L("Street food and fair menu prices"),
                       detail: L("What locals pay, dish by dish")),
            RecipeStep(icon: "bag.fill", tint: Color(hex: 0xC8743A),
                       title: L("Markets and bargaining"),
                       detail: L("Opening prices and how far to haggle")),
            RecipeStep(icon: "figure.walk", tint: Theme.teal,
                       title: L("Travel style: %@", persona.travelStyle.title),
                       detail: persona.interests.isEmpty ? L("All interests")
                           : persona.interests.map { L($0) }.joined(separator: ", "))
        ]
        return steps
    }

    private func build() {
        nameFocused = false
        var persona = draft
        persona.name = persona.name.trimmingCharacters(in: .whitespaces)
        saveTrip()
        persona.tripDays = app.trip?.plannedDayCount ?? persona.tripDays
        app.persona = persona
        recipe = recipeSteps(for: persona)
        recipeDone = 0
        withAnimation(.smooth) { isBuilding = true }

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            for item in recipe {
                if item.icon == "dollarsign.arrow.circlepath" {
                    await app.currency.refresh()
                }
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { recipeDone += 1 }
            }
            try? await Task.sleep(for: .milliseconds(900))
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
