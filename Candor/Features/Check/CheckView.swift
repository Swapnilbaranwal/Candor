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
        Tool(route: .interpreter, title: "Interpreter", subtitle: "Speak and show Hindi", icon: "character.bubble.fill", color: Theme.accent),
        Tool(route: .converter, title: "Converter", subtitle: "Rupees to your money", icon: "dollarsign.arrow.circlepath", color: Theme.mint),
        Tool(route: .emergency, title: "Emergency", subtitle: "Police, help and helplines", icon: "sos", color: .red)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L("Check"))
                        .font(.largeTitle.weight(.bold))
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
            bigButton(title: L("Scan a price"), subtitle: L("Photograph a price tag, menu or bill"),
                      icon: "camera.viewfinder", color: Theme.saffron, route: .scan, identifier: "checkScan")
            bigButton(title: L("Check a ride"), subtitle: L("Fair auto and taxi fares by the official meter"),
                      icon: "car.fill", color: Theme.teal, route: .ride, identifier: "checkRide")
        }
    }

    private func bigButton(title: String, subtitle: String, icon: String, color: Color, route: CheckRoute, identifier: String) -> some View {
        Button { path.append(route) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(color, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func toolTile(_ tool: Tool) -> some View {
        Button { path.append(tool.route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.title2)
                    .foregroundStyle(tool.color)
                    .frame(height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(tool.title))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(L(tool.subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
                    .font(.subheadline.weight(.semibold))
            }
            VStack(spacing: 10) {
                ForEach(app.records.prefix(3)) { record in
                    RecordRow(record: record)
                }
            }
        }
    }
}
