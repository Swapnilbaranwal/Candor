import SwiftUI

/// Sign-in with Apple, Google, email, a mobile number from any country, or as a guest.
/// No option needs an Indian number. Prototype: nothing is verified, no SMS or email is sent.
struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var mode: ContactMode = .email
    @State private var email = ""
    @State private var phone = ""
    @State private var country = DelhiData.defaultCountry
    @State private var loading: SignInMethod?
    @State private var appeared = false
    @State private var showSignIn = false
    @FocusState private var fieldFocused: Bool

    private enum ContactMode: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        var id: String { rawValue }
        var title: String { L(rawValue) }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shape check only (name@domain.tld). Real verification belongs to the auth backend.
    private var emailIsValid: Bool {
        let parts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !trimmedEmail.contains(" ") else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty } && (labels.last?.count ?? 0) >= 2
    }

    private var contactIsValid: Bool {
        switch mode {
        case .email: return emailIsValid
        case .phone: return country.isValid(phone)
        }
    }

    private var contactIsLoading: Bool {
        loading == .email || loading == .phone
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            landingText
            Spacer(minLength: 12)
            landingButtons
        }
        .background(AppBackground())
        .sheet(isPresented: $showSignIn) { signInSheet }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.3)) { appeared = true }
        }
    }

    // MARK: Landing

    /// The same picture as sign-in: Delhi under today's sky with what Candor does floating over
    /// it (a fair price, a translation, the way back home, the Lens), and the wordmark above.
    private var hero: some View {
        VStack(spacing: 18) {
            Text("Candor")
                .font(.display(size: 30, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
            ProductArt()
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.top, 8)
    }

    private var landingText: some View {
        VStack(spacing: 12) {
            Text(L("Discover India like a local"))
                .font(.display(size: 34))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Fair prices, safe rides and your way back home, in your language."))
                .font(.candor(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .reveal(1)
    }

    private var landingButtons: some View {
        VStack(spacing: 12) {
            Button(L("Get Started")) {
                mode = .email
                showSignIn = true
            }
            .buttonStyle(.pill)
            .accessibilityIdentifier("getStarted")

            Button(L("Log in")) { showSignIn = true }
                .buttonStyle(.pillOutline)
                .accessibilityIdentifier("logIn")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .reveal(2)
    }

    /// The sign-in options, in a sheet over the landing page.
    private var signInSheet: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProductArt()
                    .padding(.top, 14)
                    .padding(.horizontal, -20)
                loginCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    // MARK: Sign-in card

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sign in")).font(.heading(.title2))
                Text(L("Use whatever you have. No Indian number needed."))
                    .font(.candor(.subheadline))
                    .foregroundStyle(.secondary)
            }

            // One-tap options fold away while typing so the card fits above the keyboard.
            if !fieldFocused {
                HStack(spacing: 10) {
                    providerButton("Apple", icon: "apple.logo", method: .apple)
                    providerButton("Google", icon: "g.circle.fill", method: .google)
                }

                orDivider
            }

            Picker(L("Sign in with"), selection: $mode) {
                ForEach(ContactMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(loading != nil)

            switch mode {
            case .email: emailField
            case .phone: phoneField
            }

            Button(action: submitContact) {
                HStack(spacing: 8) {
                    if contactIsLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(L("Continue"))
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.candor(.headline, .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.pill)
            .disabled(!contactIsValid || loading != nil)
            .animation(.snappy, value: contactIsValid)
            .sensoryFeedback(.success, trigger: contactIsValid) { _, valid in valid }

            VStack(spacing: 8) {
                Button(L("Continue as guest")) { signIn(.guest) }
                    .font(.candor(.subheadline, .semibold))
                    .disabled(loading != nil)

                Text(footnote)
                    .font(.candor(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.large))
        .shadow(color: Theme.shadow, radius: 18, y: 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { fieldFocused = false }
                    .accessibilityIdentifier("keyboardDone") // UI tests find it in any language
            }
        }
    }

    private var footnote: String {
        switch mode {
        case .email: return L("Prototype: nothing is verified. No email is sent.")
        case .phone: return L("Any country's number works. Prototype: no SMS is sent.")
        }
    }

    /// Apple and Google are prototype stubs: tapping signs in without contacting either provider.
    /// Swap `signIn(_:)` for AuthenticationServices / GoogleSignIn when the real flows are wired in.
    private func providerButton(_ title: String, icon: String, method: SignInMethod) -> some View {
        Button {
            signIn(method)
        } label: {
            HStack(spacing: 8) {
                if loading == method {
                    ProgressView()
                } else {
                    Image(systemName: icon)
                    Text(title)
                }
            }
            .font(.candor(.headline, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(.bordered)
        // Provider buttons stay black and white (Apple's sign-in guidelines), not the accent.
        .tint(.primary)
        .disabled(loading != nil)
        .accessibilityLabel(L("Continue with %@", title))
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text(L("or"))
                .font(.candor(.caption1, .semibold))
                .foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }

    private var emailField: some View {
        // The example address is a verbatim prompt: as a plain title SwiftUI styles it as a blue link.
        TextField(L("Email"), text: $email, prompt: Text(verbatim: "you@example.com"))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.continue)
            .onSubmit { submitContact() }
            .focused($fieldFocused)
            .font(.candor(.title3, .semibold))
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Theme.field, in: .capsule)
    }

    private var phoneField: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(DelhiData.countryCodes) { code in
                    Button("\(code.flag)  \(code.region)  \(code.dial)") { country = code }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(country.flag)
                    Text(country.dial).monospacedDigit()
                    Image(systemName: "chevron.down").font(.candor(.caption2, .bold))
                }
                .font(.candor(.headline, .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(Theme.field, in: .capsule)
            }

            TextField(L("Mobile number"), text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .focused($fieldFocused)
                .font(.candor(.title3, .semibold).monospacedDigit())
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(Theme.field, in: .capsule)
                .onChange(of: phone) { _, newValue in
                    phone = clamped(newValue)
                }
                .onChange(of: country) { _, _ in
                    phone = clamped(phone)
                }
        }
    }

    /// Digits only, capped at the selected country's longest number (+1 for a leading trunk "0").
    private func clamped(_ input: String) -> String {
        String(input.filter { $0.isASCII && $0.isNumber }.prefix(country.digits.upperBound + 1))
    }

    // MARK: Actions

    private func submitContact() {
        guard contactIsValid else { return }
        signIn(mode == .email ? .email : .phone)
    }

    private func signIn(_ method: SignInMethod) {
        guard loading == nil else { return }
        fieldFocused = false

        if method == .guest {
            app.signIn(with: .guest)
            return
        }

        let phoneNumber = method == .phone ? "\(country.dial) \(country.national(phone))" : ""
        let emailAddress = method == .email ? trimmedEmail : nil
        loading = method
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            app.signIn(with: method, phone: phoneNumber, email: emailAddress)
            loading = nil
        }
    }
}

#Preview {
    LoginView().environment(AppState())
}
