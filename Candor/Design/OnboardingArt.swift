import SwiftUI

// Illustrations for the logo, sign-in and first-run screens. All drawn in code: no image
// downloads, no animation runtime, nothing to load. Loops run on `TimelineView` and stop
// under Reduce Motion.

// MARK: - Logo

/// Candor's logo: an open "C" in a sunrise gradient holding a map pin. Honest guidance, right
/// to the place. `tile` puts it on the night-indigo square of the app icon.
struct CandorLogo: View {
    var size: CGFloat = 80
    var tile = true

    var body: some View {
        ZStack {
            if tile {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1C1E48), Color(hex: 0x30286E)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0xFF8C5A, opacity: 0.25), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.5))
            }
            CandorMark()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The bare mark, drawn in a square: the "C" arc and the mint pin in its opening.
struct CandorMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .trim(from: 48.0 / 360.0, to: 312.0 / 360.0)
                    .stroke(AngularGradient(colors: [Color(hex: 0xFF6260), Color(hex: 0xFF9A5A), Color(hex: 0xFFBE50)],
                                            center: .center,
                                            startAngle: .degrees(48), endAngle: .degrees(312)),
                            style: StrokeStyle(lineWidth: s * 0.115, lineCap: .round))
                    .frame(width: s * 0.54, height: s * 0.54)
                    .position(x: s * 0.47, y: s * 0.5)
                PinShape()
                    .fill(Color(hex: 0x6EE2B6), style: FillStyle(eoFill: true))
                    .frame(width: s * 0.166, height: s * 0.257)
                    .position(x: s * 0.74, y: s * 0.506)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A map pin with a hole: round head, pointed tail at the bottom of the rect.
nonisolated struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + r)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let d = max(tip.y - center.y, r * 1.05)
        let a = asin(min(r / d, 1))   // angle of the tangent points below the horizontal
        var p = Path()
        p.move(to: tip)
        let steps = 48
        for i in 0...steps {
            // From the right tangent point over the top to the left one.
            let angle = a - (Double.pi + 2 * a) * Double(i) / Double(steps)
            p.addLine(to: CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
        }
        p.closeSubpath()
        let hole = r * 0.38
        p.addEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
        return p
    }
}

/// A crescent moon: a disc with a bite taken out of its upper right.
nonisolated struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let disc = Path(ellipseIn: rect)
        let bite = Path(ellipseIn: rect.offsetBy(dx: rect.width * 0.34, dy: -rect.height * 0.2))
        return disc.subtracting(bite)
    }
}

// MARK: - Sign-in: what Candor does, at a glance

/// The sign-in illustration: Delhi under today's sky with the four things Candor does floating
/// over it: a fair price checked, a phrase translated, the way back home, and the Lens.
struct ProductArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                CityScene(animated: !reduceMotion)
                    .frame(height: 170)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 22)

                bubble(icon: "checkmark.seal.fill", tint: Theme.mint,
                       title: L("Auto to India Gate"), value: L("₹180 · fair"))
                    .offset(x: -58, y: -84 + 4 * sin(t * 1.3))
                bubble(icon: "character.bubble.fill", tint: Theme.teal,
                       title: "कितना हुआ?", value: L("How much is it?"))
                    .offset(x: 70, y: -8 + 4 * sin(t * 1.1 + 1.5))
                bubble(icon: "house.fill", tint: Theme.saffron,
                       title: L("Way back home"), value: L("12 min by metro"))
                    .offset(x: -70, y: 80 + 4 * sin(t * 1.2 + 3))
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.ink, in: .circle)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    .offset(x: 118, y: -78 + 5 * sin(t * 1.5 + 0.7))
            }
            .frame(height: 240)
        }
        .accessibilityElement()
        .accessibilityLabel(L("Fair prices, translation, the way back home and the Lens"))
    }

    private func bubble(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.candor(.caption1, .semibold)).foregroundStyle(.primary)
                Text(value).font(.candor(.caption2)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Theme.surface, in: .capsule)
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .fixedSize()
    }
}

