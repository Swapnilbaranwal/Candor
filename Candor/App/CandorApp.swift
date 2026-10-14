import SwiftUI

@main
struct CandorApp: App {
    @State private var app: AppState
    @State private var location: LocationService
    @State private var agent: CandorAgent

    init() {
        // Navigation-bar titles ("Trip", sheet titles) in the heading face too.
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: CandorType.heading(.largeTitle)]
        UINavigationBar.appearance().titleTextAttributes = [.font: CandorType.heading(.headline, weight: .semibold)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: CandorType.font(.body)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: CandorType.font(.caption2, weight: .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: CandorType.font(.subheadline, weight: .medium)], for: .normal)
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
    /// Day feels like day, night like night: the app's appearance follows the time of day.
    @State private var period = DayPeriod.now()
    @Environment(\.scenePhase) private var scenePhase

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
        // One typeface everywhere: text without its own font uses Candor's body style.
        .font(.candor(.body))
        // The accent for every screen, the login included (the tab view sets it again for its tabs).
        .tint(Theme.accent)
        .environment(\.locale, Localizer.shared.locale)
        .environment(\.layoutDirection, Localizer.shared.layoutDirection)
        .onChange(of: app.phase, initial: true) { _, phase in
            if phase == .main { location.start() }
        }
        // One look all day: Candor's warm light theme. Only the sky on today's trip card
        // follows the time (morning, afternoon, evening, night).
        .preferredColorScheme(.light)
        .onChange(of: period, initial: true) { _, value in applyAppearance(value) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { period = DayPeriod.now() }
        }
        .task { await app.currency.refresh() }
        .task {
            // Long enough to read the name, short enough to never feel like waiting.
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
            // Google Maps is only needed on the Trip tab: start it once the first screen is up,
            // so it doesn't hold up launch.
            try? await Task.sleep(for: .milliseconds(300))
            GoogleMapsSetup.start()
        }
    }
}

extension RootView {
    /// Sheets and full-screen covers are separate presentations, so the window itself is switched too.
    fileprivate func applyAppearance(_ period: DayPeriod) {
        let style: UIUserInterfaceStyle = .light
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}

/// Candor's planning loader as a still picture: the logo at the centre, a dotted orbit, and
/// India's ingredients (food, Metro, monuments, fair prices, markets, walks) resting around it,
/// with the name underneath. Nothing moves or spins, so it's on screen instantly and never
/// holds up the app.
struct SplashView: View {
    private static let ingredients: [(icon: String, tint: Color)] = [
        ("fork.knife", Theme.saffron), ("tram.fill", Theme.teal), ("building.columns.fill", Theme.rose),
        ("indianrupeesign", Theme.emerald), ("bag.fill", Theme.coral), ("figure.walk", Theme.indigo)
    ]

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(Theme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [3, 7]))
                        .frame(width: 236, height: 236)
                    ForEach(Self.ingredients.indices, id: \.self) { index in
                        let item = Self.ingredients[index]
                        let angle = 2 * Double.pi * Double(index) / Double(Self.ingredients.count) - Double.pi / 2
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .frame(width: 48, height: 48)
                            .background(Color.white, in: .circle)
                            .overlay(Circle().strokeBorder(item.tint.opacity(0.18), lineWidth: 1))
                            .offset(x: 118 * cos(angle), y: 118 * sin(angle))
                    }
                    CandorLogo(size: 104)
                }
                .frame(width: 300, height: 300)

                VStack(spacing: 6) {
                    Text("Candor")
                        .font(.display(size: 40, .bold))
                        .foregroundStyle(Theme.ink)
                    Text(L("Explore India. Pay what locals pay."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Candor")
    }
}
