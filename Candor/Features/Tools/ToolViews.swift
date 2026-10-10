import SwiftUI

// MARK: - Scam radar

struct ScamRadarView: View {
    @Binding var tab: AppTab
    @Environment(CandorAgent.self) private var agent
    @State private var expanded: String?
    @State private var situation = ""
    @State private var steps: [AgentStep] = []
    @State private var answer: String?
    @State private var isRunning = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                checkCard
                SectionHeader(title: L("Known patterns in Delhi"), subtitle: L("Most people are honest. These are the few tricks worth knowing."))
                VStack(spacing: 10) {
                    ForEach(DelhiData.scams) { scam in
                        scamCard(scam)
                    }
                }
                .animation(.snappy, value: expanded)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(L("Scam radar"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Something feels off?"), systemImage: "shield.lefthalf.filled")
                .font(.candor(.headline, .semibold))
            TextField(L("Describe what's happening, e.g. \"the driver says my hotel is closed\""), text: $situation, axis: .vertical)
                .lineLimit(2...4)
                .focused($focused)
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
            Button {
                Task { await check() }
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) } else { Image(systemName: "magnifyingglass") }
                    Text(L("Check with Candor"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.rose)
            .disabled(situation.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)

            if !steps.isEmpty {
                AgentTrailView(steps: steps, isWorking: isRunning)
            }
            if let answer {
                MarkdownText(text: answer)
                    .padding(14)
                    .background(Theme.rose.opacity(0.14), in: .rect(cornerRadius: 16))
            }
        }
        .card()
    }

    private func scamCard(_ scam: Scam) -> some View {
        let isOpen = expanded == scam.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded = isOpen ? nil : scam.id
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: scam.icon)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.rose, in: .rect(cornerRadius: 12))
                    Text(L(scam.title)).font(.candor(.headline, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L(scam.howItWorks)).font(.candor(.subheadline))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Red flags")).font(.candor(.caption1, .bold)).foregroundStyle(Theme.rose)
                        ForEach(scam.redFlags, id: \.self) { flag in
                            Label(L(flag), systemImage: "flag.fill").font(.candor(.caption1))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("What to do")).font(.candor(.caption1, .bold)).foregroundStyle(Theme.mint)
                        Text(L(scam.whatToDo)).font(.candor(.subheadline))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(cornerRadius: 16, padding: 14)
    }

    private func check() async {
        focused = false
        steps = []
        answer = nil
        isRunning = true
        let result = await agent.run(prompt: "Is this a scam, and what should I do? \(situation)") { step in
            withAnimation(.snappy) { upsertStep(step, in: &steps) }
        }
        withAnimation(.smooth) {
            answer = result.text
            isRunning = false
        }
    }
}

// MARK: - Converter

struct ConverterView: View {
    @Environment(AppState.self) private var app
    @State private var amountText = "500"
    @State private var fromINR = true
    @FocusState private var focused: Bool

    private var code: String { app.persona.homeCurrency }
    private var amount: Double { Double(amountText) ?? 0 }

    private var resultText: String {
        if fromINR {
            return app.homeAmount(amount)
        }
        return inr(app.currency.toINR(amount, from: code) ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 18) {
                    HStack {
                        Text(fromINR ? "🇮🇳 INR" : "\(CurrencyOption.option(code)?.flag ?? "") \(code)")
                            .font(.candor(.headline, .semibold))
                        Spacer()
                        Button {
                            withAnimation(.snappy) { fromINR.toggle() }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        Spacer()
                        Text(fromINR ? "\(CurrencyOption.option(code)?.flag ?? "") \(code)" : "🇮🇳 INR")
                            .font(.candor(.headline, .semibold))
                    }
                    TextField(L("Amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.candor(size: 44, .bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                    Image(systemName: "equal").foregroundStyle(.secondary)
                    Text(resultText)
                        .font(.candor(size: 40, .bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: resultText)
                    Text(app.currency.isLive
                         ? L("ECB reference rate · updated %@", app.currency.lastUpdated?.formatted(date: .omitted, time: .shortened) ?? "")
                         : L("Indicative rate. Connect to the internet for today's rate."))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                .card(cornerRadius: 16, padding: 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Quick reference")).font(.candor(.headline, .semibold))
                    ForEach([20.0, 100, 500, 1000, 2000, 5000], id: \.self) { value in
                        HStack {
                            Text(inr(value)).font(.candor(.subheadline, .semibold).monospacedDigit())
                            Spacer()
                            Text(app.homeAmount(value)).font(.candor(.subheadline).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .card()

                Button {
                    Task { await app.currency.refresh() }
                } label: {
                    Label(L("Refresh rates"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity).frame(height: 30)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(L("Converter"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Emergency

struct EmergencyView: View {
    @Environment(LocationService.self) private var location

    private var mapsURL: URL? {
        let c = location.location?.coordinate ?? location.origin
        return URL(string: "https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                callCard(title: L("Emergency (police, fire, ambulance)"), number: DelhiData.emergencyNumber,
                         display: DelhiData.emergencyNumber, icon: "sos", tint: .red)
                callCard(title: L("Incredible India tourist helpline (24×7, multilingual)"), number: DelhiData.tourismHelpline,
                         display: DelhiData.tourismHelplineDisplay, icon: "phone.bubble.fill", tint: Theme.accent)

                if let mapsURL {
                    ShareLink(item: mapsURL, message: Text(L("I'm here. Candor shared my location."))) {
                        Label(L("Share my location"), systemImage: "location.fill.viewfinder")
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.teal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Quick tips"), systemImage: "lightbulb.fill").font(.candor(.headline, .semibold))
                    Text(L("• Move to a busy, official place: station counter, hotel lobby or police booth."))
                    Text(L("• Never hand over your passport or cards under pressure."))
                    Text(L("• Keep a photo of your passport and visa on your phone."))
                }
                .font(.candor(.subheadline))
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle(L("Emergency"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func callCard(title: String, number: String, display: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.candor(.title2))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(tint, in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.candor(.subheadline)).foregroundStyle(.secondary)
                Text(display).font(.candor(.title2, .bold).monospacedDigit())
            }
            Spacer()
            if let url = URL(string: "tel:\(number)") {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .font(.candor(.title3))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(tint, in: .circle)
                }
            }
        }
        .card()
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if app.records.isEmpty {
                    ContentUnavailableView(L("No checks yet"),
                                           systemImage: "checkmark.shield",
                                           description: Text(L("Scan a price or check a ride and it will appear here.")))
                        .padding(.top, 60)
                } else {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(L("Overcharges caught so far")).font(.candor(.caption1)).foregroundStyle(.secondary)
                            Text(inr(app.totalFlaggedINR)).font(.heading(.title1))
                        }
                        Spacer()
                        Text("≈ " + app.homeAmount(app.totalFlaggedINR)).font(.candor(.headline, .semibold).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .card()
                    ForEach(app.records) { record in
                        RecordRow(record: record)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle(L("History"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