// MARK: - Journey: town to town

/// Two towns under today's sky: a plane flies the arc from one to the other while a car, an
/// auto-rickshaw and a scooter travel the road below. Drawn on a `Canvas`, so it stays cheap.
struct JourneyArt: View {
    var from: String?
    var to: String?
    var period: DayPeriod = .now()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 3.0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                paint(&ctx, size: size, t: t)
            }
        }
        .overlay(alignment: .top) { routeLabel.padding(.top, 12) }
        .clipShape(.rect(cornerRadius: Theme.Radius.large, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var routeLabel: some View {
        if let from {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.saffron)
                Text(from)
                if let to {
                    Image(systemName: "airplane").font(.candor(.caption2, .bold)).foregroundStyle(.secondary)
                    Text(to)
                }
            }
            .font(.candor(.caption1, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
        }
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }

    private func paint(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let full = CGRect(origin: .zero, size: size)

        // Sky, stars or sun, clouds.
        ctx.fill(Path(full), with: .linearGradient(Gradient(colors: period.sky),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.8)))
        if period.isNight {
            for i in 0..<14 {
                let x = w * frac(Double(i) * 0.137 + 0.04)
                let y = h * (0.05 + 0.32 * frac(Double(i) * 0.291 + 0.1))
                let alpha = 0.3 + 0.7 * abs(sin(t * 1.4 + Double(i)))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)), with: .color(.white.opacity(alpha)))
            }
            ctx.fill(CrescentShape().path(in: CGRect(x: w * 0.86, y: h * 0.10, width: 20, height: 20)),
                     with: .color(period.sun))
        } else {
            let r = 13 + 1.5 * sin(t * 1.2)
            let c = CGPoint(x: w * 0.9, y: h * 0.17)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.4, y: c.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                     with: .radialGradient(Gradient(colors: [period.sun.opacity(0.6), period.sun.opacity(0)]),
                                           center: c, startRadius: r * 0.5, endRadius: r * 2.4))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(period.sun))
        }
        let span = Double(w) + 160
        for (i, spec) in [(0.12, 1.0, 7.0, 0.0), (0.26, 0.65, 4.5, 0.5)].enumerated() {
            let x = frac(t * spec.2 / span + spec.3 + Double(i) * 0.1) * span - 80
            let cw = 96 * spec.1, ch = 36 * spec.1
            ctx.fill(CloudShape().path(in: CGRect(x: x, y: h * spec.0, width: cw, height: ch)),
                     with: .color(.white.opacity(period.isNight ? 0.10 : 0.8)))
        }

        // Hills and ground.
        ctx.fill(HillShape(baseline: 0.62, amplitude: 0.05, waves: 1.4, phase: 0.8).path(in: full),
                 with: .color(period.farHills.opacity(0.8)))

        // Towns.
        let left = CGRect(x: w * 0.02, y: h * 0.38, width: w * 0.33, height: h * 0.38)
        let right = CGRect(x: w * 0.65, y: h * 0.36, width: w * 0.33, height: h * 0.40)
        town(&ctx, in: left, variant: 0, t: t)
        town(&ctx, in: right, variant: 1, t: t)

        ctx.fill(Path(CGRect(x: 0, y: h * 0.75, width: w, height: h * 0.25)), with: .color(period.ground))

        // Road with a dashed centre line.
        let roadTop = h * 0.79, roadBottom = h * 0.99
        let road = period.isNight ? Color(hex: 0x1A1D2B) : Color(hex: 0x4A4E5A)
        ctx.fill(Path(CGRect(x: 0, y: roadTop, width: w, height: roadBottom - roadTop)), with: .color(road))
        var centre = Path()
        centre.move(to: CGPoint(x: 0, y: (roadTop + roadBottom) / 2))
        centre.addLine(to: CGPoint(x: w, y: (roadTop + roadBottom) / 2))
        ctx.stroke(centre, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [10, 9]))

        // The flight: dashed arc, a trail behind the plane, a pin on each town.
        let p0 = CGPoint(x: w * 0.19, y: h * 0.36)
        let p2 = CGPoint(x: w * 0.81, y: h * 0.34)
        let control = CGPoint(x: w * 0.5, y: -h * 0.12)
        var arc = Path()
        arc.move(to: p0)
        arc.addQuadCurve(to: p2, control: control)
        ctx.stroke(arc, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 5]))
        let p = CGFloat(frac(t / 6.5))
        ctx.stroke(arc.trimmedPath(from: max(0, p - 0.25), to: p), with: .color(.white.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        for pin in [p0, p2] {
            ctx.fill(Path(ellipseIn: CGRect(x: pin.x - 5, y: pin.y - 5, width: 10, height: 10)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: pin.x - 3, y: pin.y - 3, width: 6, height: 6)), with: .color(Theme.saffron))
        }
        let q: CGFloat = 1 - p
        let plane = CGPoint(x: q * q * p0.x + 2 * q * p * control.x + p * p * p2.x,
                            y: q * q * p0.y + 2 * q * p * control.y + p * p * p2.y)
        let dx = 2 * q * (control.x - p0.x) + 2 * p * (p2.x - control.x)
        let dy = 2 * q * (control.y - p0.y) + 2 * p * (p2.y - control.y)
        var planeCtx = ctx
        planeCtx.opacity = min(1, p * 10, (1 - p) * 10)
        planeCtx.translateBy(x: plane.x, y: plane.y)
        planeCtx.rotate(by: .radians(atan2(dy, dx)))
        var symbol = planeCtx.resolve(Image(systemName: "airplane"))
        symbol.shading = .color(.white)
        planeCtx.draw(symbol, in: CGRect(x: -12, y: -12, width: 24, height: 24))

        // Traffic: two lanes, one each way.
        let k = h / 190
        let travel = Double(w) + 120
        let laneA = roadTop + (roadBottom - roadTop) * 0.42
        let laneB = roadBottom - 2 * k
        let carX = frac(t * 44 / travel) * travel - 60
        vehicle(&ctx, at: CGPoint(x: carX, y: laneA), scale: k, flip: false) { car(&$0, color: Color(hex: 0xE4572E)) }
        let bikeX = frac(t * 30 / travel + 0.55) * travel - 60
        vehicle(&ctx, at: CGPoint(x: bikeX, y: laneA), scale: k, flip: false) { scooter(&$0) }
        let autoX = Double(w) + 60 - frac(t * 36 / travel + 0.2) * travel
        vehicle(&ctx, at: CGPoint(x: autoX, y: laneB), scale: k, flip: true) { auto(&$0) }
        let car2X = Double(w) + 60 - frac(t * 50 / travel + 0.7) * travel
        vehicle(&ctx, at: CGPoint(x: car2X, y: laneB), scale: k, flip: true) { car(&$0, color: Color(hex: 0x3D7DD8)) }
    }

    // MARK: Towns

    /// (x, width, height) of each building, in the town's unit square; the last flag adds a dome.
    private static let towns: [[(Double, Double, Double, Int)]] = [
        [(0.00, 0.16, 0.42, 0), (0.13, 0.15, 0.62, 0), (0.27, 0.22, 0.48, 1), (0.48, 0.06, 0.96, 2),
         (0.55, 0.17, 0.38, 0), (0.70, 0.16, 0.70, 0), (0.85, 0.15, 0.46, 1)],
        [(0.00, 0.18, 0.50, 1), (0.16, 0.12, 0.74, 2), (0.27, 0.24, 0.42, 0), (0.50, 0.14, 0.86, 2),
         (0.63, 0.20, 0.55, 1), (0.82, 0.18, 0.36, 0)]
    ]

    private func town(_ ctx: inout GraphicsContext, in rect: CGRect, variant: Int, t: Double) {
        let fill = GraphicsContext.Shading.color(period.monuments)
        for (index, b) in Self.towns[variant].enumerated() {
            let bw = rect.width * b.1
            let bh = rect.height * b.2
            let x = rect.minX + rect.width * b.0
            let top = rect.maxY - bh
            ctx.fill(Path(CGRect(x: x, y: top, width: bw, height: bh)), with: fill)
            switch b.3 {
            case 1:
                let r = bw * 0.36
                ctx.fill(Path(ellipseIn: CGRect(x: x + bw / 2 - r, y: top - r, width: r * 2, height: r * 2)), with: fill)
            case 2:
                var spire = Path()
                spire.move(to: CGPoint(x: x - bw * 0.1, y: top))
                spire.addLine(to: CGPoint(x: x + bw / 2, y: top - bw * 0.9))
                spire.addLine(to: CGPoint(x: x + bw * 1.1, y: top))
                spire.closeSubpath()
                ctx.fill(spire, with: fill)
            default:
                break
            }
            // Windows: lit and flickering at night, faint by day.
            guard bw > 8 else { continue }
            let rows = Int(bh / 9)
            for row in 0..<max(rows - 1, 0) {
                for column in 0..<2 where (index * 7 + row * 3 + column) % 3 != 0 {
                    let wx = x + bw * (column == 0 ? 0.22 : 0.6)
                    let wy = top + 6 + Double(row) * 9
                    let lit = period.isNight || period == .dusk
                    let glow = lit ? 0.65 + 0.35 * sin(t * 0.8 + Double(index + row)) : 0.22
                    ctx.fill(Path(CGRect(x: wx, y: wy, width: max(bw * 0.18, 2.5), height: 3.5)),
                             with: .color(lit ? Color(hex: 0xFFD27A, opacity: glow) : .white.opacity(glow)))
                }
            }
        }
    }

    // MARK: Vehicles (drawn facing right, base on y = 0)

    private func vehicle(_ ctx: inout GraphicsContext, at point: CGPoint, scale: CGFloat, flip: Bool,
                         draw: (inout GraphicsContext) -> Void) {
        var g = ctx
        g.translateBy(x: point.x, y: point.y)
        g.scaleBy(x: flip ? -scale : scale, y: scale)
        draw(&g)
    }

    private func wheel(_ g: inout GraphicsContext, x: CGFloat, r: CGFloat = 4.5) {
        g.fill(Path(ellipseIn: CGRect(x: x - r, y: -r * 2, width: r * 2, height: r * 2)), with: .color(Color(hex: 0x1E1E24)))
        g.fill(Path(ellipseIn: CGRect(x: x - r * 0.4, y: -r * 1.4, width: r * 0.8, height: r * 0.8)), with: .color(.white.opacity(0.7)))
    }

    private func car(_ g: inout GraphicsContext, color: Color) {
        var cabin = Path()
        cabin.move(to: CGPoint(x: -13, y: -13))
        cabin.addLine(to: CGPoint(x: -8, y: -21))
        cabin.addLine(to: CGPoint(x: 7, y: -21))
        cabin.addLine(to: CGPoint(x: 14, y: -13))
        cabin.closeSubpath()
        g.fill(cabin, with: .color(color))
        var glass = Path()
        glass.move(to: CGPoint(x: -10, y: -14))
        glass.addLine(to: CGPoint(x: -6.5, y: -19))
        glass.addLine(to: CGPoint(x: 6, y: -19))
        glass.addLine(to: CGPoint(x: 10.5, y: -14))
        glass.closeSubpath()
        g.fill(glass, with: .color(Color(hex: 0xCFE8F7)))
        g.fill(Path(roundedRect: CGRect(x: -22, y: -15, width: 44, height: 10), cornerRadius: 4), with: .color(color))
        if period.isNight {
            g.fill(Path(ellipseIn: CGRect(x: 19, y: -13, width: 4, height: 3)), with: .color(Color(hex: 0xFFE9A8)))
        }
        wheel(&g, x: -12)
        wheel(&g, x: 12)
    }

    /// An auto-rickshaw: green body, yellow canopy, three wheels (two show).
    private func auto(_ g: inout GraphicsContext) {
        g.fill(Path(roundedRect: CGRect(x: -15, y: -28, width: 25, height: 13), cornerRadius: 5),
               with: .color(Color(hex: 0xF6C445)))
        g.fill(Path(CGRect(x: -6, y: -25, width: 12, height: 9)), with: .color(Color(hex: 0x1E1E24, opacity: 0.55)))
        g.fill(Path(roundedRect: CGRect(x: -16, y: -16, width: 28, height: 10), cornerRadius: 3),
               with: .color(Color(hex: 0x2E8B57)))
        var nose = Path()
        nose.move(to: CGPoint(x: 10, y: -16))
        nose.addLine(to: CGPoint(x: 18, y: -9))
        nose.addLine(to: CGPoint(x: 12, y: -6))
        nose.closeSubpath()
        g.fill(nose, with: .color(Color(hex: 0x2E8B57)))
        if period.isNight {
            g.fill(Path(ellipseIn: CGRect(x: 15, y: -12, width: 3.5, height: 3)), with: .color(Color(hex: 0xFFE9A8)))
        }
        wheel(&g, x: -9, r: 4)
        wheel(&g, x: 13, r: 4)
    }

    /// A scooter with its rider.
    private func scooter(_ g: inout GraphicsContext) {
        let body = Color(hex: 0x7A4FD3)
        var frame = Path()
        frame.move(to: CGPoint(x: -9, y: -5))
        frame.addLine(to: CGPoint(x: -2, y: -11))
        frame.addLine(to: CGPoint(x: 7, y: -11))
        frame.addLine(to: CGPoint(x: 9, y: -5))
        g.stroke(frame, with: .color(body), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        var bar = Path()
        bar.move(to: CGPoint(x: 7, y: -11))
        bar.addLine(to: CGPoint(x: 9, y: -18))
        g.stroke(bar, with: .color(Color(hex: 0x1E1E24)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        var rider = Path()
        rider.move(to: CGPoint(x: -3, y: -13))
        rider.addLine(to: CGPoint(x: 1, y: -22))
        rider.addLine(to: CGPoint(x: 8, y: -17))
        g.stroke(rider, with: .color(Color(hex: 0x2B6CB0)), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        g.fill(Path(ellipseIn: CGRect(x: -1.5, y: -29.5, width: 6.5, height: 6.5)), with: .color(Color(hex: 0xE94F37)))
        wheel(&g, x: -9, r: 4)
        wheel(&g, x: 9, r: 4)
    }
}

// MARK: - Who's going

/// A small drawn portrait of the party: one traveller with a backpack, a couple under a heart,
/// a family with a child, a group of friends. About 60 × 60.
struct PartyArt: View {
    let party: TravelParty
    var isSelected = false
    var size: CGFloat = 60

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(tint.opacity(isSelected ? 0.28 : 0.14))
            figures
                .offset(y: size * 0.1)
                .scaleEffect(isSelected ? 1.06 : 1, anchor: .bottom)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(alignment: .top) {
            if party == .couple {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Theme.rose)
                    .offset(y: size * 0.02)
                    .symbolEffect(.bounce, value: isSelected)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isSelected)
        .accessibilityHidden(true)
    }

    var tint: Color {
        switch party {
        case .solo: Theme.saffron
        case .couple: Theme.rose
        case .family: Theme.teal
        case .group: Theme.indigo
        }
    }

    @ViewBuilder
    private var figures: some View {
        let unit = size / 60
        switch party {
        case .solo:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4 * unit)
                    .fill(Color(hex: 0x8D5A3B))
                    .frame(width: 12 * unit, height: 16 * unit)
                    .offset(x: -11 * unit, y: -4 * unit)
                PersonFigure(shirt: Theme.saffron, skin: Color(hex: 0xE0AC69), hair: Color(hex: 0x3B2A20), unit: unit * 1.15)
            }
        case .couple:
            HStack(spacing: -6 * unit) {
                PersonFigure(shirt: Theme.indigo, skin: Color(hex: 0xC68642), hair: Color(hex: 0x2B1D14), unit: unit)
                PersonFigure(shirt: Theme.rose, skin: Color(hex: 0xF1C27D), hair: Color(hex: 0x6B3E26), unit: unit, longHair: true)
            }
        case .family:
            ZStack(alignment: .bottom) {
                HStack(spacing: 4 * unit) {
                    PersonFigure(shirt: Theme.teal, skin: Color(hex: 0xC68642), hair: Color(hex: 0x2B1D14), unit: unit)
                    PersonFigure(shirt: Theme.saffron, skin: Color(hex: 0xE0AC69), hair: Color(hex: 0x3B2A20), unit: unit, longHair: true)
                }
                PersonFigure(shirt: Theme.mint, skin: Color(hex: 0xF1C27D), hair: Color(hex: 0x6B3E26), unit: unit * 0.68)
            }
        case .group:
            ZStack(alignment: .bottom) {
                HStack(spacing: 8 * unit) {
                    PersonFigure(shirt: Theme.teal, skin: Color(hex: 0xF1C27D), hair: Color(hex: 0xA0522D), unit: unit * 0.88)
                    PersonFigure(shirt: Theme.rose, skin: Color(hex: 0x8D5524), hair: Color(hex: 0x1E1E24), unit: unit * 0.88, longHair: true)
                }
                PersonFigure(shirt: Theme.indigo, skin: Color(hex: 0xE0AC69), hair: Color(hex: 0x3B2A20), unit: unit * 1.02)
            }
        }
    }
}

