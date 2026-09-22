import AppKit
import SwiftUI
import TajpoCore

private enum Step: Int, CaseIterable {
    case welcome, accessibility, shortcut, apiKey, practice, finish

    var title: String {
        switch self {
        case .welcome: "Write better without leaving your app"
        case .accessibility: "Allow Accessibility access"
        case .shortcut: "Your shortcut"
        case .apiKey: "Connect OpenAI"
        case .practice: "Try it"
        case .finish: "You're set"
        }
    }
}

/// Holds the practice text and lets Tajpo's own window act as the text source.
@MainActor
final class PracticeText: ObservableObject, LocalTextProvider {
    @Published var text = "Their going to the libary tomorow, but me and him thinks its closed."
    @Published var replaced = false

    var practiceText: String { text }

    func replacePracticeText(with text: String) {
        self.text = text
        replaced = true
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @StateObject private var practice = PracticeText()

    @AppStorage("onboardingStep") private var savedStep = 0
    @State private var step: Step = .welcome
    @State private var requestedAccess: Date?
    @State private var shortcutPressed = false
    @State private var keyField = ""
    @State private var keyMessage: Message?
    @State private var checkingKey = false
    @State private var loginError: String?

    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { item in
                        Circle()
                            .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(step.title)
                .font(.largeTitle.bold())
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            navigation
        }
        .padding(28)
        .frame(width: 620, height: 500)
        .onAppear {
            step = Step(rawValue: savedStep) ?? .welcome
            enter(step)
        }
        .onChange(of: step) { old, new in
            leave(old)
            enter(new)
            savedStep = new.rawValue
        }
        .onReceive(poll) { _ in
            if step == .accessibility { model.refreshStatus() }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Select text in any app, press a shortcut, and Tajpo corrects, improves, shortens, or changes its tone right next to your text. You check the result, then replace or copy it.")
                Text("Setup takes about two minutes: one permission, a shortcut, and your OpenAI API key.")
                    .foregroundStyle(.secondary)
            }
        case .accessibility:
            VStack(alignment: .leading, spacing: 12) {
                Text("Tajpo uses Accessibility access only to read the text you select and to put the result back. macOS will ask you to turn Tajpo on in System Settings.")
                AccessibilityStatus(model: model)
                if !model.accessibilityTrusted, let requestedAccess, Date().timeIntervalSince(requestedAccess) > 20 {
                    Button("Reveal Tajpo in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .help("Drag Tajpo into the Accessibility list if it's missing.")
                }
            }
            .onAppear { if requestedAccess == nil, !model.accessibilityTrusted { requestedAccess = Date() } }
        case .shortcut:
            VStack(alignment: .leading, spacing: 12) {
                Text("Press this shortcut in any app after selecting text. Click it to choose a different one.")
                ShortcutSetting(model: model, action: .rewrite)
                if shortcutPressed {
                    Label("It works. Tajpo heard \(settings.rewriteShortcut?.displayString ?? "the shortcut").", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let shortcut = settings.rewriteShortcut {
                    Label("Try it now: press \(shortcut.displayString).", systemImage: "keyboard")
                        .foregroundStyle(.secondary)
                }
            }
        case .apiKey:
            apiKeyStep
        case .practice:
            VStack(alignment: .leading, spacing: 10) {
                Text("Click in the text below and press \(settings.rewriteShortcut?.displayString ?? "your shortcut"). Choose Correct, then Replace. Here Tajpo uses the whole practice text; in other apps it uses your selection.")
                TextEditor(text: $practice.text)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                if practice.replaced {
                    Label("Nice. That's the whole workflow.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Open TextEdit with Sample Text") { openTextEdit() }
                Text("In other apps, select text first. If an app can't be edited (a web page, a PDF), Tajpo offers Copy instead of Replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .finish:
            VStack(alignment: .leading, spacing: 10) {
                checklistRow("Accessibility access", done: model.accessibilityTrusted, fix: { step = .accessibility })
                checklistRow("Shortcut \(settings.rewriteShortcut?.displayString ?? "")", done: model.hotkeyErrors[.rewrite] == nil && settings.rewriteShortcut != nil, fix: { step = .shortcut })
                checklistRow("API key", done: !model.needsAPIKey, fix: { step = .apiKey })
                Divider()
                Toggle("Launch Tajpo at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { loginError = model.setLaunchAtLogin($0) }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Text("Tajpo lives in the menu bar. Open it for settings, presets, and this guide.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tajpo sends the text you select directly to OpenAI using your own API key. The key stays in your Mac's Keychain.")
            Text("API usage is billed by OpenAI separately from ChatGPT and needs prepaid credit. Typical edits cost a fraction of a cent.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Text("·").foregroundStyle(.secondary)
                Link("Add credit", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
            }
            if let hint = model.apiKeyHint {
                Label("Saved in Keychain · \(hint)", systemImage: "key.fill")
                    .foregroundStyle(.secondary)
            }
            HStack {
                SecureField(model.apiKeyHint == nil ? "Paste your API key (sk-…)" : "Paste a new key to replace it", text: $keyField)
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        keyField = text
                        saveAndCheckKey(advance: false)
                    }
                }
                Button(checkingKey ? "Checking…" : "Save & Check") { saveAndCheckKey(advance: false) }
                    .disabled(checkingKey || keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            MessageView(message: keyMessage)
            if !settings.usesOpenAI {
                Text("You're using a custom server (\(settings.baseURL.host ?? "")), so a key may not be needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navigation: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(-1) }
            }
            Spacer()
            if step != .welcome && step != .finish {
                Button("Skip for Now") { move(1) }
            }
            Button(step == .finish ? "Finish" : "Continue") { continueTapped() }
                .keyboardShortcut(.defaultAction)
                .disabled(checkingKey)
        }
    }

    private func checklistRow(_ title: String, done: Bool, fix: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(done ? .green : .orange)
            Text(title)
            Spacer()
            if !done { Button("Fix", action: fix) }
        }
    }

    // MARK: Actions

    private func continueTapped() {
        switch step {
        case .apiKey where !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            // Return in the key field lands here: save instead of dropping the key.
            saveAndCheckKey(advance: true)
        case .finish:
            savedStep = 0
            model.completeOnboarding()
        default:
            move(1)
        }
    }

    private func move(_ offset: Int) {
        if let next = Step(rawValue: step.rawValue + offset) { step = next }
    }

    private func saveAndCheckKey(advance: Bool) {
        do {
            try model.saveAPIKey(keyField)
        } catch {
            keyMessage = .error(error.localizedDescription)
            return
        }
        keyField = ""
        keyMessage = .info("Saved in Keychain. Checking the key…")
        checkingKey = true
        Task {
            defer { checkingKey = false }
            do {
                try await model.testConnection()
                keyMessage = .success("Your key works.")
                if advance { move(1) }
            } catch {
                // The key is saved either way; explain what's wrong but let the user continue.
                keyMessage = .error(AppModel.map(error).localizedDescription)
            }
        }
    }

    private func enter(_ step: Step) {
        switch step {
        case .shortcut:
            shortcutPressed = false
            model.shortcutProbe = { shortcutPressed = true }
        case .practice:
            model.localTextProvider = practice
        default:
            break
        }
    }

    private func leave(_ step: Step) {
        switch step {
        case .shortcut: model.shortcutProbe = nil
        case .practice: model.localTextProvider = nil
        default: break
        }
    }

    private func openTextEdit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tajpo Practice.txt")
        let sample = "Select this sentence and press \(settings.rewriteShortcut?.displayString ?? "your shortcut"): their going to the libary tomorow.\n"
        try? sample.write(to: url, atomically: true, encoding: .utf8)
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
