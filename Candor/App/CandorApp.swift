import SwiftUI

@main
struct CandorApp: App {
    @State private var app: AppState
    @State private var location: LocationService
    @State private var agent: CandorAgent

    init() {
        GoogleMapsSetup.start()
        // Navigation-bar titles ("Trip", sheet titles) in the heading face too.
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: CandorType.heading(.largeTitle)]
        UINavigationBar.appearance().titleTextAttributes = [.font: CandorType.heading(.headline, weight: 650)]
        let app = AppState()
        let location = LocationService()
        _app = State(initialValue: app)
        _location = State(initialValue: location)
        _agent = State(initialValue: CandorAgent(app: app, location: location))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(location)
                .environment(agent)
        }
    }
}

/// Switches between login, persona setup and the main app.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var showSplash = true

    var body: some View {
        ZStack {
            switch app.phase {
            case .login:
                LoginView()
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .onboarding:
                PersonaSetupView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .main:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.55), value: app.phase)
        // The language chosen in the app sets SwiftUI's locale and, for Arabic and Hebrew, mirrors the layout.
        // Numbers and dates formatted with `.formatted()` still follow the phone's own locale.
        .environment(\.locale, Localizer.shared.locale)
        .environment(\.layoutDirection, Localizer.shared.layoutDirection)
        .onChange(of: app.phase, initial: true) { _, phase in
            if phase == .main { location.start() }
        }
        .task { await app.currency.refresh() }
        .task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.smooth(duration: 0.5)) { showSplash = false }
        }
    }
}

/// Picks up where the launch screen leaves off: the same logo on the same colour, in the same spot,
/// then the name and tagline appear before the first screen fades in.
struct SplashView: View {
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            AppBackground()
                .opacity(revealed ? 1 : 0)

            Image("LaunchLogo")
                .shadow(color: Theme.rose.opacity(revealed ? 0.45 : 0), radius: 24, y: 8)
                .scaleEffect(revealed ? 1.06 : 1)
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        Text("Candor")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text(L("Explore India. Pay what locals pay."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .offset(y: 150)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 12)
                }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) { revealed = true }
        }
    }
}
