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
                    Text("Candor prototype · Delhi pilot · v1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LiquidBackground())
            .navigationTitle("Me")
            .confirmationDialog("Clear all saved checks?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear checks", role: .destructive) { app.resetStats() }
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
            Text(app.persona.name.isEmpty ? "Traveller" : app.persona.name)
                .font(.title2.weight(.bold))
            Text(app.persona.accountLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                tag(app.persona.travelStyle.title, app.persona.travelStyle.icon)
                tag("\(app.persona.tripDays) days", "calendar")
                tag(app.persona.homeCurrency, "banknote")
            }
            if !app.persona.interests.isEmpty {
                Text(app.persona.interests.joined(separator: " · "))
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
            Label("Preferences", systemImage: "slider.horizontal.3").font(.headline)
            HStack {
                Text("Name")
                TextField("Your name", text: persona.name)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
            HStack {
                Text("Language")
                Spacer()
                Picker("Language", selection: persona.languageCode) {
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
            }
            Divider()
            HStack {
                Text("Home currency")
                Spacer()
                Picker("Home currency", selection: persona.homeCurrency) {
                    ForEach(CurrencyOption.all) { option in
                        Text("\(option.flag) \(option.code)").tag(option.code)
                    }
                }
            }
            Divider()
            HStack {
                Text("Travel style")
                Spacer()
                Picker("Travel style", selection: persona.travelStyle) {
                    ForEach(TravelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }
            Divider()
            Stepper("Days in Delhi: \(persona.wrappedValue.tripDays)", value: persona.tripDays, in: 1...14)
        }
        .glassCard()
    }

    private func aiCard(key: Binding<String>, model: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AI settings", systemImage: "sparkles").font(.headline)
                Spacer()
                Text(app.hasGemini ? "Gemini live" : "Offline agent")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint((app.hasGemini ? Theme.mint : Theme.saffron).opacity(0.4)), in: .capsule)
            }
            Text("Add a Gemini API key from Google AI Studio to turn on photo reading, live reasoning and free translation. Without a key, Candor runs an on-device agent with the same tools.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Group {
                    if showKey {
                        TextField("Gemini API key", text: key)
                    } else {
                        SecureField("Gemini API key", text: key)
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
                Text("Model").font(.subheadline)
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
                    Label("Test connection", systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(.glass)
                .disabled(!app.hasGemini || testState == .testing)

                switch testState {
                case .idle: EmptyView()
                case .testing: ProgressView()
                case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint).font(.caption.weight(.semibold))
                case .failed(let message): Text(message).font(.caption).foregroundStyle(Theme.rose).lineLimit(2)
                }
            }

            Label("Prototype stores the key on this device. For the submission, call Gemini through a Cloud Run proxy instead.", systemImage: "lock.shield")
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
                Label("Clear saved checks", systemImage: "trash").frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glass)
            .disabled(app.records.isEmpty)

            Button(role: .destructive) {
                app.signOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).frame(height: 30)
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
