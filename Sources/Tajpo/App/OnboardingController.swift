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
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 430),
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
    @State private var testText = "Tajpo make this sentence better."
    private let keyStore = KeychainAPIKeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text([
                "Write better without leaving your app",
                "Accessibility",
                "Your shortcut",
                "Your OpenAI key",
                "Try Tajpo"
            ][step])
            .font(.largeTitle.bold())
            Group {
                if step == 0 {
                    Text("Select text anywhere. Tajpo appears beside it, streams a rewrite, and lets you replace or copy.")
                } else if step == 1 {
                    VStack(alignment: .leading) {
                        Text("Tajpo needs Accessibility access only to read and replace text you select. The system prompt appears when you request it.")
                        Button("Request access") { model.requestAccessibility() }
                    }
                } else if step == 2 {
                    VStack(alignment: .leading) {
                        Text("Press \(model.settings.hotkeyLabel) after setup. This is the same shortcut you will use in other apps.")
                        Text("Tip: you can change it later in Settings.")
                            .foregroundStyle(.secondary)
                    }
                } else if step == 3 {
                    VStack(alignment: .leading) {
                        SecureField("OpenAI API key", text: $key)
                        Button("Save securely in Keychain") { saveKey() }
                        if !keyMessage.isEmpty {
                            Text(keyMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
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
                Spacer()
                Button(step == 4 ? "Finish" : "Continue") {
                    if step == 4 { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 430)
    }

    private func saveKey() {
        do {
            try keyStore.save(APIKeyValidator.validate(key))
            key = ""
            keyMessage = "Saved in Keychain."
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}
