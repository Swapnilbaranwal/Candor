import SwiftUI

// MARK: - Travel smart

struct ScamRadarView: View {
    @Binding var tab: AppTab
    @State private var expanded: String?

    /// The few that matter most to a first-time visitor. The agent still knows all of them.
    private static let shown = ["hotel", "meter", "monument", "office", "detour"]
    private var tips: [Scam] {
        Self.shown.compactMap { id in DelhiData.scams.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Most people you'll meet are honest and helpful. These few tips help you travel with confidence."))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(tips) { tip in
                        tipCard(tip)
                    }
                }
                .animation(.candorExpand, value: expanded)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle(L("Travel smart"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tipCard(_ tip: Scam) -> some View {
        let isOpen = expanded == tip.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                expanded = isOpen ? nil : tip.id
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: tip.icon)
                        .foregroundStyle(Theme.teal)
                        .frame(width: 36, height: 36)
                        .background(Theme.teal.opacity(0.14), in: .circle)
                    Text(L(tip.title))
                        .font(.candor(.headline, .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(tip.howItWorks))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                    Text(L(tip.whatToDo))
                        .font(.candor(.subheadline, .medium))
                }
                .padding(.leading, 48)
                .transition(.candorReveal)
            }
        }
        .card(cornerRadius: 16, padding: 14)
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
        return GoogleMapsLink.place(c)
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
