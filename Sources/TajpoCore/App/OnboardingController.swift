import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?

    func show(model: AppModel) {
        let view = OnboardingView(model: model, finish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "completedOnboarding")
            self?.window?.close()
            self?.window = nil
        })
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Tajpo"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    let finish: () -> Void

    init(model: AppModel, finish: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.finish = finish
    }
    @State private var step = 0
    @State private var key = ""
    @State private var keyMessage = ""
    @State private var skippedAccessibility = false
    @State private var skippedShortcut = false
    @State private var skippedKey = false
    @State private var testText = "tajpo make this sentance better so i can really just send it."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                ForEach(0..<titles.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? TajpoTheme.copper : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            Text(titles[step])
                .font(.largeTitle.bold())
            Group {
                switch step {
                case 0:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select text anywhere. Tajpo appears beside it, streams a rewrite, and lets you replace, copy, or undo.")
                        Text("It starts with an on-device demo so you can try it without an API key. Switch to OpenAI or a local server when you want a stronger model.")
                            .foregroundStyle(.secondary)
                    }
                case 1:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tajpo needs Accessibility access only to read and replace text you select.")
                        Button("Request access") { model.requestAccessibility() }
                            .buttonStyle(.borderedProminent)
                            .tint(TajpoTheme.copper)
                        statusLine(
                            ok: model.isAccessibilityTrusted,
                            okText: "Accessibility is granted.",
                            missing: "Accessibility is not granted yet."
                        )
                    }
                case 2:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Press \(model.settings.hotkeyLabel) now. This is the same shortcut you will use in other apps.")
                        statusLine(
                            ok: model.hotkeyConfirmed,
                            okText: "Shortcut received.",
                            missing: "Waiting for \(model.settings.hotkeyLabel)…"
                        )
                    }
                case 3:
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Provider", selection: $settings.provider) {
                            ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                        }
                        .onChange(of: settings.provider) { _, _ in
                            settings.applyProviderDefaults()
                        }
                        if settings.provider == .openAI {
                            SecureField("OpenAI API key", text: $key)
                            HStack {
                                Button("Save securely in Keychain") { saveKey() }
                                Button("Test connection") {
                                    Task { keyMessage = await model.testConnection() }
                                }
                            }
                        } else if settings.provider == .localCompatible {
                            TextField("Local /v1 URL", text: $settings.baseURL)
                            Button("Test connection") {
                                Task { keyMessage = await model.testConnection() }
                            }
                        } else {
                            Text("Demo mode stays on this Mac. You can add a key later in Settings.")
                                .foregroundStyle(.secondary)
                        }
                        if !keyMessage.isEmpty {
                            Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        statusLine(
                            ok: settings.provider != .openAI || model.hasSavedAPIKey(),
                            okText: settings.provider == .demo ? "Demo engine is ready." : "Provider is ready.",
                            missing: "Save a key or switch to the demo engine."
                        )
                    }
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $testText)
                            .font(.body)
                            .frame(height: 110)
                            .padding(6)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.quaternary))
                            .accessibilityLabel("Practice text")
                        Text("Select this text after setup and press \(model.settings.hotkeyLabel).")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                if canSkip {
                    Button("Skip") { markSkip(); step += 1 }
                }
                Spacer()
                Button(step == 4 ? "Finish" : "Continue") {
                    if step == 4 { finish() } else { step += 1 }
                }
                .disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(TajpoTheme.copper)
            }
        }
        .padding(28)
        .frame(width: 620, height: 500)
        .onAppear { model.refreshSystemState() }
    }

    private var titles: [String] {
        ["Write better without leaving your app", "Accessibility", "Your shortcut", "Your model", "Try Tajpo"]
    }

    private var canSkip: Bool {
        (step == 1 && !model.isAccessibilityTrusted)
            || (step == 2 && !model.hotkeyConfirmed)
            || (step == 3 && settings.provider == .openAI && !model.hasSavedAPIKey())
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
        case 3: skippedKey = true
        default: break
        }
    }

    private func statusLine(ok: Bool, okText: String, missing: String) -> some View {
        Text(ok ? okText : missing)
            .font(.caption)
            .foregroundStyle(ok ? TajpoTheme.sage : Color.secondary)
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(key)
            key = ""
            keyMessage = "Saved in Keychain."
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}
