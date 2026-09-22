import AppKit
import SwiftUI
import TajpoCore

/// Setup steps. The order puts a working result before the scary permission:
/// the practice step uses Tajpo's own window, which needs no Accessibility access.
enum OnboardingStep: Int, CaseIterable {
    case welcome, connect, tryIt, everywhere, done

    static let storageKey = "onboardingStepV2"

    var label: String {
        switch self {
        case .welcome: "Welcome"
        case .connect: "Connect"
        case .tryIt: "Try it"
        case .everywhere: "Every app"
        case .done: "Done"
        }
    }
}

/// Holds the practice text and lets Tajpo's own window act as the text source.
@MainActor
final class PracticeText: ObservableObject, LocalTextProvider {
    @Published var text = "Their going to the libary tomorow, but me and him thinks its closed."
    @Published var fixes: Int?

    var practiceText: String { text }

    func replacePracticeText(with text: String, diff: [DiffSegment]?) {
        self.text = text
        fixes = diff?.filter { $0.kind == .inserted }.count ?? 0
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @StateObject private var practice = PracticeText()

    @AppStorage(OnboardingStep.storageKey) private var savedStep = 0
    @State private var step: OnboardingStep = .welcome
    @State private var resumed = false
    @State private var restoring = false

    // Connect
    @State private var keyField = ""
    @State private var keyStatus: KeyStatus = .idle
    @State private var showLocalOption = false

    // Try it
    @State private var choosingShortcut = false

    // Every app
    @State private var requestedAccess: Date?
    @State private var grantCelebrated = false

    // Done
    @State private var launchAtLogin = true
    @State private var checkUpdates = true
    @State private var loginMessage: String?
    @State private var loginAttempted = false

    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    enum KeyStatus: Equatable {
        case idle, checking, connected, warning(String), failure(String, RecoveryAction?)
    }

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            progressBar
            if resumed {
                Label("Welcome back. Pick up where you left off.", systemImage: "arrow.uturn.forward")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            navigation
        }
        .padding(28)
        .frame(width: 640, height: 500)
        .onAppear {
            let restored = OnboardingStep(rawValue: savedStep) ?? .welcome
            restoring = restored != .welcome
            resumed = restored != .welcome
            step = restored
            enter(restored)
        }
        .onChange(of: step) { old, new in
            if restoring {
                // The initial jump to a saved step isn't a user navigation.
                restoring = false
                return
            }
            leave(old)
            enter(new)
            savedStep = new.rawValue
            resumed = false
        }
        .onReceive(poll) { _ in
            guard step == .everywhere else { return }
            model.refreshStatus()
            if model.accessibilityTrusted && !grantCelebrated { accessGranted() }
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases.filter { $0 != .welcome }, id: \.self) { item in
                let done = isComplete(item)
                let current = item == step
                HStack(spacing: 4) {
                    Image(systemName: done ? "checkmark.circle.fill" : (current ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(done ? Color.green : (current ? Color.accentColor : Color.secondary))
                    Text(item.label)
                        .fontWeight(current ? .semibold : .regular)
                        .foregroundStyle(current ? .primary : .secondary)
                }
                if item != .done {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1).frame(maxWidth: 40)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup step \(max(step.rawValue, 1)) of 4, \(step.label)")
    }

    private func isComplete(_ item: OnboardingStep) -> Bool {
        switch item {
        case .welcome: true
        case .connect: !model.needsAPIKey && keyStatus != .checking
        case .tryIt: practice.fixes != nil
        case .everywhere: model.accessibilityTrusted
        case .done: false
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .connect: connect
        case .tryIt: tryIt
        case .everywhere: everywhere
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Better writing, in any app")
                .font(.largeTitle.bold())
            DemoAnimation()
            Text("Select text, press a shortcut, and Tajpo fixes, polishes, shortens, or changes its tone right where you're writing. You always see the result before anything changes.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Setup takes about 3 minutes, plus about 5 more if you still need to add OpenAI API credit.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.usesOpenAI ? "Connect your OpenAI account" : "Connect your AI server")
                .font(.largeTitle.bold())
            if settings.usesOpenAI {
                Text("Tajpo runs on your own OpenAI API key. Your text goes straight from your Mac to OpenAI, never to us. Tajpo has no servers.")
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = model.apiKeyHint, keyField.isEmpty, keyStatus == .idle || keyStatus == .connected {
                    Label("Connected · \(hint)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    checklistRow(1, "Add credit at OpenAI ($5 is plenty to start)", link: ("Open Billing", Links.billing))
                    checklistRow(2, "Create an API key", link: ("Open API Keys", Links.apiKeys))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        numberBadge(3)
                        Text("Paste it here")
                        Button("Paste Key") { pasteKey() }
                            .buttonStyle(.borderedProminent)
                            .disabled(keyStatus == .checking)
                        SecureField("or type it (sk-…)", text: $keyField)
                    }
                }
                keyStatusView
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ModelCatalog.costHint)
                        Text("Prepaid means you're never billed more than you add. When credit runs out, Tajpo just stops until you top up. This is separate from ChatGPT Plus.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Your key is stored only in your Mac's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("No OpenAI account? Use a free local model instead", isExpanded: $showLocalOption) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("If you run Ollama or LM Studio on this Mac, Tajpo can use it with no key and no cost. Your text never leaves your Mac.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Use Ollama") { useLocalServer("http://localhost:11434/v1") }
                            Button("Use LM Studio") { useLocalServer("http://localhost:1234/v1") }
                        }
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
                .font(.callout)
            } else {
                Text("Tajpo is set to use \(settings.baseURL.absoluteString). Your text goes only to that server.")
                keyStatusView
                Button("Check Connection") { checkConnection() }
                Button("Use OpenAI instead") {
                    try? settings.setBaseURL(ModelCatalog.defaultBaseURL.absoluteString)
                    keyStatus = .idle
                    model.refreshStatus()
                }
                .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var keyStatusView: some View {
        switch keyStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking with the AI server…")
            }
            .font(.callout)
        case .connected:
            Label("Connected. Tajpo is ready to write.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .warning(let text):
            Label(text, systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let text, let recovery):
            VStack(alignment: .leading, spacing: 6) {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let recovery {
                        Button(InlineRewriteView.title(for: recovery)) { model.perform(recovery) }
                    }
                    Button("Check Again") { checkConnection() }
                }
            }
            .font(.callout)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it").font(.largeTitle.bold())
            if model.needsAPIKey {
                GroupBox {
                    HStack {
                        Label("Tajpo needs your OpenAI key before it can edit text.", systemImage: "key")
                        Spacer()
                        Button("Add Key") { step = .connect }
                    }
                    .padding(4)
                }
            }
            HStack(spacing: 10) {
                Text("Press")
                KeyCaps(shortcut: settings.rewriteShortcut)
                Text("then pick **Correct** and **Replace**.")
            }
            .font(.title3)
            TextEditor(text: $practice.text)
                .font(.body)
                .frame(height: 80)
                .scrollIndicators(.never)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Text("Tip: click in the box first. You can also type a sentence of your own.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let fixes = practice.fixes {
                Label(fixes > 0 ? "Fixed \(fixes) \(fixes == 1 ? "mistake" : "mistakes"). That's the whole workflow." : "Done. That's the whole workflow.",
                      systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
            HStack {
                Button("Or click here to open Tajpo") { model.openPanel() }
                    .buttonStyle(.link)
                Spacer()
                if choosingShortcut {
                    ShortcutSetting(model: model, action: .rewrite)
                        .frame(maxWidth: 360)
                } else if let shortcut = settings.rewriteShortcut {
                    Text("\(shortcut.displayString) works in almost every app.")
                        .foregroundStyle(.secondary)
                    Button("Choose Another") { choosingShortcut = true }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
        }
        .animation(.default, value: practice.fixes)
    }

    private var everywhere: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use Tajpo in every app").font(.largeTitle.bold())
            Text("To read the text you select in Mail, Notes, Slack, and other apps, and to put the improved version back, macOS needs you to turn on Accessibility for Tajpo.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                promiseColumn("Tajpo does", symbol: "checkmark", color: .green, items: [
                    "Read the text you select, only when you press the shortcut",
                    "Put the result back when you click Replace"
                ])
                promiseColumn("Tajpo doesn't", symbol: "xmark", color: .secondary, items: [
                    "Record your keystrokes",
                    "Read your screen or other windows",
                    "Send anything until you choose an action",
                    "Touch password fields"
                ])
            }
            Text("macOS will describe this as letting Tajpo “control your computer”. That's the standard wording for any app that edits text in other apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.accessibilityTrusted {
                Label("Done. Tajpo can now work in any app.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else if let requestedAccess, Date().timeIntervalSince(requestedAccess) > 20 {
                DisclosureGroup("Having trouble?") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Don't see Tajpo in the list?")
                            Button("Show Tajpo in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                            }
                            Text("and drag it into the list.")
                        }
                        Text("Tajpo is switched on but this still says it isn't? Select Tajpo, remove it with −, then add it again.")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var done: some View {
        let missing = missingItems
        return VStack(alignment: .leading, spacing: 14) {
            Text(missing.isEmpty ? "You're ready" : "Almost there").font(.largeTitle.bold())
            if missing.isEmpty {
                HStack(spacing: 10) {
                    Text("Select text anywhere, then press")
                    KeyCaps(shortcut: settings.rewriteShortcut)
                }
                .font(.title3)
                Button("Try It in TextEdit") { openTextEdit() }
            } else {
                Text(missing.count == 1 ? "One thing is still missing. You can finish it now or later from the menu bar." : "A few things are still missing. You can finish them now or later from the menu bar.")
                    .foregroundStyle(.secondary)
                ForEach(missing, id: \.title) { item in
                    HStack {
                        Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                        Text(item.title)
                        Spacer()
                        Button("Add Now") { step = item.step }
                    }
                }
            }
            Divider()
            if LaunchAtLogin.isAvailable {
                Toggle("Start Tajpo when you log in (recommended, so the shortcut always works)", isOn: $launchAtLogin)
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.orange)
                }
            } else if AppLocation.isTemporary {
                Label("Tajpo is running from a temporary location. Move it to Applications so it can start at login.", systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Toggle("Check for new versions weekly (asks GitHub for the latest version number, nothing else)", isOn: $checkUpdates)
            Label("Tajpo lives in your menu bar, where you'll find settings, presets, and this guide.", systemImage: "menubar.arrow.up.rectangle")
                .foregroundStyle(.secondary)
        }
    }

    private var missingItems: [(title: String, step: OnboardingStep)] {
        var items: [(String, OnboardingStep)] = []
        if model.needsAPIKey { items.append(("Add your OpenAI key (needed to edit text)", .connect)) }
        if !model.accessibilityTrusted { items.append(("Allow Tajpo in other apps (Accessibility)", .everywhere)) }
        if settings.rewriteShortcut == nil || model.hotkeyErrors[.rewrite] != nil { items.append(("Choose a working shortcut", .tryIt)) }
        return items
    }

    // MARK: Navigation

    private var navigation: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(-1) }
            }
            Spacer()
            if let skip = skipTitle {
                Button(skip) { move(1) }
                    .buttonStyle(.link)
            }
            Button(primaryTitle) { primaryAction() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(keyStatus == .checking)
        }
    }

    private var skipTitle: String? {
        switch step {
        case .connect where model.needsAPIKey: "I'll Do This Later"
        case .everywhere where !model.accessibilityTrusted: "Not Now"
        case .tryIt where practice.fixes == nil: "Skip"
        default: nil
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .connect: (!model.needsAPIKey && keyField.isEmpty) ? "Continue" : "Check Key"
        case .tryIt: "Continue"
        case .everywhere: model.accessibilityTrusted ? "Continue" : "Open System Settings"
        case .done: missingItems.isEmpty ? "Start Writing" : "Finish Later"
        }
    }

    private func primaryAction() {
        switch step {
        case .connect:
            if !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Return in the key field lands here: save and check instead of dropping the key.
                checkKey()
            } else if model.needsAPIKey {
                keyStatus = .warning("Paste your API key first, or choose “I'll Do This Later”.")
            } else {
                move(1)
            }
        case .everywhere:
            if model.accessibilityTrusted {
                move(1)
            } else {
                requestedAccess = Date()
                model.requestAccessibility()
            }
        case .done:
            finish()
        default:
            move(1)
        }
    }

    private func move(_ offset: Int) {
        if let next = OnboardingStep(rawValue: step.rawValue + offset) { step = next }
    }

    private func finish() {
        if LaunchAtLogin.isAvailable, launchAtLogin != model.launchAtLoginEnabled, !loginAttempted {
            loginAttempted = true
            if let message = model.setLaunchAtLogin(launchAtLogin) {
                // Show it once; pressing Finish again completes setup anyway.
                loginMessage = message + " Press the button again to finish."
                return
            }
        }
        model.updates.automatic = checkUpdates
        savedStep = 0
        model.completeOnboarding()
        model.celebrateMenuBarIcon()
    }

    private func enter(_ step: OnboardingStep) {
        switch step {
        case .tryIt:
            model.localTextProvider = practice
        case .done:
            launchAtLogin = LaunchAtLogin.isAvailable
        default:
            break
        }
    }

    private func leave(_ step: OnboardingStep) {
        if step == .tryIt { model.localTextProvider = nil }
    }

    // MARK: Key handling

    private func pasteKey() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            keyStatus = .warning("The clipboard is empty. Copy your key from OpenAI's API keys page first.")
            return
        }
        keyField = text
        checkKey()
    }

    private func checkKey() {
        let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            do {
                try model.saveAPIKey(trimmed)
            } catch {
                keyStatus = .failure(AppModel.map(error).localizedDescription, nil)
                return
            }
            keyField = ""
            if !APIKeyValidator.looksLikeOpenAIKey(trimmed) {
                keyStatus = .warning("Saved, but this doesn't look like an OpenAI key (they start with “sk-”). Check it if the connection fails.")
            }
        }
        checkConnection()
    }

    private func checkConnection() {
        keyStatus = .checking
        Task {
            do {
                try await model.testConnection()
                keyStatus = .connected
                try? await Task.sleep(for: .seconds(1))
                if step == .connect { move(1) }
            } catch {
                keyStatus = Self.friendly(AppModel.map(error))
            }
        }
    }

    private func useLocalServer(_ url: String) {
        do {
            try settings.setBaseURL(url)
            model.refreshStatus()
            checkConnection()
        } catch {
            keyStatus = .failure(error.localizedDescription, nil)
        }
    }

    /// Setup-specific wording with the next step attached.
    static func friendly(_ error: TajpoError) -> KeyStatus {
        switch error {
        case .insufficientQuota:
            .failure("Your key works, but the account has no API credit yet. New credit can take a few minutes to activate.", .openBilling)
        case .invalidAPIKey:
            .failure("OpenAI didn't accept this key. Copy it again from the API keys page. Keys are shown only once, so you may need to create a new one.", .openAPIKeys)
        case .network:
            .failure("Couldn't reach the AI server. Check your internet connection (or that your local server is running), then check again.", nil)
        case .rateLimited, .serverError:
            .warning("The AI server is busy right now. Your key is saved; you can continue and it will work shortly.")
        case .modelNotFound:
            .failure(error.localizedDescription, .openSettings)
        default:
            .failure(error.localizedDescription, error.recoveryAction)
        }
    }

    // MARK: Accessibility

    private func accessGranted() {
        grantCelebrated = true
        NSApp.activate()
        NSApp.windows.first { $0.title == "Welcome to Tajpo" }?.makeKeyAndOrderFront(nil)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if step == .everywhere { move(1) }
        }
    }

