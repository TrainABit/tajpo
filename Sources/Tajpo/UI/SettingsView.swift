import AppKit
import SwiftUI
import TajpoCore

enum SettingsTab: Int, CaseIterable {
    case general, ai, presets, privacy

    var title: String {
        switch self {
        case .general: "General"
        case .ai: "AI Provider"
        case .presets: "Style Presets"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .ai: "sparkles"
        case .presets: "text.badge.star"
        case .privacy: "hand.raised"
        }
    }
}

/// Settings window with native toolbar tabs. Tajpo is a menu bar (accessory)
/// app, so the SwiftUI `Settings` scene wouldn't reliably come to the front.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    init(model: AppModel) {
        self.model = model
    }

    func show(tab: SettingsTab) {
        if window == nil { build() }
        tabs?.selectedTabViewItemIndex = tab.rawValue
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func build() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let root: AnyView = switch tab {
            case .general: AnyView(GeneralSettings(model: model))
            case .ai: AnyView(AISettings(model: model))
            case .presets: AnyView(PresetSettings(model: model, presets: model.presets))
            case .privacy: AnyView(PrivacySettings())
            }
            let controller = NSHostingController(rootView: root.frame(width: 580))
            controller.sizingOptions = [.preferredContentSize]
            controller.title = tab.title
            let item = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.tabs = tabs
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Ends any shortcut recording (which resumes global shortcuts).
        window?.makeFirstResponder(nil)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var updates: UpdateChecker
    @State private var loginMessage: String?

    init(model: AppModel) {
        self.model = model
        updates = model.updates
    }

    var body: some View {
        Form {
            Section {
                StatusHeader(model: model)
            }
            Section {
                ShortcutSetting(model: model, action: .rewrite)
                ShortcutSetting(model: model, action: .repeatLast)
            } header: {
                Text("Shortcuts")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts must include ⌘ or ⌃. Click a shortcut to record a new one.")
                    if model.secureInputActive {
                        Label("Another app has secure keyboard entry on (e.g. a password field), which pauses all global shortcuts.", systemImage: "lock")
                    }
                }
                .foregroundStyle(.secondary)
            }
            if !model.accessibilityTrusted {
                Section("Accessibility") {
                    AccessibilityStatus(model: model)
                }
            }
            Section {
                Toggle("Launch Tajpo at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { loginMessage = model.setLaunchAtLogin($0) }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                if let loginMessage {
                    ErrorLabel(text: loginMessage)
                }
                Toggle("Check for updates weekly", isOn: Binding(
                    get: { updates.automatic },
                    set: { updates.automatic = $0 }
                ))
            } header: {
                Text("Startup and updates")
            } footer: {
                Text("The update check asks GitHub for the latest release number. It sends nothing about you or your text.")
                    .foregroundStyle(.secondary)
                if AppLocation.isTemporary {
                    Text("Move Tajpo to your Applications folder to start it at login.").foregroundStyle(.secondary)
                } else if !LaunchAtLogin.isAvailable {
                    Text("Available when Tajpo runs as an app bundle (scripts/build-app.sh).").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: model.accessibilityTrusted ? 470 : 540)
    }
}

/// App icon, version, and whether Tajpo is ready, at the top of General.
private struct StatusHeader: View {
    @ObservedObject var model: AppModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tajpo").font(.title3.bold())
                Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.needsSetup {
                Button { model.showOnboarding() } label: {
                    Label("Finish Setup…", systemImage: "exclamationmark.circle.fill")
                }
                .tint(.orange)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Setup Guide…") { model.showOnboarding() }
                    .buttonStyle(.link)
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct AccessibilityStatus: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.accessibilityTrusted {
            Label("Tajpo can read and replace selected text in other apps.", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Tajpo isn't allowed to work in other apps yet.", systemImage: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                Button("Open Accessibility Settings") {
                    model.requestAccessibility()
                    model.openAccessibilitySettings()
                }
                Text("Already switched on but this still shows? Select Tajpo in the list, remove it with −, then add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ErrorLabel: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .font(.callout)
    }
}

// MARK: - AI provider

private struct AISettings: View {
    enum Provider: String, CaseIterable, Identifiable {
        case openAI = "OpenAI"
        case custom = "Other server"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings

    @State private var provider: Provider
    @State private var keyField = ""
    @State private var keyMessage: Message?
    @State private var confirmRemove = false
    @State private var testing = false
    @State private var modelChoice: String
    @State private var customModel: String
    @State private var modelMessage: Message?
    @State private var baseURLField: String
    @State private var projectField: String
    @State private var serverMessage: Message?

    private static let custom = "Custom…"

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        self.settings = settings
        _provider = State(initialValue: settings.usesOpenAI ? .openAI : .custom)
        _modelChoice = State(initialValue: ModelCatalog.suggested.contains(settings.model) ? settings.model : Self.custom)
        _customModel = State(initialValue: settings.model)
        _baseURLField = State(initialValue: settings.usesOpenAI ? "http://localhost:11434/v1" : settings.baseURL.absoluteString)
        _projectField = State(initialValue: settings.projectID)
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { _, new in
                    if new == .openAI {
                        applyServer(ModelCatalog.defaultBaseURL.absoluteString)
                    }
                }
            } footer: {
                Text(provider == .openAI
                     ? "Your text goes directly from your Mac to OpenAI with your own key."
                     : "Any OpenAI-compatible server works, including local ones such as Ollama or LM Studio. Your text goes only to this server.")
                    .foregroundStyle(.secondary)
            }

            if provider == .custom {
                Section("Server") {
                    TextField("Server URL", text: $baseURLField, prompt: Text("http://localhost:11434/v1"))
                        .onSubmit { applyServer(baseURLField) }
                    HStack {
                        Button("Apply") { applyServer(baseURLField) }
                        Button("Ollama") { baseURLField = "http://localhost:11434/v1"; applyServer(baseURLField) }
                        Button("LM Studio") { baseURLField = "http://localhost:1234/v1"; applyServer(baseURLField) }
                    }
                    MessageView(message: serverMessage)
                }
            }

            Section {
                if let hint = model.apiKeyHint {
                    LabeledContent("Saved in Keychain", value: hint)
                } else {
                    Text(provider == .openAI ? "No key saved yet." : "No key saved. Local servers usually don't need one.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    SecureField("API key", text: $keyField,
                                prompt: Text(model.apiKeyHint == nil ? "Paste your API key" : "Paste a new key to replace it"))
                        .onSubmit(saveKey)
                    Button("Save") { saveKey() }
                        .disabled(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button(testing ? "Testing…" : "Test Connection") { test() }
                        .disabled(testing)
                    Button("Remove Key", role: .destructive) { confirmRemove = true }
                        .disabled(model.apiKeyHint == nil)
                    Spacer()
                    if provider == .openAI {
                        Link("Get an API key ↗", destination: Links.apiKeys)
                    }
                }
                MessageView(message: keyMessage)
            } header: {
                Text("API key")
            } footer: {
                if provider == .openAI {
                    Text("\(ModelCatalog.costHint) API usage is billed by OpenAI separately from ChatGPT and needs prepaid credit.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Model") {
                Picker("Model", selection: $modelChoice) {
                    ForEach(ModelCatalog.suggested, id: \.self) { Text($0).tag($0) }
                    Text(Self.custom).tag(Self.custom)
                }
                .onChange(of: modelChoice) { _, choice in
                    if choice != Self.custom, choice != settings.model { applyModel(choice) }
                }
                if modelChoice == Self.custom {
                    HStack {
                        TextField("Model name", text: $customModel, prompt: Text("e.g. llama3.1"))
                            .onSubmit { applyModel(customModel) }
                        Button("Use") { applyModel(customModel) }
                    }
                }
                if ModelCatalog.isReasoningModel(settings.model) {
                    Text("Reasoning models are slower for quick edits. gpt-4.1-mini is usually the better fit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if provider == .openAI {
                    TextField("Project ID", text: $projectField, prompt: Text("Optional"))
                        .onSubmit { settings.setProjectID(projectField) }
                }
                MessageView(message: modelMessage)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
        .onAppear(perform: syncFromSettings)
        .onReceive(settings.$baseURL.dropFirst()) { _ in syncFromSettings() }
        .onReceive(settings.$model.dropFirst()) { _ in syncFromSettings() }
        .confirmationDialog("Remove the saved API key?", isPresented: $confirmRemove) {
            Button("Remove Key", role: .destructive) {
                do {
                    try model.removeAPIKey()
                    keyMessage = .info("Key removed.")
                } catch {
                    keyMessage = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Settings can change elsewhere (e.g. the setup guide's local-model button).
    private func syncFromSettings() {
        let current: Provider = settings.usesOpenAI ? .openAI : .custom
        if provider != current { provider = current }
        if !settings.usesOpenAI { baseURLField = settings.baseURL.absoluteString }
        modelChoice = ModelCatalog.suggested.contains(settings.model) ? settings.model : Self.custom
        customModel = settings.model
        projectField = settings.projectID
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(keyField)
            keyField = ""
            keyMessage = .info("Saved in Keychain. Testing…")
            test()
        } catch {
            keyMessage = .error(error.localizedDescription)
        }
    }

    private func test() {
        testing = true
        Task {
            defer { testing = false }
            do {
                try await model.testConnection()
                keyMessage = .success("Connected. \(settings.model) is ready to use.")
            } catch {
                keyMessage = .error(AppModel.map(error).localizedDescription)
            }
        }
    }

    private func applyModel(_ text: String) {
        do {
            try settings.setModel(text)
            customModel = settings.model
            modelMessage = .success("Now using \(settings.model).")
        } catch {
            modelMessage = .error(error.localizedDescription)
        }
    }

    private func applyServer(_ text: String) {
        do {
            try settings.setBaseURL(text)
            if provider == .openAI { settings.setProjectID(projectField) }
            serverMessage = .success("Using \(settings.baseURL.absoluteString).")
            model.refreshStatus()
        } catch {
            serverMessage = .error(error.localizedDescription)
        }
    }
}

enum Message: Equatable {
    case info(String), success(String), error(String)
}

struct MessageView: View {
    let message: Message?

    var body: some View {
        switch message {
        case .info(let text)?:
            Text(text).font(.callout).foregroundStyle(.secondary)
        case .success(let text)?:
            Label(text, systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
        case .error(let text)?:
            ErrorLabel(text: text)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Presets

private struct PresetSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presets: PresetStore
    @State private var editingID: UUID?
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A preset adds your own style instructions to Improve, Rewrite, Shorten, Change Tone, and custom instructions. Correct never uses presets, and a chosen tone wins over a preset.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    List(selection: $editingID) {
                        Section {
                            HStack {
                                Text("None")
                                Spacer()
                                if presets.selectedID == nil { activeBadge }
                            }
                            .contextMenu { Button("Use No Preset") { presets.select(nil) } }
                        }
                        ForEach(presets.presets) { preset in
                            HStack {
                                Text(preset.name)
                                Spacer()
                                if presets.selectedID == preset.id { activeBadge }
                            }
                            .tag(Optional(preset.id))
                            .contextMenu {
                                Button("Use This Preset") { presets.select(preset.id) }
                                Button("Delete", role: .destructive) { delete(preset.id) }
                            }
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: false))
                    HStack(spacing: 2) {
                        Button {
                            editingID = presets.add().id
                        } label: { Image(systemName: "plus").frame(width: 20, height: 18) }
                        .help("Add a preset")
                        .accessibilityLabel("Add preset")
                        Button {
                            if let editingID { delete(editingID) }
                        } label: { Image(systemName: "minus").frame(width: 20, height: 18) }
                        .disabled(editingID == nil)
                        .help("Delete the selected preset")
                        .accessibilityLabel("Delete preset")
                        Spacer()
                        Button("Restore…") { confirmRestore = true }
                            .help("Restore the built-in presets")
                            .controlSize(.small)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                }
                .frame(width: 200)

                if let editingID, let preset = presets.presets.first(where: { $0.id == editingID }) {
                    PresetEditor(preset: preset, isActive: presets.selectedID == preset.id,
                                 activate: { presets.select(preset.id) },
                                 save: { presets.update($0) })
                        .id(preset.id)
                } else {
                    Text("Select a preset to edit it, or click + to create one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .frame(height: 420)
        .onAppear { editingID = editingID ?? presets.selectedID ?? presets.presets.first?.id }
        .confirmationDialog("Restore the built-in presets?", isPresented: $confirmRestore) {
            Button("Restore") { presets.restoreBuiltIns() }
        } message: {
            Text("Professional and Casual are reset to their original instructions. Your own presets are kept.")
        }
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
    }

    private func delete(_ id: UUID) {
        presets.remove(id: id)
        editingID = presets.presets.first?.id
    }
}

private struct PresetEditor: View {
    @State var preset: WritingPreset
    let isActive: Bool
    let activate: () -> Void
    let save: (WritingPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
            Text("Instructions")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $preset.instructions)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Text("Example: “Use British spelling. Keep sentences under 20 words.”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isActive ? "Active" : "Use This Preset", action: activate)
                    .disabled(isActive)
            }
        }
        .onChange(of: preset) { _, updated in
            var cleaned = updated
            if cleaned.name.trimmingCharacters(in: .whitespaces).isEmpty { cleaned.name = "Untitled" }
            save(cleaned)
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    var body: some View {
        Form {
            Section("What leaves your Mac") {
                Text("Only the text you select, and only when you choose an action. It goes directly to the AI server set under AI Provider (OpenAI by default) using your own key. Tajpo has no backend, account, analytics, or text logging.")
                Link("How OpenAI handles API data ↗", destination: Links.dataUsage)
            }
            Section("Clipboard") {
                Text("In apps that don't support Accessibility, Tajpo briefly uses the clipboard to copy the selection and paste the result, then restores what you had. These temporary items are marked so clipboard managers skip them.")
            }
            Section("Stored on this Mac") {
                Text("Your API key is kept in the macOS Keychain. Settings, presets, recent instructions, and a local count of your edits are kept in Tajpo's preferences. Nothing else is stored.")
            }
            Section {
                Link("Read the full privacy policy ↗", destination: Links.privacy)
            }
        }
        .formStyle(.grouped)
        .frame(height: 490)
    }
}
