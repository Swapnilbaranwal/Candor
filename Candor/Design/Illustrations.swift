import SwiftUI

// Candor's illustrations are drawn in code: original artwork, crisp at any size, light on the
// bundle, and alive (drifting clouds, a breathing sun, birds, glowing windows).

// MARK: - Time of day

/// The scene's palette follows the clock, so the hero greets the traveller with the sky they see.
enum DayPeriod: CaseIterable {
    case dawn, day, dusk, night

    static func now(_ date: Date = .now) -> DayPeriod {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<7: .dawn
        case 7..<17: .day
        case 17..<19: .dusk
        default: .night
        }
    }

    var sky: [Color] {
        switch self {
        case .dawn: [Color(hex: 0xF7B98F), Color(hex: 0xF6D9C4), Color(hex: 0xDCE7F5)]
        case .day: [Color(hex: 0x6FBFEF), Color(hex: 0xB9E3FA), Color(hex: 0xFCEBD3)]
        case .dusk: [Color(hex: 0x3A2A6A), Color(hex: 0xC8577A), Color(hex: 0xF8A65B)]
        case .night: [Color(hex: 0x081230), Color(hex: 0x1B2653), Color(hex: 0x37407C)]
        }
    }

    var farHills: Color {
        switch self {
        case .dawn: Color(hex: 0xC9B4D6)
        case .day: Color(hex: 0x9CC3E3)
        case .dusk: Color(hex: 0x7A5492)
        case .night: Color(hex: 0x252E5C)
        }
    }

    var midHills: Color {
        switch self {
        case .dawn: Color(hex: 0xA58FC2)
        case .day: Color(hex: 0x7FB0A0)
        case .dusk: Color(hex: 0x553F7E)
        case .night: Color(hex: 0x1B2249)
        }
    }

    var monuments: Color {
        switch self {
        case .dawn: Color(hex: 0x7A587F)
        case .day: Color(hex: 0xB5603A)
        case .dusk: Color(hex: 0x2E2149)
        case .night: Color(hex: 0x0F1533)
        }
    }

    var ground: Color {
        switch self {
        case .dawn: Color(hex: 0x6F9C7E)
        case .day: Color(hex: 0x4F9466)
        case .dusk: Color(hex: 0x2A2250)
        case .night: Color(hex: 0x0A0F27)
        }
    }

    var foreground: Color {
        switch self {
        case .dawn: Color(hex: 0x4E7F61)
        case .day: Color(hex: 0x3A7A50)
        case .dusk: Color(hex: 0x1D1740)
        case .night: Color(hex: 0x060A1C)
        }
    }

    var sun: Color {
        switch self {
        case .dawn: Color(hex: 0xFFE2A8)
        case .day: Color(hex: 0xFFF3C4)
        case .dusk: Color(hex: 0xFFD27A)
        case .night: Color(hex: 0xF4F1DE)
        }
    }

    var isNight: Bool { self == .night }

    /// The app follows the sky: light from dawn to dusk, dark at night.
    var colorScheme: ColorScheme { self == .night ? .dark : .light }

    /// The greeting icon that matches the sky.
    var symbol: String {
        switch self {
        case .dawn: "sunrise"
        case .day: "sun.max"
        case .dusk: "sunset"
        case .night: "moon.stars"
        }
    }
}

extension Color {
    /// `Color(hex: 0xF8A65B)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Delhi skyline scene

/// An illustrated Delhi: hills, India Gate, Qutub Minar, Humayun's Tomb and the Lotus Temple
/// under a sky that follows the time of day. Clouds drift, the sun breathes, birds fly by.
struct CityScene: View {
    var period: DayPeriod = .now()
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    LinearGradient(colors: period.sky, startPoint: .top, endPoint: .bottom)

                    if period.isNight { stars(size: size, t: t) }
                    sun(size: size, t: t)
                    clouds(size: size, t: t)

                    HillShape(baseline: 0.58, amplitude: 0.06, waves: 1.6, phase: 0.3)
                        .fill(period.farHills.opacity(0.85))
                    HillShape(baseline: 0.70, amplitude: 0.05, waves: 2.3, phase: 1.4)
                        .fill(period.midHills)

