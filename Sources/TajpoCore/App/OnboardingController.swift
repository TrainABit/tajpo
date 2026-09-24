import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(model: model, finish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "completedOnboarding")
            self?.window?.close()
            self?.window = nil
        })
        let size = NSSize(width: 760, height: 540)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Tajpo"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = false
        window.minSize = size
        window.setFrameAutosaveName("TajpoOnboardingWindowV2")
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
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
            title: "A better sentence, without leaving your app",
            detail: "Select text, press your shortcut, and review the result before anything changes.",
            symbol: "wand.and.stars"
        ),
        SetupStep(
            id: 1,
            label: "Access",
            title: "Let Tajpo work in other apps",
            detail: "Accessibility lets Tajpo read the text you select and put the finished version back.",
            symbol: "lock.shield"
        ),
        SetupStep(
            id: 2,
            label: "Shortcut",
            title: "Choose how you invoke Tajpo",
            detail: "Use one shortcut in any app. You can change it later in Settings.",
            symbol: "keyboard"
        ),
        SetupStep(
            id: 3,
            label: "Model",
            title: "Choose how Tajpo writes",
            detail: "Start with the on-device demo, or connect a provider when you want a stronger model.",
            symbol: "cpu"
        ),
        SetupStep(
            id: 4,
            label: "Try it",
            title: "Try one small edit",
            detail: "Practice here first. When you are ready, select text in another app and press your shortcut.",
            symbol: "text.cursor"
        )
    ]
}