/// One simple person: head, hair, shoulders.
struct PersonFigure: View {
    let shirt: Color
    let skin: Color
    let hair: Color
    var unit: CGFloat = 1
    var longHair = false

    var body: some View {
        VStack(spacing: 1.5 * unit) {
            ZStack(alignment: .top) {
                if longHair {
                    Capsule().fill(hair).frame(width: 15 * unit, height: 17 * unit).offset(y: -1 * unit)
                }
                Circle().fill(skin).frame(width: 12 * unit, height: 12 * unit)
                UnevenRoundedRectangle(topLeadingRadius: 7 * unit, bottomLeadingRadius: 1 * unit,
                                       bottomTrailingRadius: 1 * unit, topTrailingRadius: 7 * unit)
                    .fill(hair)
                    .frame(width: 13 * unit, height: 5.5 * unit)
                    .offset(y: -1 * unit)
            }
            .frame(height: 12 * unit, alignment: .top)
            UnevenRoundedRectangle(topLeadingRadius: 9 * unit, topTrailingRadius: 9 * unit)
                .fill(shirt)
                .frame(width: 21 * unit, height: 16 * unit)
        }
    }
}

// MARK: - How you like to travel

extension TravelStyle {
    var gradient: [Color] {
        switch self {
        case .budget: [Color(hex: 0x34C38F), Color(hex: 0x1C9AA8)]
        case .comfort: [Color(hex: 0xFFB648), Color(hex: 0xF0646C)]
        case .luxury: [Color(hex: 0x7C6CF0), Color(hex: 0x3A2A8C)]
        }
    }

