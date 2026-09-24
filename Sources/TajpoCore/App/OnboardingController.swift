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
        let size = NSSize(width: 880, height: 590)
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
        window.setFrameAutosaveName("TajpoOnboardingWindow")
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
    let contextTitle: String
    let contextDetail: String
    let symbol: String

    static let all: [SetupStep] = [
        SetupStep(
            id: 0,
            label: "Welcome",
            title: "Write better without leaving your app",
            detail: "Select text anywhere. Tajpo appears beside it, streams a rewrite, and lets you replace, copy, or undo.",
            contextTitle: "A private writing layer",
            contextDetail: "Select once. Stay in your flow.",
            symbol: "wand.and.stars"
        ),
        SetupStep(
            id: 1,
            label: "Accessibility",
            title: "Let Tajpo work in other apps",
            detail: "Accessibility lets Tajpo read the text you select and put the finished version back. It never reads your whole screen.",
            contextTitle: "Permission, with boundaries",
            contextDetail: "You choose what Tajpo touches.",
            symbol: "lock.shield"
        ),
        SetupStep(
            id: 2,
            label: "Shortcut",
            title: "Choose how you invoke Tajpo",
            detail: "Press this shortcut in any app to open the rewrite panel. You can change it later in Settings.",
            contextTitle: "One shortcut, everywhere",
            contextDetail: "Keep your hands on the keyboard.",
            symbol: "keyboard"
        ),
        SetupStep(
            id: 3,
            label: "Your model",
            title: "Choose how Tajpo writes",
            detail: "Start with the on-device demo, or connect a provider when you are ready for a stronger model.",
            contextTitle: "Your text, your choice",
            contextDetail: "Demo mode works without a key or network.",
            symbol: "cpu"
        ),
        SetupStep(
            id: 4,
            label: "Try Tajpo",
            title: "Try one small edit",
            detail: "Practice here first. When you are ready, select text in another app and press your shortcut.",
            contextTitle: "Ready when you are",
            contextDetail: "A safe place to try the workflow.",
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
        SetupStep.all[min(max(step, 0), SetupStep.all.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ProgressView(value: Double(step + 1), total: Double(SetupStep.all.count))
                .progressViewStyle(.linear)
                .tint(TajpoTheme.copper)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .accessibilityLabel("Setup progress, step \(step + 1) of \(SetupStep.all.count)")

            HStack(spacing: 0) {
                SetupContextPanel(
                    step: step,
                    model: model,
                    settings: settings,
                    practiceText: testText
                )
                .frame(width: 300)

                Divider()

                stepPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(TajpoTheme.copper)
        .onAppear { model.refreshSystemState() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Set up Tajpo")
                    .font(.headline.weight(.semibold))
                Text("A private writing assistant for your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 1) {
                Text(currentStep.label)
                    .font(.subheadline.weight(.semibold))
                Text("Step \(step + 1) of \(SetupStep.all.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 7) {
                        Image(systemName: currentStep.symbol)
                            .foregroundStyle(TajpoTheme.copper)
                        Text("STEP \(step + 1)  ·  \(currentStep.label.uppercased())")
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(TajpoTheme.copper)
                    }
                    Text(currentStep.title)
                        .font(.system(size: 28, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(currentStep.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    stepContent
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            welcomeContent
        case 1:
            accessibilityContent
        case 2:
            shortcutContent
        case 3:
            modelContent
        default:
            practiceContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            setupFeature(
                symbol: "macwindow.on.rectangle",
                title: "Works where you write",
                detail: "Mail, Notes, Slack, your browser, and most other apps."
            )
            setupFeature(
                symbol: "eye",
                title: "You approve every change",
                detail: "See the result first. Nothing changes until you choose Replace."
            )
            setupFeature(
                symbol: "lock.shield",
                title: "Private by design",
                detail: "Demo mode stays on this Mac. No account and no tracking."
            )
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
                                .foregroundStyle(.primary)
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
            Button(step == SetupStep.all.count - 1 ? "Finish" : step == 0 ? "Get Started" : "Continue") {
                if step == SetupStep.all.count - 1 {
                    finish()
                } else {
                    move(to: step + 1)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(TajpoTheme.copper)
            .disabled(!canContinue)
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
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
            withAnimation(.easeInOut(duration: 0.22)) { step = target }
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

    private func setupFeature(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TajpoTheme.copper)
                .frame(width: 28, height: 28)
                .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

private struct SetupContextPanel: View {
    let step: Int
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let practiceText: String

    private var currentStep: SetupStep {
        SetupStep.all[min(max(step, 0), SetupStep.all.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tajpo")
                        .font(.headline.weight(.semibold))
                    Text("Writing, without the tab switch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(AppVersion.string)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 28)

            Text(currentStep.contextTitle)
                .font(.system(size: 23, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(currentStep.contextDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            preview
                .padding(.top, 20)

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                Image(systemName: contextNoteSymbol)
                    .foregroundStyle(TajpoTheme.copper)
                Text(contextNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TajpoTheme.copper)
                .frame(width: 3)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch step {
        case 0:
            RewritePreviewCard()
        case 1:
            PermissionPreview(isTrusted: model.isAccessibilityTrusted)
        case 2:
            ShortcutPreview(shortcut: model.settings.hotkeyLabel)
        case 3:
            ModelPreview(provider: settings.provider)
        default:
            PracticePreview(text: practiceText)
        }
    }

    private var contextNote: String {
        switch step {
        case 0: "No account required"
        case 1: "Only selected text is read"
        case 2: "Your shortcut works anywhere"
        case 3: "Demo mode needs no key"
        default: "Nothing is replaced without approval"
        }
    }

    private var contextNoteSymbol: String {
        switch step {
        case 0: "person.crop.circle.badge.checkmark"
        case 1: "text.cursor"
        case 2: "keyboard"
        case 3: "lock.shield"
        default: "checkmark.shield"
        }
    }
}

private struct RewritePreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Tajpo preview", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TajpoTheme.copper)
                Spacer()
                Text("Correct")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("Their going to the libary tomorow.")
                .font(.body)
                .foregroundStyle(.secondary)
                .strikethrough(true, color: .red.opacity(0.65))
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TajpoTheme.copper)
                Text("They're going to the library tomorrow.")
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct PermissionPreview: View {
    let isTrusted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tajpo")
                        .font(.subheadline.weight(.semibold))
                    Text("Accessibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Capsule()
                        .fill(isTrusted ? TajpoTheme.sage : Color.primary.opacity(0.18))
                        .frame(width: 34, height: 20)
                        .overlay(alignment: isTrusted ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                                .padding(2)
                        }
                    Text(isTrusted ? "On" : "Off")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isTrusted ? TajpoTheme.sage : .secondary)
                }
            }
            Text(isTrusted ? "Tajpo can read and replace selected text." : "Tajpo is waiting for your permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }
}

private struct ShortcutPreview: View {
    let shortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press this anywhere")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(shortcut)
                .font(.system(size: 25, weight: .semibold, design: .monospaced))
                .foregroundStyle(TajpoTheme.copper)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Label("The panel opens next to your selection.", systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }
}

private struct ModelPreview: View {
    let provider: LLMProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: provider == .demo ? "sparkles" : provider == .openAI ? "key" : "server.rack")
                    .font(.title3)
                    .foregroundStyle(TajpoTheme.copper)
                    .frame(width: 30, height: 30)
                    .background(TajpoTheme.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.title)
                        .font(.subheadline.weight(.semibold))
                    Text(provider == .demo ? "Runs on this Mac" : "Ready when you are")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Label(provider == .demo ? "No key or network required" : "You can change this later", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }
}

private struct PracticePreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TajpoTheme.copper)
            Text(text)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Select it, then press your shortcut", systemImage: "cursorarrow.rays")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
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
