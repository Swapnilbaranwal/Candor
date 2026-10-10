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
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                Spacer()

                // The hero steps aside while typing so the card clears the keyboard.
                if !fieldFocused {
                    hero
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    Spacer()
                }

                loginCard
                    .offset(y: appeared ? 0 : 60)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(.snappy, value: fieldFocused)
        }
        .onTapGesture { fieldFocused = false }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.35)) { appeared = true }
        }
    }

    // MARK: Hero

    /// Logo and name only: the sign-in card below is the whole job of this screen.
    private var hero: some View {
        VStack(spacing: 16) {
            CandorLogo(size: 96)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text("Candor")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
        }
    }

    // MARK: Sign-in card

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sign in")).font(.heading(.title2))
                Text(L("Use whatever you have. No Indian number needed."))
                    .font(.subheadline)
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
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.saffron)
            .disabled(!contactIsValid || loading != nil)
            .animation(.snappy, value: contactIsValid)
            .sensoryFeedback(.success, trigger: contactIsValid) { _, valid in valid }

            VStack(spacing: 8) {
                Button(L("Continue as guest")) { signIn(.guest) }
                    .font(.subheadline.weight(.semibold))
                    .disabled(loading != nil)

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
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
            .font(.headline)
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
                .font(.caption.weight(.semibold))
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
            .font(.title3.weight(.semibold))
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
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(Theme.field, in: .capsule)
            }

            TextField(L("Mobile number"), text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .focused($fieldFocused)
                .font(.title3.weight(.semibold).monospacedDigit())
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
