import SwiftUI

enum Theme {
    static let saffron = Color(red: 1.00, green: 0.58, blue: 0.20)
    static let rose = Color(red: 0.94, green: 0.32, blue: 0.47)
    static let indigo = Color(red: 0.36, green: 0.33, blue: 0.90)
    static let teal = Color(red: 0.12, green: 0.68, blue: 0.74)
    static let mint = Color(red: 0.16, green: 0.74, blue: 0.48)

    static let brandGradient = LinearGradient(
        colors: [saffron, rose, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// "₹1,250" style formatting.
func inr(_ value: Double) -> String {
    "₹" + value.formatted(.number.precision(.fractionLength(0)))
}

// MARK: - Animated liquid background

/// A slowly breathing mesh gradient that gives the glass something rich to refract.
struct LiquidBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
        }
        .ignoresSafeArea()
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.35)) * 0.12
        let b = Float(cos(t * 0.27)) * 0.12
        return [
            SIMD2(0, 0), SIMD2(0.5 + a, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + b), SIMD2(0.5 + a, 0.5 - b), SIMD2(1, 0.5 + a),
            SIMD2(0, 1), SIMD2(0.5 - b, 1), SIMD2(1, 1)
        ]
    }

    private var colors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.22, green: 0.08, blue: 0.22), Color(red: 0.08, green: 0.07, blue: 0.24), Color(red: 0.04, green: 0.12, blue: 0.26),
                Color(red: 0.34, green: 0.13, blue: 0.08), Color(red: 0.05, green: 0.05, blue: 0.11), Color(red: 0.04, green: 0.19, blue: 0.23),
                Color(red: 0.11, green: 0.05, blue: 0.19), Color(red: 0.24, green: 0.08, blue: 0.21), Color(red: 0.36, green: 0.17, blue: 0.05)
            ]
        }
        return [
            Color(red: 1.00, green: 0.85, blue: 0.68), Color(red: 1.00, green: 0.78, blue: 0.80), Color(red: 0.85, green: 0.83, blue: 1.00),
            Color(red: 0.99, green: 0.92, blue: 0.85), Color(red: 1.00, green: 0.97, blue: 0.94), Color(red: 0.79, green: 0.93, blue: 0.96),
            Color(red: 0.87, green: 0.95, blue: 0.90), Color(red: 0.93, green: 0.87, blue: 1.00), Color(red: 1.00, green: 0.87, blue: 0.76)
        ]
    }
}

// MARK: - Glass helpers

extension View {
    /// Padded content on a Liquid Glass rounded rectangle.
    func glassCard(cornerRadius: CGFloat = 28, tint: Color? = nil, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(Self.candorGlass(tint: tint, interactive: false), in: .rect(cornerRadius: cornerRadius))
    }

    static func candorGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Brand mark: a glass disc with a gradient "C" and tick.
struct CandorLogo: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: size, height: size)
                .blur(radius: size * 0.18)
                .opacity(0.8)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(Theme.rose.opacity(0.35)), in: .circle)
        }
    }
}

/// Animated orb that represents the agent. Spins faster while it works.
struct AgentOrb: View {
    var size: CGFloat = 56
    var isActive = false

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t * (isActive ? 220 : 40)).degrees.truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [Theme.saffron, Theme.rose, Theme.indigo, Theme.teal, Theme.saffron],
                                          center: .center, angle: .degrees(angle)))
                    .blur(radius: size * 0.12)
                    .scaleEffect(CGFloat(isActive ? 1.0 + 0.06 * sin(t * 4) : 0.95))
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: isActive)
            }
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .circle)
        }
    }
}

/// A selectable glass capsule.
struct GlassChip: View {
    let title: String
    var icon: String?
    var isSelected = false
    var tint: Color = Theme.saffron
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(isSelected ? Glass.regular.tint(tint).interactive() : Glass.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders inline Markdown and turns "* " / "- " list markers into bullets.
struct MarkdownText: View {
    let text: String

    var body: some View {
        Text(Self.attributed(text))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    static func attributed(_ raw: String) -> AttributedString {
        let cleaned = raw
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                    return "• " + trimmed.dropFirst(2)
                }
                if trimmed.hasPrefix("#") {
                    return "**" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) + "**"
                }
                return line
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(raw)
    }
}
