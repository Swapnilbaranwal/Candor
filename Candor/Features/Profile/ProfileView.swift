import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var showKey = false
    @State private var confirmReset = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, ok, failed(String)
    }

    private var languages: [String] {
        var list = DelhiData.languages
        if !list.contains(app.persona.languageCode) { list.insert(app.persona.languageCode, at: 0) }
        return list
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    personaHeader
                    preferencesCard(app: $app.persona)
                    aiCard(key: $app.geminiKey, model: $app.geminiModel)
                    accountCard
                    Text(L("Candor prototype · Delhi pilot · v1.0"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LiquidBackground())
            .navigationTitle(L("Me"))
            .confirmationDialog(L("Clear all saved checks?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L("Clear checks"), role: .destructive) { app.resetStats() }
            }
        }
    }

    private var personaHeader: some View {
        VStack(spacing: 12) {
            Text(app.persona.initials)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .glassEffect(.regular.tint(Theme.indigo), in: .circle)
            Text(app.persona.name.isEmpty ? L("Traveller") : app.persona.name)
                .font(.title2.weight(.bold))
            Text(app.persona.accountLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                tag(app.persona.travelStyle.title, app.persona.travelStyle.icon)
                tag(L("Days: %@", app.persona.tripDays), "calendar")
                tag(app.persona.homeCurrency, "banknote")
            }
            if !app.persona.interests.isEmpty {
                Text(app.persona.interests.map { L($0) }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, padding: 22)
    }

    private func tag(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }

    private func preferencesCard(app persona: Binding<Persona>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Preferences"), systemImage: "slider.horizontal.3").font(.headline)
            HStack {
                Text(L("Name"))
                TextField(L("Your name"), text: persona.name)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
            HStack {
                Text(L("Language"))
                Spacer()
                Picker(L("Language"), selection: persona.languageCode) {
                    ForEach(languages, id: \.self) { code in
                        Text(Persona.nativeName(of: code)).tag(code)
                    }
                }
            }
            Divider()
            HStack {
                Text(L("Home currency"))
                Spacer()
                Picker(L("Home currency"), selection: persona.homeCurrency) {
                    ForEach(CurrencyOption.all) { option in
                        Text("\(option.flag) \(option.code)").tag(option.code)
                    }
                }
            }
            Divider()
            HStack {
                Text(L("Travel style"))
                Spacer()
                Picker(L("Travel style"), selection: persona.travelStyle) {
                    ForEach(TravelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }
            Divider()
            Stepper(L("Days in Delhi: %@", persona.wrappedValue.tripDays), value: persona.tripDays, in: 1...14)
        }
        .glassCard()
    }

    private func aiCard(key: Binding<String>, model: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("AI settings"), systemImage: "sparkles").font(.headline)
                Spacer()
                Text(app.hasGemini ? L("Gemini live") : L("Offline agent"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint((app.hasGemini ? Theme.mint : Theme.saffron).opacity(0.4)), in: .capsule)
            }
            Text(L("Add a Gemini API key from Google AI Studio to turn on photo reading, live reasoning and free translation. Without a key, Candor runs an on-device agent with the same tools."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Group {
                    if showKey {
                        TextField(L("Gemini API key"), text: key)
                    } else {
                        SecureField(L("Gemini API key"), text: key)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline.monospaced())
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            HStack {
                Text(L("Model")).font(.subheadline)
                TextField("gemini-2.5-flash", text: model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await testConnection() }
                } label: {
                    Label(L("Test connection"), systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(.glass)
                .disabled(!app.hasGemini || testState == .testing)

                switch testState {
                case .idle: EmptyView()
                case .testing: ProgressView()
                case .ok: Label(L("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint).font(.caption.weight(.semibold))
                case .failed(let message): Text(message).font(.caption).foregroundStyle(Theme.rose).lineLimit(2)
                }
            }

            Label(L("Prototype stores the key on this device. For the submission, call Gemini through a Cloud Run proxy instead."), systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var accountCard: some View {
        VStack(spacing: 10) {
            Button {
                confirmReset = true
            } label: {
                Label(L("Clear saved checks"), systemImage: "trash").frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glass)
            .disabled(app.records.isEmpty)

            Button(role: .destructive) {
                app.signOut()
            } label: {
                Label(L("Sign out"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glass)
            .tint(Theme.rose)
        }
    }

    private func testConnection() async {
        testState = .testing
        do {
            let client = GeminiClient(apiKey: app.geminiKey, model: app.geminiModel)
            _ = try await client.ask("Reply with the single word: ready")
            testState = .ok
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}
