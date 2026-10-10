import SwiftUI

/// Phrasebook with audio plus Gemini-powered free translation.
struct InterpreterView: View {
    @Environment(AppState.self) private var app
    @State private var category = "Prices"
    @State private var showing: Phrase?
    @State private var input = ""
    @State private var toHindi = true
    @State private var translation: String?
    @State private var roman: String?
    @State private var isTranslating = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                translateCard
                SectionHeader(title: L("Phrasebook"), subtitle: L("Tap to hear it, or show it full screen"))
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
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(L("Interpreter"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { phrase in
            ShowPhraseSheet(phrase: phrase)
                .presentationDetents([.large])
        }
    }

    private var translateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(toHindi ? app.persona.languageName : L("Hindi")).font(.candor(.subheadline, .semibold))
                Spacer()
                Button {
                    withAnimation(.snappy) { toHindi.toggle(); translation = nil; roman = nil }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                Spacer()
                Text(toHindi ? L("Hindi") : app.persona.languageName).font(.candor(.subheadline, .semibold))
            }

            TextField(toHindi ? L("Type what you want to say…") : L("Type the Hindi or Hinglish you heard…"), text: $input, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused)
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: 16))

            Button {
                Task { await translate() }
            } label: {
                HStack {
                    if isTranslating { ProgressView().tint(.white) } else { Image(systemName: "character.bubble") }
                    Text(L("Translate"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isTranslating || !app.hasGemini)

            if !app.hasGemini {
                Label(L("Free translation needs a Gemini key (Me → AI settings). The phrasebook below works offline."), systemImage: "key.fill")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.candor(.caption1)).foregroundStyle(Theme.rose)
            }
            if let translation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(translation).font(.candor(.title3, .semibold)).textSelection(.enabled)
                    if let roman { Text(roman).font(.candor(.subheadline)).foregroundStyle(.secondary) }
                    HStack {
                        Button {
                            Speaker.shared.speak(translation, language: toHindi ? "hi-IN" : app.persona.languageCode)
                        } label: {
                            Label(L("Speak"), systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        if toHindi {
                            Button {
                                showing = Phrase(english: input, hindi: translation, roman: roman ?? "", category: "Custom")
                            } label: {
                                Label(L("Show"), systemImage: "rectangle.expand.vertical")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
            }
        }
        .card()
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
            Button {
                showing = phrase
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .card(cornerRadius: 16, padding: 14)
    }

    private func translate() async {
        focused = false
        error = nil
        isTranslating = true
        defer { isTranslating = false }
        do {
            let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
            let output = try await client.translate(input, toHindi: toHindi, userLanguage: app.persona.englishLanguageName)
            withAnimation(.smooth) {
                translation = output.text
                roman = output.roman
            }
        } catch {
            self.error = error.localizedDescription
        }
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
