import SwiftUI

/// Interpreter: a two-way conversation between the traveller and someone local. Each side speaks
/// or types in their own language; Candor translates with Google Translate, shows it big and says
/// it out loud. Ready-made Hindi phrases sit underneath for when there's no signal.
struct InterpreterView: View {
    private enum Side { case me, them }

    private struct Turn: Identifiable {
        let id = UUID()
        let side: Side
        let original: String
        let translated: String
        /// The language the translation is in, to speak it.
        let language: InterpreterLanguage
    }

    @Environment(AppState.self) private var app
    @AppStorage("candor.interpreter.theirs") private var theirCode = "hi"
    @AppStorage("candor.interpreter.mine") private var myCode = ""
    @State private var listener = SpeechListener()
    @State private var listeningSide: Side?
    @State private var turns: [Turn] = []
    @State private var draft = ""
    @State private var draftSide: Side = .me
    @State private var isTranslating = false
    @State private var errorText: String?
    @State private var fullScreen: Turn?
    @State private var category = "Prices"
    @State private var showing: Phrase?
    @FocusState private var typing: Bool

    private var mine: InterpreterLanguage {
        InterpreterLanguage.forPersona(myCode.isEmpty ? app.persona.languageCode : myCode)
    }
    private var theirs: InterpreterLanguage {
        (InterpreterLanguage.indian + InterpreterLanguage.world).first { $0.code == theirCode } ?? .hindi
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    languageBar
                    if turns.isEmpty && !isTranslating && listeningSide == nil {
                        emptyHint
                    }
                    ForEach(turns) { turn in
                        turnCard(turn).id(turn.id)
                    }
                    if let listeningSide {
                        liveCard(listeningSide)
                    }
                    if isTranslating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L("Translating…")).font(.candor(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.candor(.caption1))
                            .foregroundStyle(Theme.rose)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    phrasesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in
                withAnimation(.smooth) { scroller.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(AppBackground())
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle(L("Interpreter"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { listener.stop() }
        .onChange(of: listener.isListening) { _, listening in
            // Stopped by the recogniser itself (a pause, a time limit): translate what it heard.
            if !listening, let side = listeningSide { finishListening(side) }
        }
        .sheet(item: $fullScreen) { turn in
            ShowTranslationSheet(text: turn.translated, original: turn.original, language: turn.language)
                .presentationDetents([.large])
        }
        .sheet(item: $showing) { phrase in
            ShowPhraseSheet(phrase: phrase)
                .presentationDetents([.large])
        }
    }

    // MARK: Languages

    private var languageBar: some View {
        HStack(spacing: 10) {
            languageMenu(title: L("You"), selected: mine) { myCode = $0.code }
            Button {
                let old = mine.code
                myCode = theirs.code
                theirCode = old
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(L("Swap languages"))
            languageMenu(title: L("Them"), selected: theirs) { theirCode = $0.code }
        }
    }

    private func languageMenu(title: String, selected: InterpreterLanguage,
                              choose: @escaping (InterpreterLanguage) -> Void) -> some View {
        Menu {
            Section(L("India")) {
                ForEach(InterpreterLanguage.indian) { language in
                    Button(language.name) { choose(language) }
                }
            }
            Section(L("Other languages")) {
                ForEach(InterpreterLanguage.world.filter { $0.code != "en" }) { language in
                    Button(language.name) { choose(language) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.candor(.caption2)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(selected.name).font(.candor(.subheadline, .semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface.opacity(0.85), in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Talk to anyone"), systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.candor(.headline, .semibold))
            Text(L("Tap your mic and speak in your language. Candor says it out loud in theirs and shows it big. Then hand them the phone: they tap their mic to answer, and you read it in yours."))
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Conversation

    private func turnCard(_ turn: Turn) -> some View {
        let isMine = turn.side == .me
        return VStack(alignment: .leading, spacing: 8) {
            Text(turn.translated)
                .font(.candor(.title3, .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(turn.original)
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(isMine ? L("You said") : L("They said"))
                    .font(.candor(.caption2, .semibold))
                    .foregroundStyle(isMine ? Theme.accent : Theme.teal)
                Spacer()
                Button { Speaker.shared.speak(turn.translated, language: turn.language.speechLocale) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L("Speak"))
                Button { fullScreen = turn } label: {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L("Show full screen"))
            }
        }
        .card(tint: isMine ? Theme.accent : Theme.teal)
        .padding(isMine ? .trailing : .leading, 24)
    }

    private func liveCard(_ side: Side) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(side == .me ? Theme.accent : Theme.teal)
            Text(listener.transcript.isEmpty ? L("Listening…") : listener.transcript)
                .font(.candor(.subheadline))
                .foregroundStyle(listener.transcript.isEmpty ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .card()
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker(L("Who's typing"), selection: $draftSide) {
                    Text(L("Me")).tag(Side.me)
                    Text(L("Them")).tag(Side.them)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                TextField(draftSide == .me ? L("Type in %@", mine.name) : L("Type in %@", theirs.name),
                          text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isTranslating)
                .accessibilityLabel(L("Translate"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.field, in: .rect(cornerRadius: 20, style: .continuous))

            HStack(spacing: 12) {
                micButton(.me, language: mine, tint: Theme.accent)
                micButton(.them, language: theirs, tint: Theme.teal)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func micButton(_ side: Side, language: InterpreterLanguage, tint: Color) -> some View {
        let active = listeningSide == side
        return Button { toggleListening(side) } label: {
            HStack(spacing: 10) {
                Image(systemName: active ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(active ? L("Tap to translate") : (side == .me ? L("I speak") : L("They speak")))
                        .font(.candor(.caption1, .semibold))
                    Text(language.name).font(.candor(.subheadline, .bold)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(active ? Theme.rose : tint, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isTranslating || (listeningSide != nil && !active))
    }

    // MARK: Actions

    private func toggleListening(_ side: Side) {
        if listeningSide == side {
            listener.stop()
            return
        }
        typing = false
        errorText = nil
        listeningSide = side
        Task {
            await listener.start(locale: (side == .me ? mine : theirs).speechLocale)
            if let error = listener.error {
                errorText = error
                listeningSide = nil
            }
        }
    }

    private func finishListening(_ side: Side) {
        listeningSide = nil
        let heard = listener.transcript
        guard !heard.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        translate(heard, side: side)
    }

    private func sendDraft() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        translate(text, side: draftSide)
    }

    /// Translates one turn into the other person's language, shows it and says it out loud.
    private func translate(_ text: String, side: Side) {
        let source = side == .me ? mine : theirs
        let target = side == .me ? theirs : mine
        errorText = nil
        isTranslating = true
        Task {
            do {
                let translated = try await Translator.translate(text, from: source, to: target, app: app)
                withAnimation(.smooth) {
                    turns.append(Turn(side: side, original: text, translated: translated, language: target))
                }
                Speaker.shared.speak(translated, language: target.speechLocale)
            } catch {
                errorText = error.localizedDescription
            }
            isTranslating = false
        }
    }

    // MARK: Ready phrases

    /// The few lines a traveller needs in Hindi, offline.
    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Ready phrases in Hindi")).font(.candor(.headline, .semibold)).padding(.top, 8)
            Text(L("Tap to hear it, or show it full screen to a driver or shopkeeper. Works offline."))
                .font(.candor(.caption1))
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

/// A translation big and high-contrast, to hold up to the other person.
struct ShowTranslationSheet: View {
    let text: String
    let original: String
    let language: InterpreterLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Text(text)
                    .font(.candor(.largeTitle, .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3)
                Text(original)
                    .font(.candor(.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        Speaker.shared.speak(text, language: language.speechLocale)
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
            .padding(28)
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
