import SwiftUI

enum HomeRoute: Hashable {
    case ride, interpreter, scams, converter, emergency, history
}

private struct QuickAction: Identifiable {
    let route: HomeRoute
    let title: String
    let icon: String
    let color: Color
    var id: HomeRoute { route }

    /// Titles are English keys, shown through `L(…)`.
    static let all: [QuickAction] = [
        QuickAction(route: .ride, title: "Ride fare", icon: "car.fill", color: Theme.teal),
        QuickAction(route: .interpreter, title: "Interpreter", icon: "character.bubble.fill", color: Theme.indigo),
        QuickAction(route: .scams, title: "Scam radar", icon: "shield.lefthalf.filled", color: Theme.rose),
        QuickAction(route: .converter, title: "Converter", icon: "dollarsign.arrow.circlepath", color: Theme.mint),
        QuickAction(route: .emergency, title: "Emergency", icon: "sos", color: .red),
        QuickAction(route: .history, title: "History", icon: "clock.arrow.circlepath", color: Theme.saffron)
    ]
}

struct HomeView: View {
    @Binding var tab: AppTab
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(CandorAgent.self) private var agent
    @State private var path: [HomeRoute] = []

    /// Opens the demo: one tap from Home to the agent's trail and a verdict card.
    private let demoPrompt = "Auto to India Gate, driver wants ₹300"

    private let suggestions = [
        "Is ₹40 fair for a 1 litre water bottle?",
        "A man says my hotel is closed",
        "Plan my day in Delhi"
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    checkCard
                    askCandor
                    scamOfTheDay
                    if !app.records.isEmpty { recentChecks }
                    quickActions
                    rateStrip
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(LiquidBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .ride: RideCheckView()
                case .interpreter: InterpreterView()
                case .scams: ScamRadarView(tab: $tab)
                case .converter: ConverterView()
                case .emergency: EmergencyView()
                case .history: HistoryView()
                }
            }
        }
    }

    /// Sends a ready-made prompt to the agent. The bubble shows it in the traveller's language;
    /// the offline agent, which matches English keywords, gets the English original.
    private func ask(_ prompt: String) {
        tab = .agent
        Task { await agent.send(L(prompt), canonical: prompt) }
    }

    // MARK: Sections

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return L("Good morning")
        case 12..<17: return L("Good afternoon")
        default: return L("Good evening")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Namaste, %@", app.persona.firstName))
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").foregroundStyle(Theme.saffron)
                    Text(location.placeLabel)
                    Text("·")
                    Text(greeting)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { tab = .profile } label: {
                Text(app.persona.initials)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.tint(Theme.indigo).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    /// Candor's one job, first on the screen: judge the price you're being quoted right now.
    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L("Fair-price check"), systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(app.hasGemini ? L("Gemini live") : L("Offline mode"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint((app.hasGemini ? Theme.mint : Theme.saffron).opacity(0.4)), in: .capsule)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("What are you being asked to pay?"))
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Candor tells you the fair price, how far over the ask is, and what to say."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { tab = .scan } label: {
                        Label(L("Scan a price"), systemImage: "camera.viewfinder")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.saffron)

                    Button { path.append(.ride) } label: {
                        Label(L("Check a ride"), systemImage: "car.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glass)
                }
                .font(.subheadline.weight(.semibold))
            }

            // The quickest way to see what Candor does. A plain tinted row, not glass:
            // glass on a glass card has nothing to refract and disappears.
            Button { ask(demoPrompt) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.saffron)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Try an example"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(L(demoPrompt))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Theme.saffron.opacity(0.12), in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeExample")

            if !app.records.isEmpty {
                Divider()
                shieldStats
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.saffron.opacity(0.10)), in: .rect(cornerRadius: 32))
    }

    /// Running total of what Candor has caught. Shown once there is at least one saved check.
    private var shieldStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A labelled stat. Rupees lead, as everywhere else: prices in India are quoted in INR.
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Overcharges caught so far"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(inr(app.totalFlaggedINR))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(app.totalFlaggedINR > 0
                     ? L("Extra you were asked to pay above the fair price.")
                     : L("Every price you checked was fair."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                stat("\(app.records.count)", L("Checks"))
                stat("\(app.overchargesCaught)", L("Overcharges"))
                stat("≈ " + (app.totalFlaggedINR > 0 ? app.homeAmount(app.totalFlaggedINR) : CurrencyService.format(0, code: app.persona.homeCurrency)),
                     L("in %@", app.persona.homeCurrency))
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L("More tools"))
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(QuickAction.all) { action in
                        Button { path.append(action.route) } label: {
                            VStack(spacing: 10) {
                                Image(systemName: action.icon)
                                    .font(.title2)
                                    .foregroundStyle(action.color)
                                    .frame(height: 28)
                                Text(L(action.title))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var askCandor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AgentOrb(size: 40, isActive: agent.isWorking)
                SectionHeader(title: L("Ask Candor"), subtitle: L("Your agent checks fares, prices and scams for you"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            ask(suggestion)
                        } label: {
                            Text(L(suggestion))
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                                .frame(width: 170, height: 64, alignment: .topLeading)
                                .padding(14)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var scamOfTheDay: some View {
        let scams = DelhiData.scams
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let scam = scams[day % scams.count]
        return Button { path.append(.scams) } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: scam.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(Theme.rose), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("SCAM OF THE DAY")).font(.caption2.weight(.bold)).foregroundStyle(Theme.rose)
                    Text(L(scam.title)).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(L(scam.whatToDo))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var recentChecks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: L("Recent checks"))
                Button(L("See all")) { path.append(.history) }
                    .font(.subheadline.weight(.semibold))
            }
            VStack(spacing: 10) {
                ForEach(app.records.prefix(3)) { record in
                    RecordRow(record: record)
                }
            }
        }
    }

    private var rateStrip: some View {
        let code = app.persona.homeCurrency
        let perUnit = app.currency.inrPerUnit[code] ?? 0
        return HStack {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.mint)
            Text("1 \(code) = \(perUnit.formatted(.number.precision(.fractionLength(2)))) INR")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Spacer()
            Text(app.currency.isLive ? L("Live rate") : L("Indicative"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard(cornerRadius: 22, padding: 14)
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
                .glassEffect(.regular.tint(record.verdict.color.opacity(0.3)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(record.title)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(record.date.formatted(.relative(presentation: .named).locale(Localizer.shared.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.askedINR.map(inr) ?? inr(record.fairHighINR))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(record.verdict.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.verdict.color)
            }
        }
        .glassCard(cornerRadius: 22, padding: 12)
    }
}