    var badge: String {
        switch self {
        case .budget: "tram.fill"
        case .comfort: "car.fill"
        case .luxury: "sparkles"
        }
    }

    var priceLevel: String {
        switch self {
        case .budget: "₹"
        case .comfort: "₹₹"
        case .luxury: "₹₹₹"
        }
    }

    var detail: String {
        switch self {
        case .budget: L("Metro, street food, homestays")
        case .comfort: L("Cabs, cafés, good hotels")
        case .luxury: L("Private car, fine dining")
        }
    }
}

/// The travel style as a small illustrated tile: the main object on a gradient, a badge on it.
struct StyleArt: View {
    let style: TravelStyle
    var isSelected = false
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: size * 0.9)
                .offset(x: size * 0.3, y: -size * 0.32)
            Image(systemName: style.icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: isSelected)
            Image(systemName: style.badge)
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(style.gradient[1])
                .frame(width: size * 0.34, height: size * 0.34)
                .background(.white, in: .circle)
                .offset(x: size * 0.3, y: size * 0.3)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.3, style: .continuous))
        .shadow(color: style.gradient[1].opacity(isSelected ? 0.45 : 0.2), radius: isSelected ? 10 : 6, y: 5)
        .accessibilityHidden(true)
    }
}

/// Icon and colour for each interest in `DelhiData.interests` (English keys).
enum InterestArt {
    static func icon(_ interest: String) -> String {
        switch interest {
        case "Heritage": "building.columns.fill"
        case "Street food": "fork.knife"
        case "Markets": "bag.fill"
        case "Spiritual": "sparkles"
        case "Art & crafts": "paintpalette.fill"
        case "Nightlife": "moon.stars.fill"
        case "Nature": "leaf.fill"
        case "Photography": "camera.fill"
        default: "star.fill"
        }
    }