@MainActor
private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
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

    private var currentStep: SetupStep {
        SetupStep.all[step]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            stepRail
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(currentStep.title)
                            .font(.system(size: 26, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(currentStep.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        stepContent
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    .frame(minHeight: max(proxy.size.height - 18, 0), alignment: .center)
                }
                .scrollIndicators(.automatic)
            }
            .id(step)
            .transition(.opacity)
            footer
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(TajpoTheme.copper)
        .onAppear { model.refreshSystemState() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tajpo")
                    .font(.headline.weight(.semibold))
                Text("Setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("PRIVATE WRITING ASSISTANT")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var stepRail: some View {
        HStack(spacing: 0) {
            ForEach(SetupStep.all) { item in
                let current = item.id == step
                let complete = item.id < step
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(current ? TajpoTheme.copper : complete ? TajpoTheme.copper.opacity(0.16) : Color.primary.opacity(0.08))
                        if complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(TajpoTheme.copper)
                        } else {
                            Text("\(item.id + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(current ? .white : .secondary)
                        }
                    }
                    .frame(width: 21, height: 21)
                    Text(item.label)
                        .font(.caption.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? .primary : .secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(item.id + 1), \(item.label)\(complete ? ", complete" : "")\(current ? ", current" : "")")

                if item.id < SetupStep.all.count - 1 {
                    Rectangle()
                        .fill(item.id < step ? TajpoTheme.copper.opacity(0.45) : Color.primary.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 9)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeContent
        case 1: accessibilityContent
        case 2: shortcutContent
        case 3: modelContent
        default: practiceContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            DemoPanelPreview()
            HStack(alignment: .top, spacing: 12) {
                welcomeFeature(
                    symbol: "macwindow.on.rectangle",
                    title: "Works where you write",
                    detail: "Mail, Notes, Slack, your browser, and more."
                )
                welcomeFeature(
                    symbol: "eye",
                    title: "You approve every change",
                    detail: "Review first. Replace only when you say so."
                )
                welcomeFeature(
                    symbol: "lock.shield",
                    title: "Private by design",
                    detail: "Demo mode stays on this Mac."
                )
            }
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.isAccessibilityTrusted ? "checkmark.shield.fill" : "lock.shield")
                    .font(.title2)
                    .foregroundStyle(model.isAccessibilityTrusted ? TajpoTheme.sage : TajpoTheme.copper)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isAccessibilityTrusted ? "Accessibility is on" : "Accessibility is needed")
                        .font(.headline)
                    Text(model.isAccessibilityTrusted ? "Tajpo can work in other apps." : "Tajpo waits until you allow it in System Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .setupSurface()

            Text("Tajpo only reads the text you select after you press the shortcut. It does not record your screen or send anything on its own.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.isAccessibilityTrusted {
                Button {
                    model.requestAccessibility()
                } label: {
                    Label("Open Accessibility Settings", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .tint(TajpoTheme.copper)
            }
        }
    }

    private var shortcutContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current shortcut")
                        .font(.headline)
                    Text("You can change this later in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.settings.hotkeyLabel)
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .setupSurface()

            Text("Press \(model.settings.hotkeyLabel) now. This is the same shortcut you will use in other apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            setupStatus(
                ok: model.hotkeyConfirmed,
                okText: "Shortcut received. You are ready to continue.",
                missingText: "Waiting for \(model.settings.hotkeyLabel)…"
            )
        }
    }

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerPicker
            providerFields

            if !keyMessage.isEmpty {
                Text(keyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            setupStatus(
                ok: settings.provider != .openAI || model.hasSavedAPIKey(),
                okText: settings.provider == .demo ? "Demo engine is ready." : "Provider is ready.",
                missingText: "Save a key or switch to the demo engine."
            )
        }
    }

    private var providerPicker: some View {
        VStack(spacing: 8) {
            ForEach(LLMProvider.allCases) { provider in
                Button {
                    settings.provider = provider
                    settings.applyProviderDefaults()
                    keyMessage = ""
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: providerSymbol(provider))
                            .font(.headline)
                            .foregroundStyle(settings.provider == provider ? TajpoTheme.copper : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.title)
                                .font(.subheadline.weight(.semibold))
                            Text(providerDescription(provider))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if settings.provider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TajpoTheme.copper)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        settings.provider == provider ? TajpoTheme.copper.opacity(0.12) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(settings.provider == provider ? TajpoTheme.copper.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.title)
                .accessibilityAddTraits(settings.provider == provider ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var providerFields: some View {
        switch settings.provider {
        case .demo:
            Label("Demo mode runs on this Mac. No key, network, or account is needed.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .setupSurface()
        case .openAI:
            VStack(alignment: .leading, spacing: 10) {
                SecureField("OpenAI API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenAI API key")
                HStack {
                    Button("Save in Keychain") { saveKey() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test connection") {
                        Task { keyMessage = await model.testConnection() }
                    }
                    Spacer()
                }
            }
            .setupSurface()
        case .localCompatible:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Local /v1 URL", text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Test connection") {
                        Task { keyMessage = await model.testConnection() }
                    }
                    Spacer()
                }
            }
            .setupSurface()
        }
    }

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $testText)
                .font(.body)
                .frame(height: 124)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .accessibilityLabel("Practice text")
            Text("When you are ready, select this text in another app and press \(model.settings.hotkeyLabel).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Nothing is replaced until you approve it.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button("Back") { move(to: step - 1) }
            }
            Spacer()
            if let skipTitle {
                Button(skipTitle) {
                    markSkip()
                    move(to: step + 1)
                }
                .buttonStyle(.link)
                .tint(TajpoTheme.copper)
            }
            Button {
                if step == SetupStep.all.count - 1 {
                    finish()
                } else {
                    move(to: step + 1)
                }
            } label: {
                Text(step == SetupStep.all.count - 1 ? "Finish" : step == 0 ? "Get Started" : "Continue")
                    .foregroundStyle(.white)
                    .frame(minWidth: 90)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(TajpoTheme.copper)
            .disabled(!canContinue)
        }
        .controlSize(.regular)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var skipTitle: String? {
        switch step {
        case 1 where !model.isAccessibilityTrusted: "Skip for now"
        case 2 where !model.hotkeyConfirmed: "Skip for now"
        case 3 where settings.provider == .openAI && !model.hasSavedAPIKey(): "Use demo instead"
        default: nil
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: model.isAccessibilityTrusted || skippedAccessibility
        case 2: model.hotkeyConfirmed || skippedShortcut
        case 3: settings.provider != .openAI || model.hasSavedAPIKey() || skippedKey
        default: true
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
            step = target
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step = target }
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

    private func welcomeFeature(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TajpoTheme.copper)
                .frame(width: 28, height: 28)
                .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupStatus(ok: Bool, okText: String, missingText: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? TajpoTheme.sage : Color.secondary)
                .frame(width: 7, height: 7)
            Text(ok ? okText : missingText)
                .font(.callout)
                .foregroundStyle(ok ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
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
        case .demo: "Try the workflow on this Mac"
        case .openAI: "Use an API key when you want a stronger model"
        case .localCompatible: "Connect Ollama, llama.cpp, or MLX"
        }
    }
}

private struct DemoPanelPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Tajpo", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
                Spacer()
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TajpoTheme.sage)
                Text("⌥⌘T")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            HStack(alignment: .top, spacing: 14) {
                previewColumn(
                    title: "Original",
                    text: "Their going to the libary tomorow.",
                    color: .secondary,
                    strikethrough: true
                )
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TajpoTheme.copper)
                    .padding(.top, 22)
                previewColumn(
                    title: "Rewrite",
                    text: "They're going to the library tomorrow.",
                    color: .primary,
                    strikethrough: false
                )
            }
            .padding(14)

            Divider()

            HStack(spacing: 6) {
                ForEach(["Correct", "Improve", "Shorten"], id: \.self) { action in
                    Text(action)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(action == "Correct" ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            action == "Correct" ? TajpoTheme.copper : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                Spacer()
                Text("Replace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
    }

    private func previewColumn(title: String, text: String, color: Color, strikethrough: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .foregroundStyle(color)
                .strikethrough(strikethrough, color: .red.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SetupSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

private extension View {
    func setupSurface() -> some View {
        modifier(SetupSurfaceModifier())
    }
}
