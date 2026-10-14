import SwiftUI

// MARK: - Buttons

/// Big capsule button. `.filled` is the screen's main action (ink pill, white text);
/// `.outline` is the quiet partner next to it.
struct PillButtonStyle: ButtonStyle {
    /// `amber` is the warm call to action for saffron cards, where burgundy would clash.
    enum Kind { case filled, amber, outline, soft, cream }
    var kind: Kind = .filled
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, height: height)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            configuration.label
                .font(.candor(.headline, .semibold))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                // The button's shadow sits on its capsule only, not traced around the label.
                .background(Capsule().fill(background)
                    .shadow(color: isEnabled ? shadowColor : .clear, radius: kind == .cream ? 6 : 10, y: kind == .cream ? 3 : 6))
                .overlay {
                    switch kind {
                    case .filled, .amber:
                        // Velvet buttons: a soft sheen on the upper half and a fine gold rim.
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .center))
                            .padding(1.5)
                            .allowsHitTesting(false)
                        Capsule().strokeBorder(LinearGradient(colors: [Theme.gold.opacity(0.9), Theme.gold.opacity(0.25)],
                                                              startPoint: .top, endPoint: .bottom),
                                               lineWidth: 1)
                    case .cream:
                        Capsule().strokeBorder(Theme.gold.opacity(0.55), lineWidth: 1)
                    case .outline:
                        Capsule().strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1.2)
                    case .soft:
                        EmptyView()
                    }
                }
                .contentShape(.capsule)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .filled, .amber: .white
            case .outline: Theme.ink
            case .soft: .primary
            case .cream: Color(hex: 0x5C1226)
            }
        }

        private var shadowColor: Color { kind == .cream ? Color.black.opacity(0.12) : glow }

        private var glow: Color {
            switch kind {
            case .filled: Color(hex: 0x2E0712).opacity(0.35)
            case .amber: Color(hex: 0x8A3F0E).opacity(0.32)
            default: .clear
            }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .filled: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x8A2340), Color(hex: 0x5C1226), Color(hex: 0x3E0A18)],
                                                       startPoint: .top, endPoint: .bottom))
            case .amber: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF2A65A), Color(hex: 0xDB7B2E), Color(hex: 0xB75A1C)],
                                                      startPoint: .top, endPoint: .bottom))
            case .cream: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFFDF8), Color(hex: 0xF7ECDD)],
                                                      startPoint: .top, endPoint: .bottom))
            case .outline: AnyShapeStyle(Theme.surface)
            case .soft: AnyShapeStyle(Theme.accentSoft)
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillOutline: PillButtonStyle { PillButtonStyle(kind: .outline) }
    static var pillSoft: PillButtonStyle { PillButtonStyle(kind: .soft, height: 48) }
    /// An ivory pill for buttons on velvet cards.
    static var pillCream: PillButtonStyle { PillButtonStyle(kind: .cream, height: 48) }
}

/// Gives any tappable card a soft press: it sinks a little and springs back.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// White circle with a soft shadow for one icon: back, bell, profile, close.
struct CircleIcon: View {
    let systemName: String
    var size: CGFloat = 50
    var filled = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(Circle()
                .fill(filled ? AnyShapeStyle(Theme.brandFill) : AnyShapeStyle(Theme.surface))
                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4))
    }
}

// MARK: - Motion

/// Fades and lifts content in on first appearance, staggered by `order`, so a screen
/// assembles itself top to bottom instead of popping in.
struct Reveal: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                // Quick and short: the whole screen is in place within about a third of a second.
                withAnimation(.snappy(duration: 0.3).delay(min(Double(order), 4) * 0.035)) {
                    shown = true
                }
            }
    }
}

extension View {
    func reveal(_ order: Int) -> some View { modifier(Reveal(order: order)) }
}

/// Small page indicator: the active page is a stretched pill.
struct PageDots: View {
    let count: Int
    let index: Int
    var color: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(color.opacity(i == index ? 1 : 0.45))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
    }
}

/// A capsule label with an icon, like "⛰ Mountains" in a travel card.
struct TagPill: View {
    let title: String
    let icon: String
    var tint: Color = Theme.saffron

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).lineLimit(1)
        }
        .font(.candor(.caption1, .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.canvas, in: .capsule)
    }
}

// MARK: - 3D artwork

/// The 3D illustrations from IconScout (free licence, no attribution needed). Each is an image
/// set in Assets.xcassets; run `Get3DArt.command` once to download them into the project.
enum Art3D: String {
    case indiaGate = "IndiaGate3D"
    case homePin = "HomePin3D"
    case suitcase = "Suitcase3D"
    case adventure = "Adventure3D"
    case translator = "Translator3D"
    case train = "Train3D"
    case pin = "Pin3D"
    case camera = "Camera3D"

    var image: UIImage? { UIImage(named: rawValue) }
}

/// A 3D illustration that floats gently, with a soft contact shadow. Falls back to `fallback`
/// (a drawn illustration or symbol) when the image isn't in the bundle yet.
struct Floating3D<Fallback: View>: View {
    let art: Art3D
    var size: CGFloat = 120
    var float = true
    @ViewBuilder var fallback: () -> Fallback
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: size * 0.02) {
            Group {
                if let image = art.image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    fallback()
                }
            }
            .frame(width: size, height: size)
            .offset(y: up ? -size * 0.05 : size * 0.02)
            .rotationEffect(.degrees(up ? -2 : 2))

            // A soft contact shadow drawn as a gradient: no blur pass on every frame of the float.
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.14), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.26))
                .frame(width: size * 0.52, height: size * 0.08)
                .scaleEffect(x: up ? 0.82 : 1, y: 1)
                .opacity(up ? 0.6 : 1)
        }
        .compositingGroup()
        .accessibilityHidden(true)
        .onAppear {
            guard float, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// Stand-in for a 3D illustration: the symbol on a soft disc.
struct SymbolArt: View {
    let symbol: String
    var tint: Color = Theme.saffron

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(22)
            .background(tint.opacity(0.14), in: .circle)
    }
}

extension Floating3D where Fallback == SymbolArt {
    /// Falls back to an SF Symbol on a soft disc.
    init(_ art: Art3D, size: CGFloat = 120, float: Bool = true, symbol: String, tint: Color = Theme.saffron) {
        self.init(art: art, size: size, float: float) { SymbolArt(symbol: symbol, tint: tint) }
    }
}
