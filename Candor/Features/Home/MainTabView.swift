import SwiftUI

enum AppTab: Hashable {
    case home, explore, scan, agent, profile
}

struct MainTabView: View {
    @Environment(CandorAgent.self) private var agent
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab(L("Home"), systemImage: "house.fill", value: AppTab.home) {
                HomeView(tab: $tab)
            }
            Tab(L("Explore"), systemImage: "map.fill", value: AppTab.explore) {
                ExploreView(tab: $tab)
            }
            Tab(L("Scan"), systemImage: "camera.viewfinder", value: AppTab.scan) {
                ScanView()
            }
            Tab(L("Agent"), systemImage: "sparkles", value: AppTab.agent) {
                AgentView()
            }
            Tab(L("Me"), systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tint(Theme.saffron)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            AgentAccessory(isOnAgentTab: tab == .agent) {
                tab = .agent
            }
        }
    }
}

/// Persistent glass bar above the tab bar: the agent is always one tap away.
struct AgentAccessory: View {
    @Environment(CandorAgent.self) private var agent
    @Environment(AppState.self) private var app
    let isOnAgentTab: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, isActive: agent.isWorking)
                    .foregroundStyle(Theme.brandGradient)
                Text(statusText)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if agent.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: app.hasGemini ? "bolt.fill" : "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if agent.isWorking { return L("Candor is working on it…") }
        if isOnAgentTab {
            return app.hasGemini ? L("Gemini agent · %@ tools", agent.toolCount) : L("Offline agent · %@ tools", agent.toolCount)
        }
        return L("Ask Candor anything…")
    }
}
