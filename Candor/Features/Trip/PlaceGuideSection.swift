import SwiftUI

/// Inside an opened stop on the Trip tab: things to do there, and questions answered right here,
/// without leaving for the Agent tab.
struct PlaceGuideSection: View {
    let stop: TripStop
    /// How the traveller gets here, for fare questions.
    var leg: Leg?
    @Environment(AppState.self) private var app
    @Environment(CandorAgent.self) private var agent
    @State private var info: PlaceGuideInfo?
    @State private var question = ""
    @State private var asked: String?
    @State private var answer: AgentResult?
    @State private var thinking = false
    @FocusState private var focused: Bool

    private let quickQuestions = ["Best time to go?", "What should it cost?", "Anything to watch for?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thingsToDo
            askBox
        }
        .task(id: stop.id) { info = await PlaceGuide.info(for: stop, app: app) }
    }

    // MARK: Things to do

    @ViewBuilder
    private var thingsToDo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What to do there"))
                .font(.candor(.subheadline, .semibold))
            if let info {
                if let meta = metaLine(info) {
                    Text(starred: meta)
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
                if let summary = info.summary, stop.spot == nil {
                    Text(summary).font(.candor(.subheadline))
                }
                ForEach(info.thingsToDo, id: \.self) { idea in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.candor(.caption1, .bold))
                            .foregroundStyle(Theme.saffron)
                        Text(idea).font(.candor(.subheadline))
                    }
                }
                Text(L("From %@", info.source))
                    .font(.candor(.caption2))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Looking it up…")).font(.candor(.subheadline)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metaLine(_ info: PlaceGuideInfo) -> String? {
        var parts: [String] = []
        if let rating = info.rating { parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1)))) }
        if let hours = info.hoursToday { parts.append(L("Open today %@", hours)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Ask

    private var askBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickQuestions, id: \.self) { item in
                        Chip(title: L(item), tint: Theme.accent) { ask(L(item)) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            HStack(spacing: 8) {
                TextField(L("Ask about %@…", L(stop.name)), text: $question)
                    .font(.candor(.subheadline))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { ask(question) }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.field, in: .capsule)
                Button { ask(question) } label: {
                    Image(systemName: "arrow.up")
                        .font(.candor(.subheadline, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.brandFill, in: .circle)
                }
                .buttonStyle(.pressable)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                .accessibilityLabel(L("Ask"))
            }

            if let asked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(asked)
                        .font(.candor(.caption1, .semibold))
                        .foregroundStyle(.secondary)
                    if thinking {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                    } else if let answer {
                        if let verdict = answer.verdict { VerdictCardView(verdict: verdict) }
                        MarkdownText(text: answer.text).font(.candor(.subheadline))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
                .transition(.opacity)
            }
        }
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        focused = false
        question = ""
        withAnimation(.smooth) {
            asked = trimmed
            answer = nil
            thinking = true
        }
        Task {
            let result = await PlaceGuide.answer(trimmed, about: stop, leg: leg, info: info, app: app, agent: agent)
            withAnimation(.smooth) {
                answer = result
                thinking = false
            }
        }
    }
}
