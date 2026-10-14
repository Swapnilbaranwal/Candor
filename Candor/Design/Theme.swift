import SwiftUI
import CoreText

/// Candor's design tokens. The rules behind them are in DESIGN.md.
enum Theme {
    // Brand and meaning colours. The brand is a royal indigo-violet with a coral partner (the
    // colours of the logo); the others only where a colour carries meaning (a fair price, an
    // overcharge, a travel mode, a Metro line). No black: the illustrations stay bright.
    static let saffron = Color(red: 1.00, green: 0.66, blue: 0.24)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.36)
    static let rose = Color(red: 0.94, green: 0.32, blue: 0.47)
    static let indigo = Color(red: 0.36, green: 0.33, blue: 0.90)
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let sky = Color(red: 0.25, green: 0.62, blue: 0.98)
    static let teal = Color(red: 0.10, green: 0.66, blue: 0.72)
    static let mint = Color(red: 0.13, green: 0.72, blue: 0.53)

    /// The brand colour: burgundy velvet, for primary buttons and selection. A rose-wine at night.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.78, green: 0.36, blue: 0.46, alpha: 1)
            : UIColor(red: 0.48, green: 0.12, blue: 0.21, alpha: 1)
    })

    /// Actions, selection, progress (the system tint).
    static let accent = ink
    /// Fills behind accent-coloured icons and selected rows: a pale rose.
    static let accentSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.78, green: 0.36, blue: 0.46, alpha: 0.20)
            : UIColor(red: 0.48, green: 0.12, blue: 0.21, alpha: 0.08)
    })
    /// Deep emerald, the partner to burgundy (guides, fair prices, Luxury).
    static let emerald = Color(red: 0.06, green: 0.33, blue: 0.25)
    /// Warm partners from Indian craft: a soft peach and a muted gold.
    static let peach = Color(red: 1.00, green: 0.80, blue: 0.62)
    static let gold = Color(red: 0.91, green: 0.77, blue: 0.42)

    /// The main button fill (solid; kept as a style so buttons and badges share it).
    static let brandFill = LinearGradient(colors: [ink, ink], startPoint: .leading, endPoint: .trailing)

    /// Soft, neutral drop shadow under cards.
    static let shadow = Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.07)

    /// The page: warm ivory by day, a soft charcoal (not black) at night.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.08, blue: 0.10, alpha: 1)
            : UIColor(red: 0.984, green: 0.961, blue: 0.937, alpha: 1)
    })
    /// Cards and grouped rows on the canvas.
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1)
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
        static let large: CGFloat = 28
    }

    /// The brand mark's gradient. Used for the logo only.
    static let brandGradient = LinearGradient(
        colors: [coral, violet, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Gradient pairs for feature cards: clean two-colour washes, never muddy.
enum CardPalette {
    static let guide = [Color(hex: 0x6D5BF0), Color(hex: 0xFF7A6B)]
    static let fair = [Color(hex: 0x1FB58C), Color(hex: 0x2A9FD6)]
    static let words = [Color(hex: 0x3F8CFF), Color(hex: 0x7B5CF5)]
    static let transit = [Color(hex: 0x4B3BCB), Color(hex: 0x2EB5C9)]
    static let safety = [Color(hex: 0xFF6B6B), Color(hex: 0xFFAA4C)]
    static let home = [Color(hex: 0xFFB547), Color(hex: 0xFF7A59)]
    static let night = [Color(hex: 0x23275E), Color(hex: 0x5B3FA8)]

    static func linear(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Gloss cards

/// An elegant light card: the surface washed with a pale tint, a soft glossy sheen along the top,
/// a hairline in the tint and a soft coloured shadow. No dark gradients: content stays dark on light.
struct GlossCard: ViewModifier {
    let tint: Color
    var radius: CGFloat = Theme.Radius.large
    var padding: CGFloat? = nil
    @Environment(\.colorScheme) private var scheme

    /// A soft porcelain card, like the reference: pure white at the top easing to a warm pearl
    /// at the bottom, a hairline of light along the edge, and a wide, soft shadow that lifts it
    /// off the page (with a tight contact shadow underneath so it feels grounded).
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme != .dark
        content
            .padding(padding ?? 0)
            .background {
                shape
                    .fill(LinearGradient(colors: light
                                            ? [Color.white, Color(hex: 0xF6F3EE)]
                                            : [Color(hex: 0x2A2A2E), Color(hex: 0x1E1E22)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.fill(tint.opacity(light ? 0.03 : 0.07)))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(light ? 0.9 : 0.12),
                                                                        Color.black.opacity(light ? 0.05 : 0.2)],
                                                               startPoint: .top, endPoint: .bottom),
                                                lineWidth: 1))
                    // The shadow belongs to the card's shape only. On the whole view it was traced
                    // around every word and icon inside, on every frame.
                    .shadow(color: Color(hex: 0x5A4A3A).opacity(light ? 0.09 : 0.35), radius: 14, y: 7)
            }
    }
}

// MARK: - Velvet cards

/// Rich feature cards with deep, velvety gradients and a silk ribbon of light, for the few
/// moments that should stand out (the reference's peach and emerald panels). Text on them is
/// set with `foreground` / `secondaryForeground`.
enum Velvet {
    /// Peach into marigold: warm, for prices and day highlights. Dark text.
    case saffron
    /// Deep emerald into jade with a mint ribbon: premium, for guides and Luxury. Light text.
    case emerald
    /// Maroon into rose, like temple silk: for Candor Plus and special moments. Light text.
    case maroon
    /// Burgundy velvet, deep wine with a rose-gold sheen: the brand's richest card. Light text.
    case burgundy
    /// Ivory into blush: the quietest velvet, for headers. Dark text.
    case pearl

    var colors: [Color] {
        switch self {
        case .saffron: [Color(hex: 0xFFE2BC), Color(hex: 0xF7B267), Color(hex: 0xEE8A3A)]
        case .emerald: [Color(hex: 0x0B3B2D), Color(hex: 0x10553F), Color(hex: 0x1B7556)]
        case .maroon: [Color(hex: 0x4A1022), Color(hex: 0x7A1E3A), Color(hex: 0xA8405C)]
        case .burgundy: [Color(hex: 0x2E0712), Color(hex: 0x5C1226), Color(hex: 0x8A2340)]
        case .pearl: [Color(hex: 0xFFFDF9), Color(hex: 0xFBEFE4), Color(hex: 0xF5E1D2)]
        }
    }

    /// The silk ribbon's colour.
    var sheen: Color {
        switch self {
        case .saffron: Color(hex: 0xFFF3DD)
        case .emerald: Color(hex: 0x58E0A8)
        case .maroon: Color(hex: 0xFFB3C4)
        case .burgundy: Color(hex: 0xF3C9A8)
        case .pearl: Color.white
        }
    }

    var isDark: Bool { self == .emerald || self == .maroon || self == .burgundy }
    var foreground: Color { isDark ? .white : Color(hex: 0x2B1A10) }
    var secondaryForeground: Color { isDark ? Color.white.opacity(0.75) : Color(hex: 0x2B1A10).opacity(0.65) }
    var shadow: Color {
        switch self {
        case .saffron: Color(hex: 0xC7672A)
        case .emerald: Color(hex: 0x0B3B2D)
        case .maroon: Color(hex: 0x4A1022)
        case .burgundy: Color(hex: 0x2E0712)
        case .pearl: Color(hex: 0x8A6A50)
        }
    }
}

struct VelvetCard: ViewModifier {
    let style: Velvet
    var radius: CGFloat = 28
    var padding: CGFloat? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .foregroundStyle(style.foreground)
            .background {
                ZStack {
                    LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    // The silk ribbon: a soft band of light and a fine thread across the lower half.
                    // Gradients only, no blur: blurs are re-rendered on every scroll frame.
                    SilkRibbon()
                        .fill(LinearGradient(colors: [style.sheen.opacity(0), style.sheen.opacity(style.isDark ? 0.30 : 0.45),
                                                      style.sheen.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                    SilkRibbon(lift: 0.12)
                        .stroke(LinearGradient(colors: [style.sheen.opacity(0), style.sheen.opacity(style.isDark ? 0.55 : 0.75),
                                                        style.sheen.opacity(0.1)],
                                               startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
                    // A soft highlight in the top-left, like light on velvet.
                    RadialGradient(colors: [Color.white.opacity(style.isDark ? 0.10 : 0.35), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 260)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(style.isDark ? 0.12 : 0.5), lineWidth: 1))
                // Shadow on the card's shape only, not traced around the text inside.
                .background(shape.fill(style.colors.last ?? .clear)
                    .shadow(color: style.shadow.opacity(0.24), radius: 16, y: 9))
            }
    }
}

/// A sweeping silk band from the left edge, rising to the right.
nonisolated struct SilkRibbon: Shape {
    var lift: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * (0.92 - lift)))
        p.addCurve(to: CGPoint(x: w, y: h * (0.48 - lift)),
                   control1: CGPoint(x: w * 0.35, y: h * (0.70 - lift)),
                   control2: CGPoint(x: w * 0.62, y: h * (0.92 - lift)))
        p.addLine(to: CGPoint(x: w, y: h * (0.62 - lift)))
        p.addCurve(to: CGPoint(x: 0, y: h * (1.02 - lift)),
                   control1: CGPoint(x: w * 0.62, y: h * (1.04 - lift)),
                   control2: CGPoint(x: w * 0.35, y: h * (0.82 - lift)))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// A light, glossy card tinted with `tint`. Pass `padding` to pad the content first.
    func glossCard(_ tint: Color, radius: CGFloat = Theme.Radius.large, padding: CGFloat? = nil) -> some View {
        modifier(GlossCard(tint: tint, radius: radius, padding: padding))
    }

    /// A rich velvet feature card (see `Velvet`).
    func velvetCard(_ style: Velvet, radius: CGFloat = 28, padding: CGFloat? = nil) -> some View {
        modifier(VelvetCard(style: style, radius: radius, padding: padding))
    }
}

/// A soft round or rounded-square icon badge: the symbol in its colour on a pale disc.
struct SoftIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44
    var rounded = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: rounded ? size * 0.32 : size / 2, style: .continuous))
    }
}