    static func tint(_ interest: String) -> Color {
        switch interest {
        case "Heritage": Color(hex: 0xC8743A)
        case "Street food": Theme.rose
        case "Markets": Theme.saffron
        case "Spiritual": Color(hex: 0xB065D6)
        case "Art & crafts": Theme.indigo
        case "Nightlife": Color(hex: 0x3A3F8F)
        case "Nature": Theme.mint
        case "Photography": Theme.teal
        default: Theme.saffron
        }
    }

    /// Icons for `Persona.tasteOptions`.
    static func tasteIcon(_ taste: String) -> String {
        switch taste {
        case "Street food over fine dining": "takeoutbag.and.cup.and.straw.fill"
        case "Local gems over famous sights": "diamond.fill"
        case "Happy to walk": "figure.walk"
        case "Avoid crowds": "person.2.slash.fill"
        case "Early starts": "sunrise.fill"
        case "Slow mornings": "cup.and.saucer.fill"
        case "Kid-friendly": "figure.and.child.holdinghands"
        case "Vegetarian": "carrot.fill"
        default: "heart.fill"
        }
    }
}

// MARK: - Setting up: the recipe

/// One ingredient of the setup "recipe".
struct RecipeStep: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

/// Setting up, drawn as a recipe in the making: the ingredients (language, money, city guides,
/// rides, food, markets, your style) orbit a pot and drop in one by one while the ring fills.
struct RecipeRing: View {
    let steps: [RecipeStep]
    /// How many ingredients are in the pot.
    let done: Int
    /// How far into the current ingredient the work is (0–1), so the ring keeps moving while it waits.
    var partial: Double = 0
    /// Off for the splash: no ring filling up, just the ingredients circling the logo.
    var showsProgress = true
    /// Seconds per full turn of the orbit.
    var spinDuration: Double = 40
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        steps.isEmpty ? 0 : min((Double(done) + min(max(partial, 0), 1)) / Double(steps.count), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let orbit = s * 0.40
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 1.5, dash: [3, 7]))
                    .frame(width: orbit * 2, height: orbit * 2)

                // The pot: the progress ring around the logo, steam rising.
                if showsProgress {
                    Circle()
                        .stroke(Theme.accentSoft, lineWidth: 9)
                        .frame(width: s * 0.44, height: s * 0.44)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AngularGradient(colors: [Theme.saffron, Theme.rose, Theme.indigo, Theme.saffron],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: s * 0.44, height: s * 0.44)
                        .animation(.smooth(duration: 0.5), value: progress)
                }
                Steam()
                    .frame(width: s * 0.2, height: s * 0.16)
                    .offset(y: -s * 0.15)
                Group {
                    if done >= steps.count && !steps.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.system(size: s * 0.1, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: s * 0.3, height: s * 0.3)
                            .background(Theme.mint, in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        CandorLogo(size: s * 0.3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .phaseAnimator([1.0, 1.08, 1.0], trigger: done) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in .spring(response: 0.25, dampingFraction: 0.5) }

                // The ingredients, slowly orbiting; each flies into the pot when it's done.
                ZStack {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let angle = 2 * Double.pi * Double(index) / Double(max(steps.count, 1)) - Double.pi / 2
                        let isIn = index < done
                        let isCurrent = index == done
                        ingredient(step, isCurrent: isCurrent, size: s * 0.16)
                            .rotationEffect(.degrees(spin ? -360 : 0))
                            .scaleEffect(isIn ? 0.2 : (isCurrent ? 1.15 : 1))
                            .opacity(isIn ? 0 : 1)
                            .offset(x: isIn ? 0 : orbit * cos(angle), y: isIn ? 0 : orbit * sin(angle))
                            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: done)
                    }
                }
                .rotationEffect(.degrees(spin ? 360 : 0))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: spinDuration).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityHidden(true)
    }

    private func ingredient(_ step: RecipeStep, isCurrent: Bool, size: CGFloat) -> some View {
        Image(systemName: step.icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(isCurrent ? .white : step.tint)
            .frame(width: size, height: size)
            .background(isCurrent ? AnyShapeStyle(step.tint) : AnyShapeStyle(Theme.surface), in: .circle)
            .overlay {
                if isCurrent {
                    Circle().stroke(step.tint.opacity(0.35), lineWidth: 6).padding(-6)
                }
            }
            .shadow(color: Theme.shadow, radius: 8, y: 4)
    }
}

