import SwiftUI

enum CheckRoute: Hashable {
    case scan, ride, scams, interpreter, converter, emergency, history
}

/// Every fair-price and safety tool in one place: scan a price, check a ride, and the tools that keep you safe.
struct CheckView: View {
    @Binding var tab: AppTab
    @Binding var path: [CheckRoute]
    @Environment(AppState.self) private var app

    private struct Tool: Identifiable {
        let route: CheckRoute
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        var id: CheckRoute { route }
    }

    /// Titles are English keys, shown through `L(…)`.
    private let safetyTools: [Tool] = [
        Tool(route: .scams, title: "Scam radar", subtitle: "Known tricks and what to do", icon: "shield.lefthalf.filled", color: Theme.rose),
        Tool(route: .interpreter, title: "Interpreter", subtitle: "Speak and show Hindi", icon: "character.bubble.fill", color: Theme.sky),
        Tool(route: .converter, title: "Converter", subtitle: "Rupees to your money", icon: "dollarsign.arrow.circlepath", color: Theme.mint),
        Tool(route: .emergency, title: "Emergency", subtitle: "Police, help and helplines", icon: "sos", color: Theme.coral)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Check"))
                            .font(.heading(.largeTitle))
                        Text(L("Know the fair price before you pay, ride safely, and get help the moment you need it."))
                            .font(.candor(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    mainChecks
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: L("Stay safe"))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(safetyTools) { tool in
                                toolTile(tool)
                            }
                        }
                    }
                    if !app.records.isEmpty { recentChecks }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CheckRoute.self) { route in
                switch route {
                case .scan: ScanView(embedded: true)
                case .ride: RideCheckView()
                case .scams: ScamRadarView(tab: $tab)
                case .interpreter: InterpreterView()
                case .converter: ConverterView()
                case .emergency: EmergencyView()
                case .history: HistoryView()
                }
            }
        }
    }

    private var mainChecks: some View {
        VStack(spacing: 12) {
            bigButton(title: L("Scan a price"), subtitle: L("Point at a menu, tag or bill and see what it should cost"),
                      icon: "camera.viewfinder", colors: CardPalette.home, route: .scan, identifier: "checkScan")
            bigButton(title: L("Check a ride"), subtitle: L("The meter fare for autos and taxis, before you get in"),
                      icon: "car.fill", colors: CardPalette.transit, route: .ride, identifier: "checkRide")
        }
    }

    private func bigButton(title: String, subtitle: String, icon: String, colors: [Color], route: CheckRoute, identifier: String) -> some View {
        let velvet: Velvet = route == .scan ? .burgundy : .emerald
        return Button { path.append(route) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(velvet.sheen)
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.heading(.title3))
                    Text(subtitle)
                        .font(.candor(.subheadline))
                        .foregroundStyle(velvet.secondaryForeground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x5C1226))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xFFF8EE), in: .circle)
            }
            .velvetCard(velvet, padding: 18)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func toolTile(_ tool: Tool) -> some View {
        Button { path.append(tool.route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                SoftIcon(symbol: tool.icon, tint: tool.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(tool.title))
                        .font(.candor(.headline, .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(L(tool.subtitle))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.large, style: .continuous))
            .shadow(color: Theme.shadow, radius: 12, y: 6)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(tool.title))
        .accessibilityHint(L(tool.subtitle))
        .accessibilityAddTraits(.isButton)
    }

    private var recentChecks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: L("Recent checks"))
                Button(L("See all")) { path.append(.history) }
                    .font(.candor(.subheadline, .semibold))
            }
            VStack(spacing: 10) {
                ForEach(app.records.prefix(3)) { record in
                    RecordRow(record: record)
                }
            }
        }
    }
}