/// "₹1,250" style formatting.
func inr(_ value: Double) -> String {
    "₹" + value.formatted(.number.precision(.fractionLength(0)))
}

// MARK: - Surfaces

/// The page background: a plain, calm canvas. (Glass is kept for system chrome:
/// the tab bar, toolbars and sheets.)
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    /// Warm ivory easing into sandstone, with a faint rose-gold glow at the top: the colour of
    /// an old haveli wall in morning light. A deep plum-charcoal at night. Static gradients only,
    /// so it costs nothing while scrolling.
    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark
                               ? [Color(hex: 0x1C1519), Color(hex: 0x120F13)]
                               : [Color(hex: 0xFFF9F2), Color(hex: 0xF8EEE3), Color(hex: 0xF3E6D9)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(scheme == .dark ? Color(hex: 0x6B1E35) : Color(hex: 0xF4CDB8)).opacity(0.35), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Padded content on a plain card. A tint washes the card faintly; use it for meaning only.
    func card(cornerRadius: CGFloat = Theme.Radius.large, tint: Color? = nil, padding: CGFloat = 16) -> some View {
        // Older call sites pass 16 for "a card"; they get the current card radius.
        let radius = cornerRadius >= 16 ? Theme.Radius.large : cornerRadius
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glossCard(tint ?? .clear, radius: radius)
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
    /// Every font is built once and reused. Building one (finding the face, scaling it for the
    /// reader's text size) on every redraw, for every label, was a big part of the lag.
    private static var cache: [String: UIFont] = [:]
    private static var sizeObserver: NSObjectProtocol?

    private static func cached(_ key: String, _ make: () -> UIFont) -> UIFont {
        if sizeObserver == nil {
            // Text size changed in Settings: build fonts afresh at the new size.
            sizeObserver = NotificationCenter.default.addObserver(
                forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { CandorType.cache.removeAll() }
            }
        }
        if let font = cache[key] { return font }
        let font = make()
        cache[key] = font
        return font
    }

    /// SF Pro at a text style's size (scaled with the reader's text size) or a fixed size.
    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, size: CGFloat? = nil) -> UIFont {
        cached("f|\(style.rawValue)|\(weight.rawValue)|\(size ?? -1)") { makeFont(style, weight: weight, size: size) }
    }

    private static func makeFont(_ style: UIFont.TextStyle, weight: UIFont.Weight, size: CGFloat?) -> UIFont {
        // Captions are hand-lettered in Story Script: small notes, like ink on a travel journal.
        if size == nil, style == .caption1 || style == .caption2 {
            _ = registerFonts
            if let face = UIFont(name: "StoryScript-Regular", size: style == .caption1 ? 14 : 12.5) {
                return UIFontMetrics(forTextStyle: style).scaledFont(for: face)
            }
        }
        let base = UIFont.systemFont(ofSize: size ?? scale(style), weight: weight)
        if size != nil { return base }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Candor's type scale, one size per role, used everywhere so screens share one rhythm.
    /// A touch calmer than the system defaults; still scales with the reader's text size.
    ///
    ///  Large title 30 · Title 1 26 · Title 2 22 · Title 3 19 · Headline 16 · Body 16 ·
    ///  Callout 15 · Subheadline 14 · Footnote 13 · Caption 12 · Caption 2 11
    static func scale(_ style: UIFont.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 30
        case .title1: 26
        case .title2: 22
        case .title3: 19
        case .headline: 16
        case .body: 16
        case .callout: 15
        case .subheadline: 14
        case .footnote: 13
        case .caption1: 12
        case .caption2: 11
        default: UIFont.preferredFont(forTextStyle: style).pointSize
        }
    }

    /// Display sizes snap to the same steps (20, 24, 28, 34, 40), so big numbers and hero
    /// titles line up with the headings around them.
    static func displayStep(_ size: CGFloat) -> CGFloat {
        let steps: [CGFloat] = [20, 24, 28, 34, 40]
        return steps.min { abs($0 - size) < abs($1 - size) } ?? size
    }

    /// (Earlier titles used Instrument Serif (Google Fonts, SIL Open Font License, bundled in
    /// Design/Fonts): an elegant, editorial serif. It has one weight, so titles get their
    /// presence from size, not boldness. Its sizes run a step larger than the body scale because
    /// the face is narrow. Scripts it doesn't cover (Devanagari, CJK, Arabic…) and symbols like ₹
    /// fall back to the system font automatically.
    static func headingSize(_ style: UIFont.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 32
        case .title1: 28
        case .title2: 24
        case .title3: 20
        case .headline: 17
        default: scale(style) + 1
        }
    }

    /// Titles in PT Serif (Google Fonts, SIL Open Font License, bundled in Design/Fonts): a warm,
    /// readable book serif. Bold for small card headings so they hold their own; regular for
    /// screen titles, where size gives the presence.
    static func heading(_ style: UIFont.TextStyle, weight: UIFont.Weight = .medium) -> UIFont {
        cached("h|\(style.rawValue)|\(weight.rawValue)") { makeHeading(style, weight: weight) }
    }

    private static func makeHeading(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = headingSize(style)
        let bold = style == .headline || style == .title3
        guard let face = titleFace(size: size, bold: bold) else { return serif(font(style, weight: weight)) }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: face)
    }

    /// Large display type (wordmark, hero titles, big numbers).
    static func display(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        cached("d|\(size)|\(weight.rawValue)") { makeDisplay(size: size, weight: weight) }
    }

    private static func makeDisplay(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let step = displayStep(size)
        return titleFace(size: step, bold: weight.rawValue >= UIFont.Weight.semibold.rawValue && step <= 28)
            ?? serif(UIFont.systemFont(ofSize: step, weight: weight))
    }

    /// PT Serif Italic at a heading size, scaled and cached.
    static func headingItalicFace(_ style: UIFont.TextStyle) -> UIFont? {
        guard titleFace(size: 12, italic: true) != nil else { return nil }
        return cached("i|\(style.rawValue)") {
            let face = titleFace(size: headingSize(style), italic: true) ?? UIFont.italicSystemFont(ofSize: headingSize(style))
            return UIFontMetrics(forTextStyle: style).scaledFont(for: face)
        }
    }

    /// PT Serif at `size`, registered from the app bundle on first use.
    static func titleFace(size: CGFloat, italic: Bool = false, bold: Bool = false) -> UIFont? {
        _ = registerFonts
        let name = italic ? "PTSerif-Italic" : (bold ? "PTSerif-Bold" : "PTSerif-Regular")
        return UIFont(name: name, size: size)
    }

    private static let registerFonts: Bool = {
        for name in ["PTSerif-Regular", "PTSerif-Bold", "PTSerif-Italic", "StoryScript-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// One step lighter, so nothing on screen shouts: bold reads as semibold, semibold as medium.
    static func soft(_ weight: UIFont.Weight) -> UIFont.Weight {
        switch weight {
        case .black, .heavy: .bold
        case .bold: .semibold
        case .semibold: .medium
        default: weight
        }
    }

    private static func serif(_ base: UIFont) -> UIFont {
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}

extension Font {
    /// Candor's typeface at a text style, e.g. `.candor(.subheadline, .semibold)`.
    static func candor(_ style: UIFont.TextStyle, _ weight: UIFont.Weight = .regular) -> Font {
        Font(CandorType.font(style, weight: CandorType.soft(weight)))
    }

    /// Candor's typeface at a fixed size (logo wordmark, big numbers).
    static func candor(size: CGFloat, _ weight: UIFont.Weight = .regular) -> Font {
        Font(CandorType.font(.body, weight: CandorType.soft(weight), size: size))
    }

    /// Screen titles and card headings: serif.
    static func heading(_ style: UIFont.TextStyle) -> Font {
        Font(CandorType.heading(style))
    }

    /// Italic title face, for a warm accent ("Namaste, …").
    static func headingItalic(_ style: UIFont.TextStyle) -> Font {
        if let face = CandorType.headingItalicFace(style) { return Font(face) }
        return heading(style).italic()
    }

    /// Serif display type at a fixed size (wordmark, hero titles).
    static func display(size: CGFloat, _ weight: UIFont.Weight = .semibold) -> Font {
        Font(CandorType.display(size: size, weight: CandorType.soft(weight)))
    }

    /// Hindi (Devanagari) text: the same system font, which includes Devanagari.
    static func hindi(_ style: UIFont.TextStyle, semibold: Bool = false, size: CGFloat? = nil) -> Font {
        Font(CandorType.font(style, weight: semibold ? .semibold : .regular, size: size))
    }
}
