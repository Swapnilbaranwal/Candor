import SwiftUI

/// Phrases: the few lines a traveller needs in Hindi, to hear out loud or show full screen.
/// Works offline. Typed translation goes through the Agent ("How do I say…?").
struct InterpreterView: View {
    @State private var category = "Prices"
    @State private var showing: Phrase?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Tap to hear it, or show it full screen to a driver or shopkeeper. Works offline."))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DelhiData.phraseCategories, id: \.self) { item in
                            Chip(title: L(item), isSelected: category == item, tint: Theme.accent) {
                                withAnimation(.snappy) { category = item }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                VStack(spacing: 10) {
                    ForEach(DelhiData.phrases.filter { $0.category == category }) { phrase in
                        phraseRow(phrase)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle(L("Phrases"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { phrase in
            ShowPhraseSheet(phrase: phrase)
                .presentationDetents([.large])
        }
    }

    private func phraseRow(_ phrase: Phrase) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L(phrase.english)).font(.candor(.caption1)).foregroundStyle(.secondary)
                Text(phrase.roman).font(.candor(.headline, .semibold))
                Text(phrase.hindi).font(.hindi(.subheadline))
            }
            Spacer()
            Button {
                Speaker.shared.speak(phrase.hindi)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(L("Speak"))
            Button {
                showing = phrase
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(L("Show full screen"))
        }
        .card(cornerRadius: 16, padding: 14)
    }
}

/// Big, high-contrast card to show a driver or shopkeeper.
struct ShowPhraseSheet: View {
    let phrase: Phrase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Text(phrase.hindi)
                    .font(.hindi(.largeTitle, semibold: true, size: 54))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                if !phrase.roman.isEmpty {
                    Text(phrase.roman)
                        .font(.candor(.title2, .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text(L(phrase.english))
                    .font(.candor(.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    HStack(spacing: 12) {
                        Button {
                            Speaker.shared.speak(phrase.hindi)
                        } label: {
                            Label(L("Speak"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity).frame(height: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        Button {
                            dismiss()
                        } label: {
                            Label(L("Close"), systemImage: "xmark").frame(maxWidth: .infinity).frame(height: 30)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(28)
        }
    }
}