    // MARK: Pieces

    private func checklistRow(_ number: Int, _ text: String, link: (String, URL)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            numberBadge(number)
            Text(text)
            Spacer()
            Link(link.0 + " ↗", destination: link.1)
        }
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.caption.bold())
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.accentColor.opacity(0.15)))
            .accessibilityHidden(true)
    }

    private func promiseColumn(_ title: String, symbol: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openTextEdit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tajpo Practice.txt")
        try? "Their going to the libary tomorow, but me and him thinks its closed.\n".write(to: url, atomically: true, encoding: .utf8)
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Links {
    static let billing = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!
    static let apiKeys = URL(string: "https://platform.openai.com/api-keys")!
    static let dataUsage = URL(string: "https://platform.openai.com/docs/guides/your-data")!
    static let privacy = URL(string: "https://github.com/TrainABit/tajpo/blob/main/PRIVACY.md")!
}

/// Shows a shortcut as keyboard keys, e.g. [⌃] [⌥] [T].
struct KeyCaps: View {
    let shortcut: GlobalShortcut?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.title3.monospaced().weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.4)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut?.displayString ?? "your shortcut")
    }

    private var keys: [String] {
        guard let shortcut else { return ["?"] }
        var result: [String] = []
        if shortcut.hasControl { result.append("⌃") }
        if shortcut.hasOption { result.append("⌥") }
        if shortcut.hasShift { result.append("⇧") }
        if shortcut.hasCommand { result.append("⌘") }
        result.append(KeyCode.name(for: shortcut.keyCode))
        return result
    }
}

/// A looping, scripted demo of the workflow (no network, no key needed).
private struct DemoAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0
    private let timer = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    private static let before = "Their going to the libary tomorow."
    private static let diff: [DiffSegment] = [
        .init(.removed, "Their"), .init(.inserted, "They're"), .init(.same, " going to the "),
        .init(.removed, "libary"), .init(.inserted, "library"), .init(.same, " "),
        .init(.removed, "tomorow"), .init(.inserted, "tomorrow"), .init(.same, ".")
    ]

    var body: some View {
        let shown = reduceMotion ? 2 : frame
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your text").font(.caption).foregroundStyle(.secondary)
                Text(shown == 0 ? Self.before : "They're going to the library tomorrow.")
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(shown == 0 ? Color.accentColor.opacity(0.2) : Color.clear)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tajpo").font(.caption).foregroundStyle(.secondary)
                Group {
                    if shown == 0 {
                        Text("Press ⌃⌥T…").foregroundStyle(.secondary)
                    } else {
                        Text(InlineRewriteView.attributed(Self.diff))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: frame)
        .onReceive(timer) { _ in frame = (frame + 1) % 3 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: “Their going to the libary tomorow” becomes “They're going to the library tomorrow.”")
    }
}
