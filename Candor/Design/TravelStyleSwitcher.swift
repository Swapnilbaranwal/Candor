import SwiftUI

/// Change how you like to travel, any time: Budget, Comfort or Luxury. Candor re-picks the best
/// way to get around and the fares straight away (Metro and buses for Budget, cabs and Candor
/// cars for Luxury). Each option wears its own velvet.
struct TravelStyleSwitcher: View {
    @Environment(AppState.self) private var app
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Travel style")).font(.heading(.title3))
                    Spacer()
                    Text(app.persona.travelStyle.detail)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            HStack(spacing: 10) {
                ForEach(TravelStyle.allCases) { style in
                    option(style)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: app.persona.travelStyle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Travel style"))
    }

    private func velvet(_ style: TravelStyle) -> Velvet {
        switch style {
        case .budget: .pearl
        case .comfort: .saffron
        case .luxury: .emerald
        }
    }

    private func option(_ style: TravelStyle) -> some View {
        let selected = app.persona.travelStyle == style
        let look = velvet(style)
        return Button {
            withAnimation(.snappy) { app.persona.travelStyle = style }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: style.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(style == .luxury ? Theme.gold : look.foreground)
                Text(style.title)
                    .font(.candor(.subheadline, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(style.priceLevel)
                    .font(.candor(.caption2, .semibold))
                    .foregroundStyle(style == .luxury ? Theme.gold : look.secondaryForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 14)
            .velvetCard(look, radius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? (style == .luxury ? Theme.gold : Theme.ink) : .clear, lineWidth: 2.5)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, style == .luxury ? Theme.gold : Theme.ink)
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(selected ? 1 : 0.72)
            .scaleEffect(selected ? 1 : 0.96)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(style.title + ", " + style.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
