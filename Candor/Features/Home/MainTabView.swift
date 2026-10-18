import SwiftUI

enum AppTab: Hashable {
    case home, trip, check
}

/// "Ask Candor": the agent chat as a sheet, opened from the ✨ button on Home and Trip.
@Observable
final class AskCandorRouter {
    var isOpen = false
    /// Me (profile and settings), opened from the avatar on Home.
    var isProfileOpen = false
    /// True while Me is on screen: it hides the "Way back home" bar, like the tabs.
    var isProfileShowing = false

    func open() { isOpen = true }
    func openProfile() { isProfileOpen = true }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    /// "Where are you staying?" and the way back home, reachable from every tab.
    @State private var router = WayHomeRouter()
    /// The Check tab's navigation, here so Home can open a Check tool directly.
    @State private var checkPath: [CheckRoute] = []
    @State private var ask = AskCandorRouter()

    /// Phosphor icons (MIT, in Assets.xcassets/TabIcons): outline, filled when selected.
    private func tabLabel(_ title: String, icon: String, tab item: AppTab) -> some View {
        Label(title, image: tab == item ? "tab-\(icon)-fill" : "tab-\(icon)")
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.home) {
                HomeView(tab: $tab, checkPath: $checkPath)
            } label: {
                tabLabel(L("Home"), icon: "house", tab: .home)
            }
            Tab(value: AppTab.trip) {
                TripView(tab: $tab)
            } label: {
                tabLabel(L("Trip"), icon: "map-trifold", tab: .trip)
            }
            Tab(value: AppTab.check) {
                CheckView(tab: $tab, path: $checkPath)
            } label: {
                tabLabel(L("Check"), icon: "seal-check", tab: .check)
            }
        }
        .tint(Theme.accent)
        // No shrinking tab bar on scroll: it changed the page's bottom inset the moment you
        // started scrolling, which re-laid out all of Home and froze the first swipe.
        // Always one tap from home, or from telling Candor where home is.
        .homeAccessory(shown: !ask.isProfileShowing)
        .alert(L("You're new to the city"), isPresented: $router.showPrompt) {
            Button(L("Add my stay")) { router.showSetup = true }
            Button(L("Not now"), role: .cancel) {}
        } message: {
            Text(L("Tell Candor where you're staying and it can always show you the way back."))
        }
        .sheet(isPresented: $router.showSetup) {
            StaySetupSheet()
                .environment(router)
        }
        .fullScreenCover(isPresented: $router.showWayHome) {
            WayHomeView()
                .environment(router)
        }
        .sheet(isPresented: $ask.isOpen) {
            AgentView(inSheet: true)
                .presentationDragIndicator(.visible)
        }
        .environment(router)
        .environment(ask)
        // Until we know where the traveller is staying, ask on launch and whenever they come back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { router.askIfNeeded(app) }
        }
        .onAppear {
            // `-candor.tab trip` at launch opens a tab directly (screenshots and UI tests).
            switch UserDefaults.standard.string(forKey: "candor.tab") {
            case "trip": tab = .trip
            case "check": tab = .check
            case "agent": ask.open()
            case "profile": tab = .home; ask.openProfile()
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

private extension View {
    /// The "Way back home" bar above the tabs, hidden on pages that hide the tabs (Me).
    @ViewBuilder
    func homeAccessory(shown: Bool) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: shown) { HomeAccessory() }
        } else {
            tabViewBottomAccessory { HomeAccessory() }
        }
    }
}
