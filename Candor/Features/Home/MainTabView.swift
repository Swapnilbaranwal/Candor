import SwiftUI

enum AppTab: Hashable {
    case home, trip, check, agent, profile
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    /// "Where are you staying?" and the way back home, reachable from every tab.
    @State private var router = WayHomeRouter()
    /// The Check tab's navigation, here so Home can open a Check tool directly.
    @State private var checkPath: [CheckRoute] = []

    var body: some View {
        TabView(selection: $tab) {
            Tab(L("Home"), systemImage: "house.fill", value: AppTab.home) {
                HomeView(tab: $tab, checkPath: $checkPath)
            }
            Tab(L("Trip"), systemImage: "map.fill", value: AppTab.trip) {
                TripView(tab: $tab)
            }
            Tab(L("Check"), systemImage: "checkmark.shield.fill", value: AppTab.check) {
                CheckView(tab: $tab, path: $checkPath)
            }
            Tab(L("Agent"), systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.agent) {
                AgentView()
            }
            Tab(L("Me"), systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Always one tap from home, or from telling Candor where home is.
        .tabViewBottomAccessory {
            HomeAccessory()
        }
        .sheet(isPresented: $router.showSetup) {
            StaySetupSheet()
                .environment(router)
        }
        .fullScreenCover(isPresented: $router.showWayHome) {
            WayHomeView()
                .environment(router)
        }
        .environment(router)
        // Until we know where the traveller is staying, ask on launch and whenever they come back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { router.askIfNeeded(app) }
        }
        .onAppear {
            // `-candor.tab trip` at launch opens a tab directly (screenshots and UI tests).
            switch UserDefaults.standard.string(forKey: "candor.tab") {
            case "trip": tab = .trip
            case "check": tab = .check
            case "agent": tab = .agent
            case "profile": tab = .profile
            default: break
            }
            if let start = app.startTab {
                tab = start
                app.startTab = nil
            }
            router.askIfNeeded(app)
        }
    }
}
