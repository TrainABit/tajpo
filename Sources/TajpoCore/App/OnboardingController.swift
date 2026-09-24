import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private var window: NSWindow?

    func show(model: AppModel) {
        NSApp.setActivationPolicy(.regular)
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(model: model, finish: { [weak self] in
            model.settings.onboardingStep = 0
            UserDefaults.standard.set(true, forKey: "completedOnboarding")
            self?.window?.close()
            self?.window = nil
        })
        let size = NSSize(width: 900, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tajpo"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = false
        window.minSize = size
        window.setFrameAutosaveName("TajpoFieldTestWindow")
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let closedWindow = notification.object as? NSWindow, closedWindow === window {
            window = nil
        }
    }
}

private struct SetupStep: Identifiable {
    let id: Int
    let label: String
    let title: String
    let detail: String
    let symbol: String

    static let all: [SetupStep] = [
        SetupStep(
            id: 0,
            label: "Welcome",
            title: "See the whole loop",
            detail: "Try the core moment before you connect anything.",
            symbol: "wand.and.stars"
        ),
        SetupStep(
            id: 1,
            label: "Access",
            title: "Give Tajpo a narrow lane",
            detail: "Accessibility lets Tajpo read only the text you select.",
            symbol: "lock.shield"
        ),
        SetupStep(
            id: 2,
            label: "Shortcut",
            title: "Make it one keystroke",
            detail: "Choose the shortcut that will open Tajpo anywhere.",
            symbol: "keyboard"
        ),
        SetupStep(
            id: 3,
            label: "Model",
            title: "Choose your engine",
            detail: "Start local, or connect a stronger model when you want one.",
            symbol: "cpu"
        ),
        SetupStep(
            id: 4,
            label: "Try it",
            title: "Make the first edit yours",
            detail: "Use the sample, then take the same flow into any app.",
            symbol: "text.cursor"
        )
    ]
}

private enum DemoAction: String, CaseIterable, Identifiable {
    case correct
    case shorter
    case formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correct: "Correct"
        case .shorter: "Shorter"
        case .formal: "Formal"
        }
    }

    var symbol: String {
        switch self {
        case .correct: "checkmark"
        case .shorter: "scissors"
        case .formal: "textformat"
        }
    }

    var result: String {
        switch self {
        case .correct: "They're going to the library tomorrow."
        case .shorter: "Library tomorrow."
        case .formal: "I will visit the library tomorrow."
        }
    }
}

