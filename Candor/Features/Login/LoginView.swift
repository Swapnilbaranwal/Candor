import SwiftUI

/// Mobile-number login. Any 10-digit number enables Continue (prototype: no OTP).
struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var phone = ""
    @State private var country = DelhiData.defaultCountry
    @State private var isLoading = false
    @State private var appeared = false
    @FocusState private var phoneFocused: Bool

    private var isValid: Bool { phone.count == 10 }

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    CandorLogo(size: 96)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                    VStack(spacing: 6) {
                        Text("Candor")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                        Text("Explore India. Pay what locals pay.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                    featureRow
                        .opacity(appeared ? 1 : 0)
                }

                Spacer()

                loginCard
                    .offset(y: appeared ? 0 : 60)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onTapGesture { phoneFocused = false }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.35)) { appeared = true }
        }
    }

    private var featureRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                feature("camera.viewfinder", "Scan prices")
                feature("car.fill", "Fair fares")
                feature("shield.lefthalf.filled", "Scam radar")
            }
        }
        .padding(.top, 6)
    }

    private func feature(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in").font(.title2.weight(.bold))
                Text("Enter your mobile number to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                TextField("10-digit number", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($phoneFocused)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .onChange(of: phone) { _, newValue in
                        let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(10))
                        if digits != newValue { phone = digits }
                    }
            }

            digitProgress

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.saffron)
            .disabled(!isValid || isLoading)
            .animation(.snappy, value: isValid)
            .sensoryFeedback(.success, trigger: isValid) { _, valid in valid }

            Text("Prototype: any 10-digit number works. No SMS is sent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { phoneFocused = false }
            }
        }
    }

    private var digitProgress: some View {
        HStack(spacing: 5) {
            ForEach(0..<10, id: \.self) { index in
                Capsule()
                    .fill(index < phone.count ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.quaternary))
                    .frame(height: 5)
            }
            Text("\(phone.count)/10")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isValid ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(.secondary))
                .frame(width: 40, alignment: .trailing)
        }
        .animation(.snappy, value: phone.count)
    }

    private func signIn() {
        guard isValid else { return }
        phoneFocused = false
        isLoading = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            app.signIn(phone: "\(country.dial) \(phone)")
            isLoading = false
        }
    }
}

#Preview {
    LoginView().environment(AppState())
}
