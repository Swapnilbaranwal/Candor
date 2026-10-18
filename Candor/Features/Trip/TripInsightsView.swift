import SwiftUI

extension TripInsight.Kind {
    var icon: String {
        switch self {
        case .event: "party.popper.fill"
        case .food: "fork.knife"
        case .market: "bag.fill"
        case .weather: "cloud.sun.fill"
        case .tip: "lightbulb.fill"
        }
    }

    var tint: Color {
        switch self {
        case .event: Theme.indigo
        case .food: Theme.rose
        case .market: Theme.saffron
        case .weather: Theme.teal
        case .tip: Theme.mint
        }
    }

    var title: String {
        switch self {
        case .event: L("What's on")
        case .food: L("Eat")
        case .market: L("Markets")
        case .weather: L("Weather")
        case .tip: L("Good to know")
        }
    }
}

/// One thing Gemini found for the trip: icon, title, when, a sentence, and the page it came from.
struct InsightRow: View {
    let insight: TripInsight
    var showsCity = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(insight.kind.tint, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(insight.title)
                    .font(.candor(.subheadline, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !insight.detail.isEmpty {
                    Text(insight.detail)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let when = insight.when {
                        Label(when, systemImage: "calendar")
                            .font(.candor(.caption2, .semibold))
                            .foregroundStyle(insight.kind.tint)
                    }
                    if showsCity {
                        Label(L(insight.city), systemImage: "mappin")
                            .font(.candor(.caption2, .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                if let title = insight.sourceTitle {
                    source(title)
                }
            }
            Spacer(minLength: 0)
        }
        .card(cornerRadius: Theme.Radius.medium, padding: 14)
    }

    @ViewBuilder
    private func source(_ title: String) -> some View {
        let label = Label(title, systemImage: "globe")
            .font(.candor(.caption2))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        if let link = insight.sourceURL, let url = URL(string: link) {
            Link(destination: url) { label }
        } else {
            label
        }
    }
}

/// "Found for your dates" on a trip day: what Gemini found on the web for this city, side by side.
struct TripInsightsSection: View {
    let insights: [TripInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.saffron)
                Text(L("Found for your dates")).font(.heading(.title3))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(insights) { insight in
                        InsightRow(insight: insight)
                            .frame(width: 270)
                    }
                }
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}