@MainActor
private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var key = ""
    @State private var keyMessage = ""
    @State private var skippedAccessibility = false
    @State private var skippedShortcut = false
    @State private var skippedKey = false
    @State private var testText = "tajpo make this sentance better so i can really just send it."

    init(model: AppModel, finish: @escaping () -> Void) {
        self.model = model
        settings = model.settings
        self.finish = finish
    }

    private var step: Int {
        min(max(settings.onboardingStep, 0), SetupStep.all.count - 1)
    }

    private func setStep(_ value: Int) {
        settings.onboardingStep = min(max(value, 0), SetupStep.all.count - 1)
    }

    private var currentStep: SetupStep {
        SetupStep.all[step]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                LiveRewriteStage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                setupRail
                    .frame(width: 300)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(TajpoTheme.copper)
        .onAppear { model.refreshSystemState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemState()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tajpo")
                    .font(.headline.weight(.semibold))
                Text("Writing layer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("LOCAL DEMO")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(TajpoTheme.sage)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TajpoTheme.sage.opacity(0.12), in: Capsule())
            Text("SETUP \(step + 1) / \(SetupStep.all.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var setupRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: currentStep.symbol)
                            .foregroundStyle(TajpoTheme.copper)
                        Text(currentStep.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(TajpoTheme.copper)
                    }
                    Text(currentStep.title)
                        .font(.system(size: 24, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(currentStep.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    railContent
                }
                .padding(24)
            }
            .scrollIndicators(.automatic)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(SetupStep.all) { item in
                        Circle()
                            .fill(item.id == step ? TajpoTheme.copper : item.id < step ? TajpoTheme.copper.opacity(0.35) : Color.primary.opacity(0.14))
                            .frame(width: item.id == step ? 8 : 6, height: item.id == step ? 8 : 6)
                    }
                    Spacer()
                    if step > 0 {
                        Button("Back") { move(to: step - 1) }
                            .buttonStyle(.link)
                    }
                }
                if let skipTitle {
                    Button(skipTitle) {
                        markSkip()
                        move(to: step + 1)
                    }
                    .buttonStyle(.link)
                    .tint(TajpoTheme.copper)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Button {
                    if step == SetupStep.all.count - 1 {
                        finish()
                    } else {
                        move(to: step + 1)
                    }
                } label: {
                    Text(step == SetupStep.all.count - 1 ? "Finish setup" : step == 0 ? "Continue" : "Next")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(TajpoTheme.copper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(canContinue ? 1 : 0.45)
                .disabled(!canContinue)
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.34))
    }

    @ViewBuilder
    private var railContent: some View {
        switch step {
        case 0: welcomeRail
        case 1: accessibilityRail
        case 2: shortcutRail
        case 3: modelRail
        default: practiceRail
        }
    }

    private var welcomeRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            proofRow("One shortcut", "opens the panel beside your selection", symbol: "bolt.fill")
            proofRow("One review", "shows the exact rewrite before anything changes", symbol: "eye.fill")
            proofRow("One boundary", "keeps your text and your choice in your hands", symbol: "hand.raised.fill")
        }
    }

    private var accessibilityRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.isAccessibilityTrusted ? "checkmark.shield.fill" : "lock.shield")
                    .font(.title3)
                    .foregroundStyle(model.isAccessibilityTrusted ? TajpoTheme.sage : TajpoTheme.copper)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isAccessibilityTrusted ? "Permission granted" : "Permission needed")
                        .font(.headline)
                    Text(model.isAccessibilityTrusted ? "Tajpo can work in other apps." : "Tajpo is waiting for your permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .setupSurface()
            if !model.isAccessibilityTrusted {
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS keeps this switch off until you turn it on. Turn on Tajpo in System Settings, then return here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings") { model.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                        .tint(TajpoTheme.copper)
                    Button {
                        model.refreshSystemState()
                    } label: {
                        Label("I turned it on — check again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.link)
                    .tint(TajpoTheme.copper)
                }
            }
        }
    }

    private var shortcutRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your shortcut")
                        .font(.headline)
                    Text("Change it later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.settings.hotkeyLabel)
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
            }
            .setupSurface()
            setupStatus(ok: model.hotkeyConfirmed, okText: "Shortcut received.", missingText: "Waiting for \(model.settings.hotkeyLabel)…")
        }
    }

    private var modelRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(LLMProvider.allCases) { provider in
                Button {
                    settings.provider = provider
                    settings.applyProviderDefaults()
                    keyMessage = ""
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: providerSymbol(provider))
                            .foregroundStyle(settings.provider == provider ? TajpoTheme.copper : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.title)
                                .font(.subheadline.weight(.semibold))
                            Text(providerDescription(provider))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if settings.provider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TajpoTheme.copper)
                        }
                    }
                    .padding(10)
                    .background(settings.provider == provider ? TajpoTheme.copper.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if settings.provider == .openAI {
                SecureField("OpenAI API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save key") { saveKey() }
                    Button("Test") { Task { keyMessage = await model.testConnection() } }
                }
            } else if settings.provider == .localCompatible {
                TextField("Local /v1 URL", text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)
                Button("Test connection") { Task { keyMessage = await model.testConnection() } }
            }
            if !keyMessage.isEmpty {
                Text(keyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var practiceRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice text")
                .font(.headline)
            TextEditor(text: $testText)
                .font(.callout)
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            Text("Select this in another app when you are ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func proofRow(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TajpoTheme.copper)
                .frame(width: 25, height: 25)
                .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setupStatus(ok: Bool, okText: String, missingText: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(ok ? TajpoTheme.sage : .secondary).frame(width: 7, height: 7)
            Text(ok ? okText : missingText)
                .font(.caption)
                .foregroundStyle(ok ? .primary : .secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canContinue: Bool {
        switch step {
        case 1: model.isAccessibilityTrusted || skippedAccessibility
        case 2: model.hotkeyConfirmed || skippedShortcut
        case 3: settings.provider != .openAI || model.hasSavedAPIKey() || skippedKey
        default: true
        }
    }

    private var skipTitle: String? {
        switch step {
        case 1 where !model.isAccessibilityTrusted: "Skip for now"
        case 2 where !model.hotkeyConfirmed: "Skip for now"
        case 3 where settings.provider == .openAI && !model.hasSavedAPIKey(): "Use demo instead"
        default: nil
        }
    }

    private func markSkip() {
        switch step {
        case 1: skippedAccessibility = true
        case 2: skippedShortcut = true
        case 3:
            skippedKey = true
            settings.provider = .demo
            settings.applyProviderDefaults()
        default: break
        }
    }

    private func move(to newStep: Int) {
        let target = min(max(newStep, 0), SetupStep.all.count - 1)
        if reduceMotion {
            setStep(target)
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { setStep(target) }
        }
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(key)
            key = ""
            keyMessage = "Saved securely in Keychain."
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func providerSymbol(_ provider: LLMProvider) -> String {
        switch provider {
        case .demo: "sparkles"
        case .openAI: "key"
        case .localCompatible: "server.rack"
        }
    }

    private func providerDescription(_ provider: LLMProvider) -> String {
        switch provider {
        case .demo: "Runs on this Mac"
        case .openAI: "Stronger model, API key"
        case .localCompatible: "Ollama, llama.cpp, MLX"
        }
    }
}

@MainActor
private struct LiveRewriteStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var action: DemoAction = .correct
    @State private var didReplace = false
    private let timer = Timer.publish(every: 4.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("LIVE PRODUCT MOMENT", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(TajpoTheme.sage)
                Spacer()
                Text("Nothing is sent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Spacer(minLength: 4)

            documentCard
                .padding(.horizontal, 24)

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(TajpoTheme.sage)
                Text("Private by default")
                    .font(.caption.weight(.medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("You approve every change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color.primary.opacity(0.035), Color.primary.opacity(0.012)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                StageGrid()
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            let currentIndex = DemoAction.allCases.firstIndex(of: action) ?? 0
            let next = DemoAction.allCases[(currentIndex + 1) % DemoAction.allCases.count]
            withAnimation(.easeInOut(duration: 0.35)) {
                action = next
                didReplace = false
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.75)).frame(width: 9, height: 9)
                Circle().fill(Color.yellow.opacity(0.75)).frame(width: 9, height: 9)
                Circle().fill(Color.green.opacity(0.75)).frame(width: 9, height: 9)
                Text("Draft — Untitled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer()
                Text("Tajpo can see this selection")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Their going to the ")
                    Text("libary")
                        .foregroundStyle(TajpoTheme.terracotta)
                        .underline(true, color: TajpoTheme.terracotta)
                    Text(" tomorow.")
                }
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                HStack(spacing: 8) {
                    Image(systemName: "selection.pin.in.out")
                        .foregroundStyle(TajpoTheme.copper)
                    Text("Selected text only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 170, alignment: .top)

            commandBar
                .padding(18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tajpo", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
                Spacer()
                Label(didReplace ? "Ready to use" : "Preview", systemImage: didReplace ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(didReplace ? TajpoTheme.sage : .secondary)
            }
            HStack(spacing: 6) {
                ForEach(DemoAction.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            action = item
                            didReplace = false
                        }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(action == item ? .white : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(action == item ? TajpoTheme.copper : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { didReplace = true }
                } label: {
                    Label(didReplace ? "Ready" : "Replace", systemImage: didReplace ? "checkmark" : "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(TajpoTheme.copper, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                Text("REWRITE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                    .frame(width: 58, alignment: .leading)
                Text(action.result)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TajpoTheme.copper.opacity(0.22), lineWidth: 1))
    }
}

private struct StageGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.primary.opacity(0.035)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct SetupSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.52), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

private extension View {
    func setupSurface() -> some View {
        modifier(SetupSurfaceModifier())
    }
}
