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

    private let suggestions = [
        "Auto to India Gate, driver wants ₹300",
        "Is ₹40 fair for a 1 litre water bottle?",
        "Plan my day in Delhi",
        "A man says my hotel is closed"
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    shieldCard
                    quickActions
                    askCandor
                    scamOfTheDay
                    if !app.records.isEmpty { recentChecks }
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

    // MARK: Sections

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Namaste, \(app.persona.firstName)")
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

    private var shieldCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Fair-price shield", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                Text(app.hasGemini ? "Gemini live" : "Offline mode")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint((app.hasGemini ? Theme.mint : Theme.saffron).opacity(0.4)), in: .capsule)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.totalFlaggedINR > 0 ? app.homeAmount(app.totalFlaggedINR) : CurrencyService.format(0, code: app.persona.homeCurrency))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("overcharge flagged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                stat("\(app.records.count)", "checks")
                stat("\(app.overchargesCaught)", "caught")
                stat(inr(app.totalFlaggedINR), "in rupees")
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { tab = .scan } label: {
                        Label("Scan a price", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.saffron)

                    Button { path.append(.ride) } label: {
                        Label("Check a ride", systemImage: "car.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glass)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.saffron.opacity(0.10)), in: .rect(cornerRadius: 32))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tools")
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(QuickAction.all) { action in
                        Button { path.append(action.route) } label: {
                            VStack(spacing: 10) {
                                Image(systemName: action.icon)
                                    .font(.title2)
                                    .foregroundStyle(action.color)
                                    .frame(height: 28)
                                Text(action.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
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
                SectionHeader(title: "Ask Candor", subtitle: "Your agent checks fares, prices and scams for you")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            tab = .agent
                            Task { await agent.send(suggestion) }
                        } label: {
                            Text(suggestion)
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
                    Text("SCAM OF THE DAY").font(.caption2.weight(.bold)).foregroundStyle(Theme.rose)
                    Text(scam.title).font(.headline).foregroundStyle(.primary)
                    Text(scam.whatToDo)
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
                SectionHeader(title: "Recent checks")
                Button("See all") { path.append(.history) }
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
            Text(app.currency.isLive ? "Live rate" : "Indicative")
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
                Text(record.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(record.date.formatted(.relative(presentation: .named)))
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
