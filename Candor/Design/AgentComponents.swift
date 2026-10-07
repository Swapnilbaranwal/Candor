import SwiftUI

/// The visible "thinking trail": every tool call the agent makes, live.
struct AgentTrailView: View {
    let steps: [AgentStep]
    let isWorking: Bool
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isWorking ? "sparkles" : "checklist")
                        .symbolEffect(.pulse, isActive: isWorking)
                    Text(isWorking ? L("Working…") : L("Steps: %@", steps.count))
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(steps) { step in
                        StepRow(step: step)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .onChange(of: isWorking) { _, working in
            if !working {
                withAnimation(.snappy.delay(0.9)) { expanded = false }
            }
        }
    }
}

struct StepRow: View {
    let step: AgentStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(tint.opacity(0.25)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.subheadline.weight(.semibold))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Group {
                switch step.state {
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.saffron)
                }
            }
            .font(.footnote)
            .frame(width: 20, height: 30)
        }
    }

    private var tint: Color {
        switch step.state {
        case .running: Theme.indigo
        case .done: Theme.teal
        case .failed: Theme.saffron
        }
    }
}

/// Verdict card: fair range, asked price, gauge, source and a phrase to say.
struct VerdictCardView: View {
    @Environment(AppState.self) private var app
    let verdict: PriceVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(verdict.verdict.title, systemImage: verdict.verdict.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.tint(verdict.verdict.color), in: .capsule)
                    .accessibilityIdentifier("verdict.\(verdict.verdict.rawValue)") // language-independent hook for UI tests
                Spacer()
                if let percent = verdict.overPercent {
                    Text("+\(percent)%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(verdict.verdict.color)
                }
            }

            Text(L(verdict.item))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Fair price")).font(.caption).foregroundStyle(.secondary)
                    Text(verdict.rangeText).font(.title2.weight(.bold).monospacedDigit())
                    Text(app.homeAmount(verdict.fairHighINR)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let asked = verdict.askedINR {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L("Asked")).font(.caption).foregroundStyle(.secondary)
                        Text(inr(asked))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(verdict.verdict.color)
                        Text(app.homeAmount(asked)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            PriceGauge(low: verdict.fairLowINR, high: verdict.fairHighINR, asked: verdict.askedINR, color: verdict.verdict.color)

            Label(L(verdict.source), systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let tip = verdict.tip {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Say it")).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text(tip.roman).font(.subheadline.weight(.semibold))
                        Text(tip.hindi).font(.caption).foregroundStyle(.secondary)
                        // What the phrase means, in the traveller's own language.
                        Text(L(tip.english)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Speaker.shared.speak(tip.hindi)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(verdict.verdict.color.opacity(0.14)), in: .rect(cornerRadius: 28))
    }
}

/// Horizontal scale showing the fair zone and where the asked price lands.
struct PriceGauge: View {
    let low: Double
    let high: Double
    let asked: Double?
    let color: Color

    var body: some View {
        let maxValue = max(high * 2, (asked ?? 0) * 1.1, 1)
        GeometryReader { geo in
            let width = geo.size.width
            let lowX = width * CGFloat(low / maxValue)
            let highX = width * CGFloat(high / maxValue)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Theme.mint.opacity(0.85))
                    .frame(width: max(highX - lowX, 8))
                    .offset(x: lowX)
                if let asked {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: min(max(width * CGFloat(asked / maxValue) - 8, 0), width - 16))
                }
            }
        }
        .frame(height: 16)
        // A price scale runs low to high, left to right, in every language (offsets are not mirrored).
        .environment(\.layoutDirection, .leftToRight)
    }
}
