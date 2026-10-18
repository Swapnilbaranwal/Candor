import SwiftUI

/// The tools a traveller reaches for in a hurry, as story-style circles at the top of Home:
/// one tap opens the Interpreter, the converter or Emergency over Home, without going to the Check tab.
struct QuickToolsRow: View {
    private enum QuickTool: String, Identifiable, CaseIterable {
        case sos, interpreter, converter
        var id: String { rawValue }

        /// English keys, shown through `L(…)`.
        var title: String {
            switch self {
            case .sos: "SOS"
            case .interpreter: "Interpreter"
            case .converter: "Converter"
            }
        }

        var icon: String {
            switch self {
            case .sos: "sos"
            case .interpreter: "bubble.left.and.text.bubble.right.fill"
            case .converter: "dollarsign.arrow.circlepath"
            }
        }

        var colors: [Color] {
            switch self {
            case .sos: [.red, Theme.coral, .red]
            case .interpreter: [Theme.sky, Theme.teal, Theme.sky]
            case .converter: [Theme.mint, Theme.saffron, Theme.mint]
            }
        }
    }

    @State private var open: QuickTool?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(QuickTool.allCases) { tool in
                Button { open = tool } label: { bubble(tool) }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(L(tool.title))
                    .accessibilityIdentifier("quick-\(tool.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .sheet(item: $open) { tool in
            NavigationStack {
                Group {
                    switch tool {
                    case .sos: EmergencyView()
                    case .interpreter: InterpreterView()
                    case .converter: ConverterView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { open = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("Close"))
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
    }

    /// A gradient ring around a filled circle, with the name underneath, like a story.
    private func bubble(_ tool: QuickTool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: tool.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(LinearGradient(colors: Array(tool.colors.prefix(2)), startPoint: .topLeading,
                                           endPoint: .bottomTrailing), in: .circle)
                .padding(3)
                .background(Theme.surface, in: .circle)
                .padding(3)
                .background(AngularGradient(colors: tool.colors, center: .center), in: .circle)
                .shadow(color: Theme.shadow, radius: 6, y: 3)
            Text(L(tool.title))
                .font(.candor(.caption1, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