                    SkylineShape().fill(period.monuments)
                    IndiaGateShape().fill(period.monuments, style: FillStyle(eoFill: true))
                    if period.isNight { windowLights(size: size, t: t) }

                    HillShape(baseline: 0.86, amplitude: 0.035, waves: 1.2, phase: 2.2)
                        .fill(period.ground)
                    TreesShape().fill(period.foreground)
                    HillShape(baseline: 0.95, amplitude: 0.02, waves: 2.8, phase: 0.6)
                        .fill(period.foreground)

                    birds(size: size, t: t)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func sun(size: CGSize, t: Double) -> some View {
        let r = min(size.width, size.height) * 0.11
        let pulse = 1 + 0.06 * sin(t * 1.2)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [period.sun.opacity(0.55), period.sun.opacity(0)],
                                     center: .center, startRadius: r * 0.6, endRadius: r * 2.6))
                .frame(width: r * 5.2, height: r * 5.2)
                .scaleEffect(pulse)
            if period.isNight {
                CrescentShape()
                    .fill(period.sun)
                    .frame(width: r * 1.7, height: r * 1.7)
                    .rotationEffect(.degrees(-15))
            } else {
                Circle().fill(period.sun).frame(width: r * 2, height: r * 2)
            }
        }
        .position(x: size.width * 0.74, y: size.height * (period == .day ? 0.24 : 0.36))
    }

    private func clouds(size: CGSize, t: Double) -> some View {
        let specs: [(y: Double, scale: Double, speed: Double, phase: Double)] = [
            (0.16, 1.0, 9, 0), (0.30, 0.7, 6, 0.45), (0.10, 0.55, 12, 0.8)
        ]
        let span = size.width + 220
        return ZStack {
            ForEach(0..<specs.count, id: \.self) { i in
                let spec = specs[i]
                let x = (t * spec.speed + spec.phase * span).truncatingRemainder(dividingBy: span) - 110
                CloudShape()
                    .fill(Color.white.opacity(period.isNight ? 0.12 : 0.85))
                    .frame(width: 120 * spec.scale, height: 46 * spec.scale)
                    .position(x: x, y: size.height * spec.y)
            }
        }
    }

    private func stars(size: CGSize, t: Double) -> some View {
        let points: [(Double, Double)] = [(0.08, 0.10), (0.22, 0.22), (0.35, 0.08), (0.48, 0.18), (0.58, 0.06),
                                          (0.88, 0.12), (0.93, 0.30), (0.15, 0.34), (0.66, 0.28), (0.40, 0.30)]
        return ZStack {
            ForEach(0..<points.count, id: \.self) { i in
                let twinkle = 0.45 + 0.55 * abs(sin(t * 1.3 + Double(i)))
                Circle().fill(Color.white.opacity(twinkle))
                    .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 3 : 2)
                    .position(x: size.width * points[i].0, y: size.height * points[i].1)
            }
        }
    }

    private func windowLights(size: CGSize, t: Double) -> some View {
        let lights: [(Double, Double)] = [(0.415, 0.60), (0.43, 0.66), (0.62, 0.76), (0.66, 0.76), (0.86, 0.79)]
        return ZStack {
            ForEach(0..<lights.count, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0xFFD27A).opacity(0.6 + 0.4 * abs(sin(t * 0.8 + Double(i) * 1.7))))
                    .frame(width: 3, height: 3)
                    .position(x: size.width * lights[i].0, y: size.height * lights[i].1)
            }
        }
    }

    private func birds(size: CGSize, t: Double) -> some View {
        let span = size.width + 120
        let x = (t * 14).truncatingRemainder(dividingBy: span) - 60
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                let flap = 0.55 + 0.45 * sin(t * 7 + Double(i) * 1.3)
                BirdShape()
                    .stroke(period.isNight ? Color.white.opacity(0.5) : Color.black.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 6)
                    .scaleEffect(x: 1, y: flap)
                    .position(x: x + Double(i) * 18, y: size.height * 0.22 + Double(i % 2) * 8 + 4 * sin(t + Double(i)))
            }
        }
    }
}

// MARK: Scene shapes

