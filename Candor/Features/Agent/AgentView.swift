import SwiftUI
import PhotosUI

/// Chat with the Candor agent. Each reply shows the tools it used, live.
struct AgentView: View {
    @Environment(AppState.self) private var app
    @Environment(CandorAgent.self) private var agent
    @State private var input = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var attachment: UIImage?
    @FocusState private var inputFocused: Bool

    private struct Starter: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private let starters: [Starter] = [
        Starter(icon: "car.fill", text: "Auto to Red Fort, he's asking ₹250"),
        Starter(icon: "tag.fill", text: "Is ₹60 fair for a samosa?"),
        Starter(icon: "shield.lefthalf.filled", text: "Someone says the station office is closed and I must book elsewhere"),
        Starter(icon: "map.fill", text: "Plan my day around heritage and street food"),
        Starter(icon: "dollarsign.arrow.circlepath", text: "How much is ₹1500 in my currency?")
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if agent.messages.isEmpty {
                            emptyState
                        }
                        ForEach(agent.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.messages.last?.steps.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: agent.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: agent.isWorking) { _, _ in scrollToBottom(proxy) }
            }
            .background(LiquidBackground())
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Candor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(app.hasGemini ? Theme.mint : Theme.saffron)
                            .frame(width: 8, height: 8)
                        Text(app.hasGemini ? "Gemini" : "Offline")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 6)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") { agent.clear() }
                        .disabled(agent.messages.isEmpty || agent.isWorking)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attachment = UIImage(data: data)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            AgentOrb(size: 84, isActive: false)
                .padding(.top, 30)
            VStack(spacing: 6) {
                Text("Hi \(app.persona.firstName), I'm Candor")
                    .font(.title2.weight(.bold))
                Text("I check fares, prices and situations for you, using real fare charts and price references. You'll see every step I take.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(starters) { starter in
                    Button {
                        Task { await agent.send(starter.text) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: starter.icon)
                                .foregroundStyle(Theme.saffron)
                                .frame(width: 24)
                            Text(starter.text)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(14)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 20)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let attachment {
                HStack {
                    Image(uiImage: attachment)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 14))
                    Text("Photo attached").font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        self.attachment = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)

                    TextField("Ask about a price, ride or situation…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                        .onSubmit(send)

                    Button(action: send) {
                        Image(systemName: agent.isWorking ? "ellipsis" : "arrow.up")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular.tint(canSend ? Theme.saffron : Color.gray.opacity(0.5)).interactive(), in: .circle)
                            .symbolEffect(.variableColor.iterative, isActive: agent.isWorking)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.smooth, value: attachment != nil)
    }

    private var canSend: Bool {
        !agent.isWorking && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil)
    }

    private func send() {
        guard canSend else { return }
        let text = input
        let image = attachment
        input = ""
        attachment = nil
        inputFocused = false
        Task { await agent.send(text, image: image) }
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .agent: agentBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 50)
            VStack(alignment: .trailing, spacing: 8) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 180, height: 180)
                        .clipShape(.rect(cornerRadius: 20))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .glassEffect(.regular.tint(Theme.saffron), in: .rect(cornerRadius: 22))
                }
            }
        }
    }

    private var agentBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentOrb(size: 30, isActive: message.isWorking)
            VStack(alignment: .leading, spacing: 12) {
                if !message.steps.isEmpty {
                    AgentTrailView(steps: message.steps, isWorking: message.isWorking)
                }
                if let verdict = message.verdict {
                    VerdictCardView(verdict: verdict)
                }
                if !message.text.isEmpty {
                    MarkdownText(text: message.text)
                } else if message.isWorking && message.steps.isEmpty {
                    Text("Thinking…").foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Spacer(minLength: 0)
        }
    }
}
