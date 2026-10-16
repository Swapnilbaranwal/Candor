import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(AskCandorRouter.self) private var router
    @State private var showKey = false
    /// Share price checks and matched tricks anonymously (see CommunityService).
    @AppStorage(CommunityService.shareKey) private var shareChecks = true
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
        // Pushed from the avatar on Home, inside Home's navigation: a back arrow, no big title.
            ScrollView {
                VStack(spacing: 16) {
                    personaHeader
                    // The trip's cities: edit them and plan the days again when plans change.
                    TripCitiesCard()
                    // How you like to travel: changes the best way around and the fares everywhere.
                    TravelStyleSwitcher()
                        .glossCard(Theme.saffron, padding: 16)
                    tastesCard(app: $app.persona)
                    preferencesCard(app: $app.persona)
                    aiCard(key: $app.geminiKey, model: $app.geminiModel)
                    accountCard
                    Text(L("Candor prototype · Delhi pilot · v1.0"))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            // The avatar and name at the top say whose page this is: no "Me" title above them.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            // A sub-page of Home: no tabs, so Back is the one way out and Home always opens on Home.
            .toolbar(.hidden, for: .tabBar)
            .onAppear { router.isProfileShowing = true }
            .onDisappear { router.isProfileShowing = false }
            .confirmationDialog(L("Clear all saved checks?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L("Clear checks"), role: .destructive) { app.resetStats() }
            }
    }

    private var personaHeader: some View {
        VStack(spacing: 12) {
            Text(app.persona.initials)
                .font(.display(size: 34, .bold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Theme.ink, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(color: Theme.ink.opacity(0.25), radius: 10, y: 5)
            Text(app.persona.name.isEmpty ? L("Traveller") : app.persona.name)
                .font(.heading(.title2))
            Text(app.persona.accountLabel)
                .font(.candor(.subheadline).monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                tag(app.persona.travelStyle.title, app.persona.travelStyle.icon)
                tag(L("Days: %@", app.persona.tripDays), "calendar")
                tag(app.persona.homeCurrency, "banknote")
            }
            HStack(spacing: 10) {
                stat("\(app.records.count)", app.records.count == 1 ? L("check") : L("checks"))
                stat("\(app.overchargesCaught)", app.overchargesCaught == 1 ? L("overcharge caught") : L("overcharges caught"))
                stat(inr(app.totalFlaggedINR), L("flagged"))
            }
            if !app.persona.interests.isEmpty {
                Text(app.persona.interests.map { L($0) }.joined(separator: " · "))
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .velvetCard(.pearl, radius: 30, padding: 22)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.candor(.headline, .bold).monospacedDigit()).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.candor(.caption2)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.8), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func tag(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.candor(.caption1, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.ink)
            .background(Theme.accentSoft, in: .capsule)
    }

    /// What you love and how you like to travel: the persona Candor plans around. Changing it
    /// here changes the suggestions everywhere (new day plans, "What to do there", Ask Candor).
    private func tastesCard(app persona: Binding<Persona>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("What you love"), systemImage: "heart.text.square").font(.candor(.headline, .semibold))
            FlowLayout(spacing: 8) {
                ForEach(DelhiData.interests, id: \.self) { interest in
                    let on = persona.wrappedValue.interests.contains(interest)
                    Chip(title: L(interest), isSelected: on, tint: Theme.accent) {
                        withAnimation(.snappy) {
                            if on { persona.wrappedValue.interests.removeAll { $0 == interest } }
                            else { persona.wrappedValue.interests.append(interest) }
                        }
                    }
                }
            }
            Divider()
            Text(L("How you like it")).font(.candor(.subheadline, .semibold))
            FlowLayout(spacing: 8) {
                ForEach(Persona.tasteOptions, id: \.self) { taste in
                    let on = persona.wrappedValue.hasTaste(taste)
                    Chip(title: L(taste), isSelected: on, tint: Theme.teal) {
                        withAnimation(.snappy) {
                            var list = persona.wrappedValue.tastes ?? []
                            if on { list.removeAll { $0 == taste } } else { list.append(taste) }
                            persona.wrappedValue.tastes = list
                        }
                    }
                }
            }
        }
        .card()
    }

    private func preferencesCard(app persona: Binding<Persona>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Preferences"), systemImage: "slider.horizontal.3").font(.candor(.headline, .semibold))
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
            Stepper(L("Days: %@", persona.wrappedValue.tripDays), value: persona.tripDays, in: 1...14)
            Divider()
            Toggle(isOn: $shareChecks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Share my checks anonymously"))
                    Text(L("Prices and tricks help the next traveller and the city's tourism office. No name, no account, location rounded to about 1 km."))
                        .font(.candor(.caption1))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.emerald)
        }
        .card()
    }

    private func aiCard(key: Binding<String>, model: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("AI settings"), systemImage: "slider.horizontal.3").font(.candor(.headline, .semibold))
                Spacer()
                Text(app.hasGemini ? L("Gemini live") : L("Offline agent"))
                    .font(.candor(.caption1, .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((app.hasGemini ? Theme.mint : Theme.saffron).opacity(0.14), in: .capsule)
            }
            Text(Backend.geminiProxy == nil
                 ? L("Add a Gemini API key from Google AI Studio to turn on photo reading, live reasoning and free translation. Without a key, Candor runs an on-device agent with the same tools.")
                 : L("Gemini runs through Candor's Google Cloud backend, so you don't need a key. If you add your own key here, Candor uses it instead."))
                .font(.candor(.caption1))
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
                .font(.candor(.subheadline).monospacedDigit())
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
            .background(Theme.field, in: .capsule)

            HStack {
                Text(L("Model")).font(.candor(.subheadline))
                TextField("gemini-3.8-flash", text: model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.candor(.subheadline).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await testConnection() }
                } label: {
                    Label(L("Test connection"), systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!app.hasGemini || testState == .testing)

                switch testState {
                case .idle: EmptyView()
                case .testing: ProgressView()
                case .ok: Label(L("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint).font(.candor(.caption1, .semibold))
                case .failed(let message): Text(message).font(.candor(.caption1)).foregroundStyle(Theme.rose).lineLimit(2)
                }
            }

            Label(Backend.geminiProxy == nil
                  ? L("Prototype stores the key on this device. For the submission, call Gemini through a Cloud Run proxy instead.")
                  : L("Candor's Gemini key stays on the server, in Google Cloud. It is not stored in the app."),
                  systemImage: "lock.shield")
                .font(.candor(.caption2))
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var accountCard: some View {
        VStack(spacing: 10) {
            Button {
                confirmReset = true
            } label: {
                Label(L("Clear saved checks"), systemImage: "trash").frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(app.records.isEmpty)

            Button(role: .destructive) {
                app.signOut()
            } label: {
                Label(L("Sign out"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.bordered)
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
