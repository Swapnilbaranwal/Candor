import SwiftUI

/// Builds the traveller persona, then shows the agent "setting itself up".
struct PersonaSetupView: View {
    @Environment(AppState.self) private var app
    @State private var draft = Persona()
    @State private var isBuilding = false
    @State private var buildSteps: [AgentStep] = []
    @FocusState private var nameFocused: Bool

    private var languages: [String] {
        var list = DelhiData.languages
        if !list.contains(draft.languageCode) { list.insert(draft.languageCode, at: 0) }
        return list
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nameCard
                    languageCurrencyCard
                    styleCard
                    interestsCard
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: build) {
                    Label("Build my travel persona", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.indigo)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            if isBuilding {
                buildingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear { draft = app.persona }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentOrb(size: 52)
            Text("Let's get to know you")
                .font(.largeTitle.weight(.bold))
            Text("Candor uses this to speak your language, show your currency and tailor its advice.")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What should we call you?", systemImage: "person.fill").font(.headline)
            TextField("Your name", text: $draft.name)
                .textContentType(.givenName)
                .focused($nameFocused)
                .font(.title3)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .glassCard()
    }

    private var languageCurrencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Language & money", systemImage: "globe").font(.headline)
            HStack {
                Text("App language")
                Spacer()
                Picker("App language", selection: $draft.languageCode) {
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Defaults to your device language. Candor's agent replies in it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Home currency")
                Spacer()
                Picker("Home currency", selection: $draft.homeCurrency) {
                    ForEach(CurrencyOption.all) { option in
                        Text("\(option.flag) \(option.code)").tag(option.code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .glassCard()
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How do you travel?", systemImage: "figure.walk").font(.headline)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(TravelStyle.allCases) { style in
                        Button {
                            withAnimation(.snappy) { draft.travelStyle = style }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: style.icon).font(.title3)
                                Text(style.title).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(draft.travelStyle == style ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(draft.travelStyle == style ? Glass.regular.tint(Theme.indigo).interactive() : Glass.regular.interactive(),
                                         in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Stepper("Days in Delhi: \(draft.tripDays)", value: $draft.tripDays, in: 1...14)
        }
        .glassCard()
    }

    private var interestsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What do you love?", systemImage: "heart.fill").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(DelhiData.interests, id: \.self) { interest in
                    GlassChip(title: interest, isSelected: draft.interests.contains(interest), tint: Theme.rose) {
                        withAnimation(.snappy) {
                            if let index = draft.interests.firstIndex(of: interest) {
                                draft.interests.remove(at: index)
                            } else {
                                draft.interests.append(interest)
                            }
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    private var buildingOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 22) {
                AgentOrb(size: 88, isActive: true)
                Text("Setting up your agent")
                    .font(.title2.weight(.bold))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(buildSteps) { step in
                        StepRow(step: step)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .glassCard()
            }
            .padding(24)
        }
    }

    private func build() {
        nameFocused = false
        var persona = draft
        persona.name = persona.name.trimmingCharacters(in: .whitespaces)
        app.persona = persona
        withAnimation(.smooth) { isBuilding = true }

        Task {
            let plan: [(String, String, String)] = [
                ("character.bubble.fill", "Speaking \(persona.languageName)", "Agent replies and tips in your language"),
                ("dollarsign.arrow.circlepath", "Linking \(persona.homeCurrency)", "Fetching today's exchange rates"),
                ("gauge.with.needle.fill", "Loading Delhi fare chart", "Auto ₹30 + ₹11/km · Taxi ₹40 + ₹17/km"),
                ("tag.fill", "Loading fair-price references", "\(DelhiData.prices.count) items with sources"),
                ("shield.lefthalf.filled", "Arming scam radar", "\(DelhiData.scams.count) known patterns"),
                ("map.fill", "Tuning for \(persona.travelStyle.title.lowercased()) travel", persona.interests.isEmpty ? "All interests" : persona.interests.joined(separator: ", "))
            ]
            for (icon, title, detail) in plan {
                var step = AgentStep(icon: icon, title: title, detail: detail)
                withAnimation(.snappy) { buildSteps.append(step) }
                if icon == "dollarsign.arrow.circlepath" {
                    await app.currency.refresh()
                } else {
                    try? await Task.sleep(for: .milliseconds(420))
                }
                step.state = .done
                withAnimation(.snappy) { upsertStep(step, in: &buildSteps) }
            }
            try? await Task.sleep(for: .milliseconds(500))
            app.completeOnboarding()
        }
    }
}

#Preview {
    PersonaSetupView().environment(AppState())
}
