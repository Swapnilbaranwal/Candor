import SwiftUI
import CoreLocation

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var checkPath: [CheckRoute]
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent
    @Environment(AskCandorRouter.self) private var askCandor
    /// Me, pushed as a full page from the avatar.
    @State private var showProfile = false
    @State private var journey: JourneyRequest?

    /// Opens the demo: one tap from Home to the agent's trail and a verdict card.
    private let demoPrompt = "Auto to India Gate, driver wants ₹300"

    var body: some View {
        // The view model does the thinking (today's plan, the next hop, the copy); this view lays it out.
        let model = HomeViewModel(app: app, location: location)
        NavigationStack {
            ScrollView {
                // A plain stack: a dozen cards, all built once when Home opens, so nothing is
                // built mid-scroll. No entrance animations either: Home is simply there.
                VStack(alignment: .leading, spacing: 22) {
                    header(model)
                    // SOS, phrases and the converter one tap away, like stories.
                    QuickToolsRow()
                    heroCard(model)
                    sectionTitle(L("Explore your way"),
                                 subtitle: L("Wander on your own with Candor in your pocket, or walk with a verified local who knows every lane."))
                    TravelCompanionPicker()
                    HomeBaseCard()
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: app.home?.name)
                    sectionTitle(L("Getting around"),
                                 subtitle: L("Every honest way to your next stop, from Metro to cab, with the fare a local would pay."))
                    gettingAround(model.nextLeg)
                    checkCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .statusBarScrim()
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .onChange(of: askCandor.isProfileOpen) { _, open in
                // Launch argument `-candor.tab profile` asks for Me through the router.
                guard open else { return }
                showProfile = true
                askCandor.isProfileOpen = false
            }
            .sheet(item: $journey) { request in
                JourneyView(leg: request.leg, mode: request.mode)
            }
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
        askCandor.open()
        Task { await agent.send(L(prompt), canonical: prompt) }
    }

    // MARK: Header

    private func header(_ model: HomeViewModel) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("\(model.greeting) · \(model.today)")
                } icon: {
                    Image(systemName: DayPeriod.now().symbol)
                        .symbolEffect(.breathe, options: .repeating)
                }
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Text(L("Namaste, %@", model.displayName))
                    .font(.heading(.largeTitle))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 5) {
                    Image(systemName: "location.fill").foregroundStyle(Theme.saffron)
                    Text(model.placeLine)
                }
                .font(.candor(.caption1, .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            // Ask Candor lives up here as one tap, so the first screen is the day, not a search box.
            Button { askCandor.open() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC4621A))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.surface).shadow(color: Theme.shadow, radius: 8, y: 4))
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(L("Ask Candor anything…"))
            .accessibilityIdentifier("homeAsk")
            Button { showProfile = true } label: {
                Text(app.persona.initials)
                    .font(.heading(.headline))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.ink).shadow(color: Theme.shadow, radius: 8, y: 4))
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(app.hasGemini ? Theme.mint : Theme.saffron)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(L("Me"))
            .accessibilityIdentifier("homeProfile")
        }
        .padding(.top, 12)
    }

    // MARK: Hero: the city and today's plan

    /// Today as a postcard: the city under today's sky, the day's title over it, and the first
    /// stops on a glass panel.
    private func heroCard(_ model: HomeViewModel) -> some View {
        Button { tab = .trip } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    CityScene(animated: false, landmarks: model.isDelhi)
                        .frame(height: 230)
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L(model.city.name), systemImage: "mappin.circle.fill")
                            .font(.candor(.caption1, .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.22), in: .capsule)
                        Text(model.heroTitle)
                            .font(.heading(.title2))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(model.heroSubtitle)
                            .font(.candor(.subheadline))
                            .opacity(0.9)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    if model.todayDone {
                        Label(L("Today done"), systemImage: "checkmark.seal.fill")
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.emerald, in: .capsule)
                            .padding(14)
                            .transition(.scale.combined(with: .opacity))
                    } else if model.isDelhi {
                        Floating3D(.indiaGate, size: 96, float: false, symbol: "building.columns.fill")
                            .padding(.trailing, 10)
                            .padding(.top, 14)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    todaySummary(model)
                    HStack {
                        Text(model.hasPlan ? L("Open today's plan") : L("Plan my days"))
                            .font(.candor(.subheadline, .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.brandFill, in: .circle)
                    }
                }
                .padding(16)
            }
            .clipShape(.rect(cornerRadius: 30, style: .continuous))
            // Shadow on a plain shape behind the card, never around the sky and text inside it.
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.shadow, radius: 14, y: 7))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("homePlanTrip")
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.heading(.title2))
            Text(subtitle).font(.candor(.subheadline)).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }


    /// Every way to travel, with what a typical hop should cost: Metro, bus, e-rickshaw, auto,
    /// bike taxi, cab. Tapping one asks Candor how to use it.
    // MARK: Getting around

    private func gettingAround(_ leg: Leg) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill").foregroundStyle(Theme.teal)
                Text(L(leg.from)).lineLimit(1)
                Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(.tertiary)
                Text(L(leg.to)).lineLimit(1).fontWeight(.semibold)
            }
            .font(.candor(.subheadline))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(leg.sortedOptions) { option in
                        Button { journey = JourneyRequest(leg: leg, mode: option.mode) } label: {
                            modeCard(option, best: option.mode == leg.best)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("getAround-\(option.mode.rawValue)")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func modeCard(_ option: LegOption, best: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SoftIcon(symbol: option.mode.icon, tint: option.mode.color, size: 42)
                Spacer()
                if best {
                    Text(L("Best"))
                        .font(.candor(.caption2, .bold))
                        .foregroundStyle(Theme.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.mint.opacity(0.14), in: .capsule)
                }
            }
            Spacer(minLength: 0)
            Text(option.mode.title).font(.heading(.headline)).foregroundStyle(.primary)
            Text(option.fareText)
                .font(.candor(.title3, .bold).monospacedDigit())
                .foregroundStyle(option.mode.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(durationText(option.minutes)).font(.candor(.caption1)).foregroundStyle(.secondary)
        }
        .frame(width: 128, height: 158, alignment: .leading)
        .glossCard(option.mode.color, padding: 14)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Today at a glance: how many places, travel time and fares, and how much is done.
    /// The stop-by-stop detail lives on the Trip tab, one tap away.
    @ViewBuilder
    private func todaySummary(_ model: HomeViewModel) -> some View {
        if model.todayDone {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("All %@ places visited. Lovely day!", model.todayStopCount))
                        .font(.candor(.subheadline, .semibold))
                    if let next = model.nextDayLine {
                        Text(next)
                            .font(.candor(.caption1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        } else if let plan = model.todayPlan, !plan.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    summaryStat("mappin.and.ellipse", L("%@ places", plan.entries.count))
                    summaryStat("clock.fill", durationText(plan.travelMinutes))
                    summaryStat("indianrupeesign", plan.fareText)
                }
                if model.todayVisited > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(model.todayVisited), total: Double(max(model.todayStopCount, 1)))
                            .tint(Theme.emerald)
                        Text(L("%1$@ of %2$@ visited", model.todayVisited, model.todayStopCount))
                            .font(.candor(.caption1, .semibold).monospacedDigit())
                            .foregroundStyle(Theme.emerald)
                    }
                }
            }
        }
    }

    private func summaryStat(_ icon: String, _ text: String) -> some View {
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

    // MARK: Fair-price check

    /// Candor's core job: judge the price you're being quoted right now.
    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("What are you being asked to pay?"))
                        .font(.heading(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Snap the menu or tell us the fare. Candor shows what locals pay, how far over the ask is, and the polite words to bargain."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                PriceTagArt(size: 84)
            }

            HStack(spacing: 10) {
                Button { openCheck(.scan) } label: {
                    Label(L("Scan a price"), systemImage: "camera.viewfinder")
                }
                .buttonStyle(PillButtonStyle(kind: .amber, height: 48))

                Button { openCheck(.ride) } label: {
                    Label(L("Check a ride"), systemImage: "car.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .cream, height: 48))
            }

            Button { openCheck(.interpreter) } label: {
                Label(L("Say it in Hindi"), systemImage: "character.bubble.fill")
            }
            .buttonStyle(PillButtonStyle(kind: .cream, height: 48))
            .accessibilityIdentifier("homePhrases")

            Button { ask(demoPrompt) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(Theme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Try an example"))
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(.secondary)
                        Text(L(demoPrompt))
                            .font(.candor(.subheadline, .medium))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.candor(.caption1, .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .background(Color.white.opacity(0.5), in: .rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("homeExample")

            if !app.hasGemini {
                Label(L("Offline mode"), systemImage: "wifi.slash")
                    .font(.candor(.caption1, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .velvetCard(.saffron, radius: 30, padding: 20)
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

/// Opens the journey screen for one way of getting somewhere.
struct JourneyRequest: Identifiable {
    let id = UUID()
    let leg: Leg
    let mode: TravelMode
}
