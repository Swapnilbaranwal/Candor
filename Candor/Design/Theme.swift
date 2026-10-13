import SwiftUI

/// Candor's design tokens. The rules behind them are in DESIGN.md.
enum Theme {
    // Brand and meaning colours. One accent (saffron) for actions and selection; the others
    // only where a colour carries meaning (a fair price, an overcharge, a category, a Metro line).
    static let saffron = Color(red: 1.00, green: 0.58, blue: 0.20)
    static let rose = Color(red: 0.94, green: 0.32, blue: 0.47)
    static let indigo = Color(red: 0.36, green: 0.33, blue: 0.90)
    static let teal = Color(red: 0.12, green: 0.68, blue: 0.74)
    static let mint = Color(red: 0.16, green: 0.74, blue: 0.48)

    /// Ink: the near-black of primary buttons and selection in light mode (white-on-ink pills,
    /// like a printed travel guide). Dark mode uses saffron so filled buttons keep contrast.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1)
            : UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    })

    /// Actions, selection, progress.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.58, blue: 0.20, alpha: 1)
            : UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    })
    /// Fills behind accent-coloured icons and selected rows.
    static let accentSoft = saffron.opacity(0.16)

    /// Soft drop shadow under cards (light mode only reads it).
    static let shadow = Color.black.opacity(0.07)

    /// The page: a warm off-white, near-black in dark mode.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : UIColor(red: 0.953, green: 0.949, blue: 0.941, alpha: 1)
    })
    /// Cards and grouped rows on the canvas.
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1)
            : UIColor.white
    })
    /// Text fields and inputs, so they read as fields on a card.
    static let field = Color.primary.opacity(0.06)
    /// Hairlines and unselected outlines.
    static let hairline = Color.primary.opacity(0.10)

    /// Corner radii: small controls, medium rows and buttons, large cards.
    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 26
    }

    /// The brand mark's gradient. Used for the logo only.
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

// MARK: - Surfaces

/// The page background: a plain, calm canvas. (Glass is kept for system chrome:
/// the tab bar, toolbars and sheets.)
struct AppBackground: View {
    var body: some View {
        Theme.canvas.ignoresSafeArea()
    }
}

extension View {
    /// Padded content on a plain card. A tint washes the card faintly; use it for meaning only.
    func card(cornerRadius: CGFloat = Theme.Radius.large, tint: Color? = nil, padding: CGFloat = 16) -> some View {
        // Older call sites pass 16 for "a card"; they get the current card radius.
        let radius = cornerRadius >= 16 ? Theme.Radius.large : cornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? .clear).opacity(0.4), in: shape)
            .background(Theme.surface, in: shape)
            .shadow(color: Theme.shadow, radius: 18, x: 0, y: 8)
    }
}

/// Candor's agent: the brand seal on a soft accent disc; a spinner while it works.
struct AgentMark: View {
    var size: CGFloat = 56
    var isActive = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentSoft)
            if isActive {
                ProgressView().tint(Theme.accent)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A selectable capsule. Selected: filled with the tint. Unselected: neutral, with a hairline.
struct Chip: View {
    let title: String
    var icon: String?
    var isSelected = false
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.candor(.subheadline, .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surface), in: .capsule)
            .overlay { Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.heading(.title3))
            if let subtitle {
                Text(subtitle).font(.candor(.subheadline)).foregroundStyle(.secondary)
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

// MARK: - Type

/// Candor's type (see DESIGN.md): SF Pro for reading, the system serif (New York) for headings.
/// Both cover every language the app speaks and scale with the reader's text size.
enum CandorType {
    /// SF Pro at a text style's size (scaled with the reader's text size) or a fixed size.
    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, size: CGFloat? = nil) -> UIFont {
        let pointSize = size ?? UIFont.preferredFont(forTextStyle: style).pointSize
        let base = UIFont.systemFont(ofSize: pointSize, weight: weight)
        if size != nil { return base }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Headings: the system serif (New York), like a printed travel guide. Scripts New York
    /// doesn't cover (Devanagari, CJK, Arabic…) fall back to the system font automatically.
    static func heading(_ style: UIFont.TextStyle, weight: UIFont.Weight = .semibold) -> UIFont {
        serif(font(style, weight: weight))
    }

    /// Large display type (wordmark, hero titles) in the serif face.
    static func display(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        serif(UIFont.systemFont(ofSize: size, weight: weight))
    }

    private static func serif(_ base: UIFont) -> UIFont {
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}

extension Font {
    /// Candor's typeface at a text style, e.g. `.candor(.subheadline, .semibold)`.
    static func candor(_ style: UIFont.TextStyle, _ weight: UIFont.Weight = .regular) -> Font {
        Font(CandorType.font(style, weight: weight))
    }

    /// Candor's typeface at a fixed size (logo wordmark, big numbers).
    static func candor(size: CGFloat, _ weight: UIFont.Weight = .regular) -> Font {
        Font(CandorType.font(.body, weight: weight, size: size))
    }

    /// Screen titles and card headings: serif.
    static func heading(_ style: UIFont.TextStyle) -> Font {
        Font(CandorType.heading(style))
    }

    /// Serif display type at a fixed size (wordmark, hero titles).
    static func display(size: CGFloat, _ weight: UIFont.Weight = .semibold) -> Font {
        Font(CandorType.display(size: size, weight: weight))
    }

    /// Hindi (Devanagari) text: the same system font, which includes Devanagari.
    static func hindi(_ style: UIFont.TextStyle, semibold: Bool = false, size: CGFloat? = nil) -> Font {
        Font(CandorType.font(style, weight: semibold ? .semibold : .regular, size: size))
    }
}
