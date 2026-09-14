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
            contentRect: CGRect(x: 0, y: 0, width: 580, height: 460),
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
    let finish: () -> Void
    @State private var step = 0
    @State private var key = ""
    @State private var keyMessage = ""
    @State private var skippedAccessibility = false
    @State private var skippedShortcut = false
    @State private var skippedKey = false
    @State private var testText = "Tajpo make this sentence better."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titles[step])
                .font(.largeTitle.bold())
            Group {
                switch step {
                case 0:
                    Text("Select text anywhere. Tajpo appears beside it, streams a rewrite, and lets you replace, copy, or undo.")
                case 1:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tajpo needs Accessibility access only to read and replace text you select.")
                        Button("Request access") { model.requestAccessibility() }
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
                            missing: "Waiting for \(model.settings.hotkeyLabel)..."
                        )
                    }
                case 3:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.settings.provider == .openAI
                             ? "Save an OpenAI key, or switch to a local server in Settings after setup."
                             : "A local server does not need a key. You can still save one for compatible APIs.")
                        SecureField("API key", text: $key)
                        HStack {
                            Button("Save securely in Keychain") { saveKey() }
                            Button("Test connection") {
                                Task { keyMessage = await model.testConnection() }
                            }
                        }
                        if !keyMessage.isEmpty {
                            Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        statusLine(
                            ok: model.hasSavedAPIKey() || !model.settings.provider.requiresAPIKey,
                            okText: model.settings.provider.requiresAPIKey ? "A key is saved." : "Local server selected; a key is optional.",
                            missing: "Save a key or skip if you will use a local server."
                        )
                    }
                default:
                    VStack(alignment: .leading) {
                        TextEditor(text: $testText)
                            .frame(height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text("Select this text after setup and press your shortcut.")
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
            }
        }
        .padding(28)
        .frame(width: 580, height: 460)
        .onAppear { model.refreshSystemState() }
    }

    private var titles: [String] {
        ["Write better without leaving your app", "Accessibility", "Your shortcut", "Your model", "Try Tajpo"]
    }

    private var canSkip: Bool {
        (step == 1 && !model.isAccessibilityTrusted)
            || (step == 2 && !model.hotkeyConfirmed)
            || (step == 3 && model.settings.provider.requiresAPIKey && !model.hasSavedAPIKey())
    }

    private var canContinue: Bool {
        switch step {
        case 1: model.isAccessibilityTrusted || skippedAccessibility
        case 2: model.hotkeyConfirmed || skippedShortcut
        case 3: model.hasSavedAPIKey() || !model.settings.provider.requiresAPIKey || skippedKey
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
            .foregroundStyle(ok ? .green : .secondary)
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