/// Three wisps of steam rising and fading.
private struct Steam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<3 {
                    let phase = (t / 2.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.2 + 0.3 * Double(i)) + 3 * sin(t * 2 + Double(i))
                    let y = size.height * (1 - phase)
                    let r = 3 + 4 * phase
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.saffron.opacity(0.35 * (1 - phase))))
                }
            }
        }
    }
}

// MARK: - Step backgrounds

/// The onboarding page: ivory, washed softly with the step's colour, a little saffron warmth,
/// and a faint rangoli-style mandala in the corner for an Indian touch.
struct StepBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            AppBackground()
            GeometryReader { geo in
                let w = geo.size.width
                // Soft washes drawn as radial gradients (a blur here re-renders while scrolling).
                RadialGradient(colors: [tint.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: w * 0.6)
                    .frame(width: w * 1.2, height: w * 1.2)
                    .position(x: w * 0.9, y: 0)
                RadialGradient(colors: [Theme.saffron.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: w * 0.5)
                    .frame(width: w, height: w)
                    .position(x: 0, y: geo.size.height * 0.85)
                Mandala()
                    .stroke(tint.opacity(0.12), lineWidth: 1)
                    .frame(width: w * 0.62, height: w * 0.62)
                    .position(x: w * 0.93, y: w * 0.17)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A simple rangoli: rings of petals around a centre, drawn as outlines.
nonisolated struct Mandala: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for ring in [1.0, 0.72, 0.46] {
            let radius = r * ring
            p.addEllipse(in: CGRect(x: c.x - radius * 0.18, y: c.y - radius * 0.18,
                                    width: radius * 0.36, height: radius * 0.36))
            let petals = ring == 1.0 ? 16 : (ring == 0.72 ? 12 : 8)
            for i in 0..<petals {
                let a = Double(i) / Double(petals) * 2 * .pi
                let tip = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
                let side = radius * 0.16
                let base = radius * 0.55
                let left = CGPoint(x: c.x + base * cos(a - 0.22) , y: c.y + base * sin(a - 0.22))
                let right = CGPoint(x: c.x + base * cos(a + 0.22), y: c.y + base * sin(a + 0.22))
                p.move(to: left)
                p.addQuadCurve(to: tip, control: CGPoint(x: (left.x + tip.x) / 2 - side * sin(a),
                                                         y: (left.y + tip.y) / 2 + side * cos(a)))
                p.addQuadCurve(to: right, control: CGPoint(x: (right.x + tip.x) / 2 + side * sin(a),
                                                           y: (right.y + tip.y) / 2 - side * cos(a)))
            }
            p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        return p
    }
}