/// A rolling hill line across the full width, filled down to the bottom.
nonisolated struct HillShape: Shape {
    var baseline: Double
    var amplitude: Double
    var waves: Double
    var phase: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 40
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...steps {
            let fx = Double(i) / Double(steps)
            let y = baseline + amplitude * sin(fx * .pi * 2 * waves + phase) * (0.6 + 0.4 * sin(fx * 5 + phase))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Qutub Minar, Humayun's Tomb and the Lotus Temple on one baseline.
nonisolated struct SkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        let base = 0.80

        // Qutub Minar: a tapering tower with balcony bands and a small cap.
        let qx = 0.42, qTop = 0.40
        p.move(to: pt(qx - 0.026, base))
        p.addLine(to: pt(qx - 0.013, qTop))
        p.addLine(to: pt(qx + 0.013, qTop))
        p.addLine(to: pt(qx + 0.026, base))
        p.closeSubpath()
        for band in [0.48, 0.58, 0.68] {
            let half = 0.013 + (band - qTop) / (base - qTop) * 0.013 + 0.006
            p.addRect(CGRect(x: rect.minX + w * (qx - half), y: rect.minY + h * band, width: w * half * 2, height: h * 0.012))
        }
        p.addRect(CGRect(x: rect.minX + w * (qx - 0.007), y: rect.minY + h * (qTop - 0.04), width: w * 0.014, height: h * 0.04))
        p.addEllipse(in: CGRect(x: rect.minX + w * (qx - 0.009), y: rect.minY + h * (qTop - 0.058), width: w * 0.018, height: h * 0.022))

        // Humayun's Tomb: a wide plinth, a drum, the onion dome, two side kiosks.
        let tx = 0.64
        p.addRect(CGRect(x: rect.minX + w * (tx - 0.085), y: rect.minY + h * (base - 0.07), width: w * 0.17, height: h * 0.07))
        p.addRect(CGRect(x: rect.minX + w * (tx - 0.04), y: rect.minY + h * (base - 0.10), width: w * 0.08, height: h * 0.03))
        p.move(to: pt(tx - 0.045, base - 0.10))
        p.addCurve(to: pt(tx, base - 0.20), control1: pt(tx - 0.05, base - 0.16), control2: pt(tx - 0.02, base - 0.19))
        p.addCurve(to: pt(tx + 0.045, base - 0.10), control1: pt(tx + 0.02, base - 0.19), control2: pt(tx + 0.05, base - 0.16))
        p.closeSubpath()
        p.addRect(CGRect(x: rect.minX + w * (tx - 0.002), y: rect.minY + h * (base - 0.235), width: w * 0.004, height: h * 0.04))
        for side in [-0.065, 0.065] {
            p.addRect(CGRect(x: rect.minX + w * (tx + side - 0.012), y: rect.minY + h * (base - 0.095), width: w * 0.024, height: h * 0.025))
            p.addEllipse(in: CGRect(x: rect.minX + w * (tx + side - 0.014), y: rect.minY + h * (base - 0.115), width: w * 0.028, height: h * 0.03))
        }

        // Lotus Temple: petals opening from a low base.
        let lx = 0.86, lBase = base + 0.005
        p.addRect(CGRect(x: rect.minX + w * (lx - 0.08), y: rect.minY + h * (lBase - 0.02), width: w * 0.16, height: h * 0.02))
        let petals: [(dx: Double, height: Double, width: Double)] = [
            (-0.055, 0.07, 0.035), (0.055, 0.07, 0.035), (-0.032, 0.10, 0.035), (0.032, 0.10, 0.035), (0, 0.125, 0.035)
        ]
        for petal in petals {
            let cx = lx + petal.dx
            p.move(to: pt(cx - petal.width, lBase - 0.02))
            p.addQuadCurve(to: pt(cx, lBase - 0.02 - petal.height), control: pt(cx - petal.width, lBase - 0.02 - petal.height * 0.7))
            p.addQuadCurve(to: pt(cx + petal.width, lBase - 0.02), control: pt(cx + petal.width, lBase - 0.02 - petal.height * 0.7))
            p.closeSubpath()
        }

        // A few low rooftops to tie the monuments together.
        for (x, width, height) in [(0.02, 0.06, 0.05), (0.27, 0.07, 0.04), (0.50, 0.05, 0.06), (0.75, 0.05, 0.035), (0.95, 0.06, 0.05)] {
            p.addRect(CGRect(x: rect.minX + w * x, y: rect.minY + h * (base - height), width: w * width, height: h * height))
        }
        return p
    }
}

