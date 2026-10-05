import SwiftUI

@main
struct CandorApp: App {
    @State private var app: AppState
    @State private var location: LocationService
    @State private var agent: CandorAgent

    init() {
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
        }
        .animation(.smooth(duration: 0.55), value: app.phase)
        .onChange(of: app.phase, initial: true) { _, phase in
            if phase == .main { location.start() }
        }
        .task { await app.currency.refresh() }
    }
}
