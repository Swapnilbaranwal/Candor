import SwiftUI

enum AppTab: Hashable {
    case home, trip, check, agent, profile
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var tab: AppTab = .home
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
        .tint(Theme.saffron)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear {
            if let start = app.startTab {
                tab = start
                app.startTab = nil
            }
        }
    }
}