/// India Gate: the arch, the attic and the shallow dome on top (even-odd fill cuts the opening).
nonisolated struct IndiaGateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = 0.17, base = 0.80, half = 0.065, top = 0.57
        p.addRect(CGRect(x: rect.minX + w * (cx - half), y: rect.minY + h * top, width: w * half * 2, height: h * (base - top)))
        // The opening: straight sides with a round head.
        let openHalf = 0.026, springLine = 0.68
        p.move(to: CGPoint(x: rect.minX + w * (cx - openHalf), y: rect.minY + h * base))
        p.addLine(to: CGPoint(x: rect.minX + w * (cx - openHalf), y: rect.minY + h * springLine))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * (cx + openHalf), y: rect.minY + h * springLine),
                       control: CGPoint(x: rect.minX + w * cx, y: rect.minY + h * (springLine - 0.06)))
        p.addLine(to: CGPoint(x: rect.minX + w * (cx + openHalf), y: rect.minY + h * base))
        p.closeSubpath()
        // Attic and dome sit above the main block (separate, so they stay filled).
        var top2 = Path()
        top2.addRect(CGRect(x: rect.minX + w * (cx - 0.05), y: rect.minY + h * (top - 0.035), width: w * 0.10, height: h * 0.035))
        top2.addEllipse(in: CGRect(x: rect.minX + w * (cx - 0.022), y: rect.minY + h * (top - 0.065), width: w * 0.044, height: h * 0.05))
        p.addPath(top2)
        return p
    }
}

/// Rounded trees along the near hill.
nonisolated struct TreesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let trees: [(x: Double, r: Double)] = [(0.04, 0.035), (0.09, 0.025), (0.30, 0.03), (0.53, 0.028),
                                               (0.56, 0.02), (0.76, 0.034), (0.97, 0.03)]
        for tree in trees {
            let radius = min(w, h * 2) * tree.r
            let center = CGPoint(x: rect.minX + w * tree.x, y: rect.minY + h * 0.86 - radius * 1.2)
            p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2.2))
            p.addRect(CGRect(x: center.x - radius * 0.12, y: center.y, width: radius * 0.24, height: radius * 1.4))
        }
        return p
    }
}

/// A soft cloud of overlapping puffs.
nonisolated struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + h * 0.45, width: w, height: h * 0.55),
                         cornerSize: CGSize(width: h * 0.27, height: h * 0.27))
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.15, y: rect.minY + h * 0.2, width: w * 0.35, height: h * 0.7))
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.38, y: rect.minY, width: w * 0.42, height: h * 0.85))
        return p
    }
}

/// A gull "v".
nonisolated struct BirdShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.width * 0.3, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.width * 0.7, y: rect.minY))
        return p
    }
}

/// The hero's bottom edge: a gentle arch, like a page turning up.
nonisolated struct ArcBottomShape: Shape {
    var depth: CGFloat = 36

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - depth),
                       control: CGPoint(x: rect.midX, y: rect.maxY - depth * 2.2))
        p.closeSubpath()
        return p
    }
}

// MARK: - Way back home art

/// A little house at the end of a dotted path, windows lit, the path marching home.
struct HomeNestArt: View {
    var period: DayPeriod = .now()
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: period.isNight
                                             ? [Color(hex: 0x2B3470), Color(hex: 0x1A1F45)]
                                             : [Color(hex: 0xFFE3C2), Color(hex: 0xFBC7B4)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: s * 0.92, height: s * 0.92)

                    // The path home.
                    HomePathShape()
                        .stroke(period.isNight ? Color.white.opacity(0.7) : Theme.ink.opacity(0.55),
                                style: StrokeStyle(lineWidth: max(2, s * 0.025), lineCap: .round,
                                                   dash: [0.1, s * 0.07], dashPhase: -CGFloat(t * 18)))
                        .frame(width: s, height: s)

