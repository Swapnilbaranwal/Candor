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

    /// Actions, selection, progress.
    static let accent = saffron
    /// Fills behind accent-coloured icons and selected rows.
    static let accentSoft = saffron.opacity(0.14)

    /// The page: a warm off-white, near-black in dark mode.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : UIColor(red: 0.975, green: 0.965, blue: 0.95, alpha: 1)
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
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 16
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
        let shape = RoundedRectangle(cornerRadius: min(cornerRadius, Theme.Radius.large), style: .continuous)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? .clear).opacity(0.4), in: shape)
            .background(Theme.surface, in: shape)
    }
}

/// Brand mark: a white seal with a rose tick on the brand gradient. Same mark as the launch screen
/// and splash (`LaunchLogo`), so the logo doesn't change as the app opens.
struct CandorLogo: View {
    var size: CGFloat = 80

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Theme.rose, .white)
            .frame(width: size, height: size)
            .background(Theme.brandGradient, in: .circle)
            .accessibilityHidden(true)
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
            .font(.subheadline.weight(.semibold))
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

// MARK: - Type

/// Headings use Bricolage Grotesque, a warm grotesque with optical sizes; body text stays SF Pro
/// (see DESIGN.md). Hindi uses Mukta. All three ship in Candor/Fonts (SIL Open Font License).
enum CandorType {
    /// PostScript name of the bundled Bricolage variable font (its default instance).
    private static let headingFontName = "BricolageGrotesque-96ptExtraBold"

    /// A heading at `style`'s size, following the reader's text size. Falls back to bold SF Pro.
    static func heading(_ style: UIFont.TextStyle, weight: CGFloat = 700) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        // Variable font: set the weight and the optical size (tighter at large sizes) explicitly.
        let axes: [Int: CGFloat] = [axis("wght"): weight, axis("opsz"): min(max(size, 12), 96)]
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: headingFontName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        let base = font.fontName.hasPrefix("BricolageGrotesque") ? font : .systemFont(ofSize: size, weight: .bold)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: size * 2)
    }

    /// Devanagari text (Hindi phrases), in Mukta, scaled with the reader's text size.
    static func hindi(_ style: UIFont.TextStyle, semibold: Bool = false, size: CGFloat? = nil) -> UIFont {
        let pointSize = size ?? UIFont.preferredFont(forTextStyle: style).pointSize
        let base = UIFont(name: semibold ? "Mukta-SemiBold" : "Mukta-Regular", size: pointSize)
            ?? .systemFont(ofSize: pointSize, weight: semibold ? .semibold : .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    private static func axis(_ tag: String) -> Int {
        tag.unicodeScalars.reduce(0) { ($0 << 8) | Int($1.value) }
    }
}

extension Font {
    /// Screen titles and card headings.
    static func heading(_ style: UIFont.TextStyle) -> Font {
        Font(CandorType.heading(style))
    }

    /// Hindi (Devanagari) text.
    static func hindi(_ style: UIFont.TextStyle, semibold: Bool = false, size: CGFloat? = nil) -> Font {
        Font(CandorType.hindi(style, semibold: semibold, size: size))
    }
}
