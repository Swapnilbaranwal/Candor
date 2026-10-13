import SwiftUI
import PhotosUI

/// Camera-first price check: photo + optional asked price → agent run → verdict.
struct ScanView: View {
    /// True when pushed inside another tab's navigation (Check), so it doesn't bring its own.
    var embedded = false

    @Environment(AppState.self) private var app
    @Environment(CandorAgent.self) private var agent
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var askedText = ""
    @State private var note = ""
    @State private var steps: [AgentStep] = []
    @State private var result: AgentResult?
    @State private var isRunning = false
    @State private var showCamera = false
    @FocusState private var focused: Bool

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var canCheck: Bool { (image != nil || !note.trimmingCharacters(in: .whitespaces).isEmpty) && !isRunning }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                viewfinder
                sourceButtons
                inputs
                checkButton
                if !steps.isEmpty {
                    AgentTrailView(steps: steps, isWorking: isRunning).card(cornerRadius: 16)
                }
                if let result {
                    if let verdict = result.verdict {
                        VerdictCardView(verdict: verdict)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    if !result.text.isEmpty {
                        MarkdownText(text: result.text).card(cornerRadius: 16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .animation(.smooth, value: steps)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(L("Price check"))
        .toolbar {
            if image != nil || result != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Reset"), systemImage: "arrow.counterclockwise") { resetAll() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { focused = false }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    withAnimation(.smooth) { image = picked }
                    clearResult()
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $image).ignoresSafeArea()
        }
    }

    private var viewfinder: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 280)
                    .clipShape(.rect(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Theme.accent)
                    Text(L("Photograph a price tag, menu or bill"))
                        .font(.candor(.headline, .semibold))
                    Text(L("Candor reads it, finds the fair price and tells you if it's fair, in your language."))
                        .font(.candor(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
            }
            if isRunning {
                ScanLine().clipShape(.rect(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .padding(.top, 8)
    }

    private var sourceButtons: some View {
        Group {
            HStack(spacing: 10) {
                if cameraAvailable {
                    Button { showCamera = true } label: {
                        Label(L("Camera"), systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(L("Photos"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.candor(.subheadline, .semibold))
            .controlSize(.large)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "indianrupeesign").foregroundStyle(Theme.saffron).frame(width: 24)
                TextField(L("What are they asking? (optional)"), text: $askedText)
                    .keyboardType(.decimalPad)
                    .focused($focused)
            }
            Divider()
            HStack(alignment: .top) {
                Image(systemName: "text.bubble").foregroundStyle(Theme.accent).frame(width: 24)
                TextField(L("Add context, e.g. \"2 chai and a samosa\""), text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focused)
            }
            if let asked = Double(askedText), asked > 0 {
                Text("≈ \(app.homeAmount(asked))")
                    .font(.candor(.caption1))
                    .foregroundStyle(.secondary)
            }
        }
        .card(cornerRadius: 16)
    }

    private var checkButton: some View {
        Button(action: check) {
            HStack(spacing: 8) {
                if isRunning { ProgressView().tint(.white) } else { Image(systemName: "checkmark.shield") }
                Text(isRunning ? L("Checking…") : L("Check fair price"))
            }
            .font(.candor(.headline, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(!canCheck)
    }

    private func check() {
        focused = false
        clearResult()
        isRunning = true
        var prompt = "Check whether this price is fair for a tourist in Delhi."
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if !trimmedNote.isEmpty { prompt += " Context: \(trimmedNote)." }
        if let asked = Double(askedText), asked > 0 { prompt += " Asked price: ₹\(asked.formatted())." }
        let photo = image

        Task {
            let output = await agent.run(prompt: prompt, image: photo) { step in
                withAnimation(.snappy) { upsertStep(step, in: &steps) }
            }
            withAnimation(.smooth) {
                result = output
                isRunning = false
            }
            if let verdict = output.verdict, verdict.askedINR != nil {
                app.record(PriceCheckRecord(verdict: verdict, kind: .scan))
            }
        }
    }

    private func clearResult() {
        steps = []
        result = nil
    }

    private func resetAll() {
        clearResult()
        image = nil
        pickerItem = nil
        askedText = ""
        note = ""
    }
}

/// Animated scanning sweep shown while the agent reads the photo.
private struct ScanLine: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.saffron.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .offset(y: down ? geo.size.height - 35 : -35)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { down = true }
                }
        }
        .allowsHitTesting(false)
    }
}

/// UIKit camera wrapper.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
