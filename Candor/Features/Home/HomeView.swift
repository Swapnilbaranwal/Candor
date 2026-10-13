import SwiftUI

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var checkPath: [CheckRoute]
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent

    /// Opens the demo: one tap from Home to the agent's trail and a verdict card.
    private let demoPrompt = "Auto to India Gate, driver wants ₹300"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header.reveal(0)
                    searchBar.reveal(1)
                    heroCard.reveal(2)
                    HomeBaseCard()
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: app.home?.name)
                        .reveal(3)
                    checkCard.reveal(4)
                    toolTiles.reveal(5)
                    scamOfTheDay.reveal(6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Opens a tool on the Check tab.
    private func openCheck(_ route: CheckRoute) {
        checkPath = [route]
        tab = .check
    }

    /// Sends a ready-made prompt to the agent. The bubble shows it in the traveller's language;
    /// the offline agent, which matches English keywords, gets the English original.
    private func ask(_ prompt: String) {
        tab = .agent
        Task { await agent.send(L(prompt), canonical: prompt) }
    }

    // MARK: Header

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return L("Good morning")
        case 12..<17: return L("Good afternoon")
        default: return L("Good evening")
        }
    }

    private var today: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localizer.shared.locale))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("\(greeting) · \(today)")
                } icon: {
                    Image(systemName: DayPeriod.now().symbol)
                        .symbolEffect(.breathe, options: .repeating)
                }
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(L("Namaste, %@", app.persona.firstName))
                    .font(.heading(.largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 5) {
                    Image(systemName: "location.fill").foregroundStyle(Theme.saffron)
                    Text(location.placeLabel)
                }
                .font(.candor(.caption1, .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { tab = .profile } label: {
                Text(app.persona.initials)
                    .font(.heading(.headline))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(Theme.surface, in: .circle)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(app.hasGemini ? Theme.mint : Theme.saffron)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    }
                    .shadow(color: Theme.shadow, radius: 12, y: 6)
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, 12)
    }

    // MARK: Search

    /// Ask anything (opens the agent), or point the camera at a price.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { tab = .agent } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(Theme.saffron)
                    Text(L("Ask Candor anything…"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.candor(.body))
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(Theme.surface, in: .capsule)
                .shadow(color: Theme.shadow, radius: 12, y: 6)
            }
            .buttonStyle(.pressable)

            Button { openCheck(.scan) } label: {
                CircleIcon(systemName: "camera.viewfinder", size: 56, filled: true)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(L("Scan a price"))
        }
    }

    // MARK: Hero: the city and today's plan

    private var city: City { app.trip?.cityStay(on: .now)?.city ?? .delhi }

    private var heroTitle: String {
        guard let trip = app.trip, !trip.days.isEmpty else { return L("Plan your days in %@", L(city.name)) }
        return trip.days[trip.todayIndex].displayTitle
    }

    private var heroSubtitle: String {
        guard let trip = app.trip, !trip.days.isEmpty else { return L("Places, travel times and fair fares between them.") }
        return tripCityLine(trip, index: trip.todayIndex)
    }

    private var heroCard: some View {
        Button { tab = .trip } label: {
            VStack(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    CityScene()
                        .frame(height: 210)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    Label(L(city.name), systemImage: "mappin.circle.fill")
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.25), in: .capsule)
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Floating3D(.indiaGate, size: 104, symbol: "building.columns.fill")
                        .offset(x: -6, y: 26)
                }

                if let trip = app.trip, trip.days.count > 1 {
                    PageDots(count: min(trip.days.count, 7), index: min(trip.todayIndex, 6), color: Theme.ink)
                }

                VStack(spacing: 4) {
                    Text(heroTitle)
                        .font(.heading(.title3))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text(heroSubtitle)
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                interestTags

                todayStops
            }
            .padding(10)
            .padding(.bottom, 6)
            .background(Theme.surface, in: .rect(cornerRadius: 30, style: .continuous))
            .shadow(color: Theme.shadow, radius: 18, y: 8)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("homePlanTrip")
    }

    private static let interestIcons: [String: String] = [
        "Heritage": "building.columns.fill", "Street food": "fork.knife", "Markets": "bag.fill",
        "Spiritual": "sparkles", "Art & crafts": "paintpalette.fill", "Nightlife": "moon.stars.fill",
        "Nature": "leaf.fill", "Photography": "camera.fill"
    ]

    private var interestTags: some View {
        let picked = app.persona.interests.isEmpty ? ["Heritage", "Street food", "Markets"] : Array(app.persona.interests.prefix(3))
        return HStack(spacing: 8) {
            ForEach(picked, id: \.self) { interest in
                TagPill(title: L(interest), icon: Self.interestIcons[interest] ?? "star.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Theme.canvas.opacity(0.6), in: .capsule)
    }

    /// Today's first stops, timed, with how to get there and the fair fare.
    @ViewBuilder
    private var todayStops: some View {
        if let trip = app.trip, !trip.days.isEmpty {
            let index = trip.todayIndex
            let start = location.dayStart(trip: trip, day: index)
            let plan = TripPlanner.dayPlan(trip.days[index], date: trip.date(ofDay: index), origin: start.coordinate,
                                           originName: start.name, style: app.persona.travelStyle,
                                           city: trip.cityStay(ofDay: index)?.city,
                                           likesWalking: app.persona.hasTaste("Happy to walk"))
            if !plan.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plan.entries.prefix(3).enumerated()), id: \.element.id) { number, entry in
                        tripRow(number: number + 1, entry: entry)
                    }
                    if plan.entries.count > 3 {
                        Text(L("+ %@ more", plan.entries.count - 3))
                            .font(.candor(.caption1, .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    /// "Delhi · Day 2 of 3"
    private func tripCityLine(_ trip: Trip, index: Int) -> String {
        let day = L("Day %1$@ of %2$@", index + 1, trip.days.count)
        guard let city = trip.cityStay(ofDay: index)?.city else { return day }
        return L(city.name) + " · " + day
    }

    private func tripRow(number: Int, entry: DayPlan.Entry) -> some View {
        let option = entry.leg.bestOption
        let visited = entry.stop.isVisited
        return HStack(spacing: 12) {
            Group {
                if visited {
                    Image(systemName: "checkmark").font(.candor(.subheadline, .bold))
                } else {
                    Text("\(number)").font(.candor(.subheadline, .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(visited ? Theme.mint : Theme.ink, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(entry.stop.name))
                    .font(.candor(.subheadline, .semibold))
                    .foregroundStyle(visited ? .secondary : .primary)
                    .strikethrough(visited, color: .secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: option.mode.icon).foregroundStyle(option.mode.color)
                    Text("\(option.mode.title) · \(durationText(option.minutes)) · \(option.fareText)")
                }
                .font(.candor(.caption1))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(timeText(entry.arrival))
                .font(.candor(.caption1, .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Fair-price check

    /// Candor's core job: judge the price you're being quoted right now.
    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("What are you being asked to pay?"))
                        .font(.heading(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Candor tells you the fair price, how far over the ask is, and what to say."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Floating3D(.camera, size: 76, symbol: "camera.viewfinder")
            }

            HStack(spacing: 10) {
                Button { openCheck(.scan) } label: {
                    Label(L("Scan a price"), systemImage: "camera.viewfinder")
                }
                .buttonStyle(PillButtonStyle(kind: .filled, height: 50))

                Button { openCheck(.ride) } label: {
                    Label(L("Check a ride"), systemImage: "car.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .outline, height: 50))
            }

            Button { ask(demoPrompt) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(Theme.saffron)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Try an example"))
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(.secondary)
                        Text(L(demoPrompt))
                            .font(.candor(.subheadline, .medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Theme.accentSoft, in: .rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("homeExample")

            if !app.hasGemini {
                Label(L("Offline mode"), systemImage: "wifi.slash")
                    .font(.candor(.caption1, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 20)
    }

    // MARK: Tools

    private struct ToolTile: Identifiable {
        let route: CheckRoute
        let title: String
        let art: Art3D
        let symbol: String
        let tint: Color
        var id: String { title }
    }

    private var tools: [ToolTile] {
        [
            ToolTile(route: .interpreter, title: L("Interpreter"), art: .translator, symbol: "character.bubble.fill", tint: Theme.indigo),
            ToolTile(route: .ride, title: L("Check a ride"), art: .train, symbol: "car.fill", tint: Theme.teal),
            ToolTile(route: .scams, title: L("Scam radar"), art: .pin, symbol: "shield.lefthalf.filled", tint: Theme.rose)
        ]
    }

    private var toolTiles: some View {
        HStack(spacing: 12) {
            ForEach(tools) { tool in
                Button { openCheck(tool.route) } label: {
                    VStack(spacing: 8) {
                        Floating3D(tool.art, size: 58, float: false, symbol: tool.symbol, tint: tool.tint)
                        Text(tool.title)
                            .font(.candor(.footnote, .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: .rect(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.shadow, radius: 12, y: 6)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: Scam of the day

    /// One line a day about a trick worth knowing. Opens Scam radar on the Check tab.
    private var scamOfTheDay: some View {
        let scams = DelhiData.scams
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let scam = scams[day % scams.count]
        return Button { openCheck(.scams) } label: {
            HStack(spacing: 12) {
                Image(systemName: scam.icon)
                    .font(.candor(.body))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.rose, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("SCAM OF THE DAY")).font(.candor(.caption2, .bold)).foregroundStyle(Theme.rose)
                    Text(L(scam.title))
                        .font(.heading(.headline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.pressable)
    }
}

struct RecordRow: View {
    @Environment(AppState.self) private var app
    let record: PriceCheckRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .foregroundStyle(record.verdict.color)
                .frame(width: 40, height: 40)
                .background(record.verdict.color.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(record.title)).font(.candor(.subheadline, .semibold)).lineLimit(1)
                Text(record.date.formatted(.relative(presentation: .named).locale(Localizer.shared.locale)))
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.askedINR.map(inr) ?? inr(record.fairHighINR))
                    .font(.candor(.subheadline, .bold).monospacedDigit())
                Text(record.verdict.title)
                    .font(.candor(.caption1, .semibold))
                    .foregroundStyle(record.verdict.color)
            }
        }
        .card(cornerRadius: 16, padding: 12)
    }
}