                    house(s: s, t: t)
                        .offset(x: s * 0.14, y: -s * 0.06)

                    // You: a pin hopping along at the start of the path.
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: s * 0.17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.rose)
                        .offset(x: -s * 0.28, y: s * 0.22 - abs(sin(t * 3)) * s * 0.05)
                        .shadow(color: Theme.rose.opacity(0.35), radius: 6, y: 3)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func house(s: CGFloat, t: Double) -> some View {
        let glow = 0.75 + 0.25 * sin(t * 2.2)
        return ZStack {
            // Walls.
            RoundedRectangle(cornerRadius: s * 0.02)
                .fill(Color(hex: 0xFFF8EE))
                .frame(width: s * 0.34, height: s * 0.24)
                .offset(y: s * 0.07)
            // Roof.
            RoofShape()
                .fill(Color(hex: 0xC4553A))
                .frame(width: s * 0.44, height: s * 0.2)
                .offset(y: -s * 0.11)
            // Chimney.
            Rectangle().fill(Color(hex: 0x8E3B28))
                .frame(width: s * 0.04, height: s * 0.08)
                .offset(x: s * 0.1, y: -s * 0.15)
            // Door.
            UnevenRoundedRectangle(topLeadingRadius: s * 0.04, topTrailingRadius: s * 0.04)
                .fill(Theme.ink.opacity(0.85))
                .frame(width: s * 0.08, height: s * 0.12)
                .offset(x: -s * 0.06, y: s * 0.13)
            // Lit window.
            RoundedRectangle(cornerRadius: s * 0.01)
                .fill(Color(hex: 0xFFC94D).opacity(glow))
                .frame(width: s * 0.08, height: s * 0.07)
                .shadow(color: Color(hex: 0xFFC94D).opacity(0.8 * glow), radius: s * 0.04)
                .offset(x: s * 0.07, y: s * 0.06)
        }
    }
}

nonisolated struct RoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// From the pin (bottom left) curving up to the front door.
nonisolated struct HomePathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.70))
        p.addCurve(to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY + h * 0.66),
                   control1: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.92),
                   control2: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.86))
        return p
    }
}

// MARK: - "Where are you staying?" art

/// A suitcase with a hopping map pin asking where home is.
struct StayQuestionArt: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                let hop = abs(sin(t * 2.4))
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xDDEBFF), Color(hex: 0xC9E7DC)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: s * 0.92, height: s * 0.92)

                    Ellipse().fill(Color.black.opacity(0.08))
                        .frame(width: s * 0.46 - hop * s * 0.04, height: s * 0.06)
                        .offset(y: s * 0.33)

                    // Suitcase.
                    ZStack {
                        RoundedRectangle(cornerRadius: s * 0.05)
                            .stroke(Color(hex: 0x6B4A2E), lineWidth: s * 0.025)
                            .frame(width: s * 0.14, height: s * 0.1)
                            .offset(y: -s * 0.17)
                        RoundedRectangle(cornerRadius: s * 0.06)
                            .fill(LinearGradient(colors: [Color(hex: 0xF29F4B), Color(hex: 0xE2703A)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: s * 0.44, height: s * 0.32)
                        HStack(spacing: s * 0.1) {
                            Capsule().fill(Color.white.opacity(0.35)).frame(width: s * 0.03, height: s * 0.28)
                            Capsule().fill(Color.white.opacity(0.35)).frame(width: s * 0.03, height: s * 0.28)
                        }
                    }
                    .offset(y: s * 0.12)
                    .rotationEffect(.degrees(sin(t * 1.6) * 2.5), anchor: .bottom)

                    // The question: where?
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: s * 0.2))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.rose)
                        .shadow(color: Theme.rose.opacity(0.35), radius: 6, y: 4)
                        .offset(x: s * 0.2, y: -s * 0.2 - hop * s * 0.06)
                    Text("?")
                        .font(.display(size: s * 0.16, .bold))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .offset(x: -s * 0.2, y: -s * 0.22 + sin(t * 2) * s * 0.02)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}
