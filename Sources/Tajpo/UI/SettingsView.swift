import SwiftUI
import TajpoCore

enum SettingsTab: Hashable {
    case general, ai, presets, privacy
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AISettings(model: model)
                .tabItem { Label("AI Provider", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
            PresetSettings(presets: model.presets)
                .tabItem { Label("Style Presets", systemImage: "text.badge.star") }
                .tag(SettingsTab.presets)
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
        }
        .padding(12)
        .frame(minWidth: 600, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutSetting(model: model, action: .rewrite)
                ShortcutSetting(model: model, action: .repeatLast)
                Text("Shortcuts must include ⌘ or ⌃. Press ⌫ while recording to turn a shortcut off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.secureInputActive {
                    Label("Another app has secure keyboard entry on (e.g. a password field), which pauses all global shortcuts.", systemImage: "lock")
                        .font(.caption)
                }
            }
            Section("Accessibility") {
                AccessibilityStatus(model: model)
            }
            Section("Startup") {
                Toggle("Launch Tajpo at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { loginError = model.setLaunchAtLogin($0) }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Available when Tajpo runs as an app bundle (scripts/build-app.sh).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Show Setup Guide…") { model.showOnboarding() }
            }
        }
        .formStyle(.grouped)
    }
}

struct AccessibilityStatus: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.accessibilityTrusted {
                Label("Accessibility access is on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Accessibility access is off. Tajpo can't read or replace selected text.", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                HStack {
                    Button("Request Access") { model.requestAccessibility() }
                    Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                }
                Text("If Tajpo is already switched on in the list but this still says off, macOS is holding a permission for an older build: select Tajpo, remove it with −, then add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - AI provider

private struct AISettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings

    @State private var keyField = ""
    @State private var keyMessage: Message?
    @State private var confirmRemove = false
    @State private var testing = false
    @State private var modelChoice = ""
    @State private var customModel = ""
    @State private var modelMessage: Message?
    @State private var baseURLField = ""
    @State private var projectField = ""
    @State private var serverMessage: Message?

    private static let custom = "Custom…"

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        Form {
            Section("OpenAI API key") {
                if let hint = model.apiKeyHint {
                    LabeledContent("Saved in Keychain", value: hint)
                } else {
                    Text(settings.usesOpenAI ? "No key saved yet." : "No key saved. Local servers usually don't need one.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    SecureField(model.apiKeyHint == nil ? "Paste your API key" : "Paste a new key to replace it", text: $keyField)
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
                    Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                }
                MessageView(message: keyMessage)
                Text("API usage is billed by OpenAI separately from ChatGPT subscriptions and needs prepaid credit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

            Section("Model") {
                Picker("Model", selection: $modelChoice) {
                    ForEach(ModelCatalog.suggested, id: \.self) { Text($0).tag($0) }
                    Text(Self.custom).tag(Self.custom)
                }
                .onChange(of: modelChoice) { _, choice in
                    if choice != Self.custom { applyModel(choice) }
                }
                if modelChoice == Self.custom {
                    HStack {
                        TextField("Model name", text: $customModel)
                            .onSubmit { applyModel(customModel) }
                        Button("Use") { applyModel(customModel) }
                    }
                }
                if ModelCatalog.isReasoningModel(settings.model) {
                    Text("Reasoning models are slower and ignore temperature. gpt-4.1-mini is usually the better fit for quick edits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MessageView(message: modelMessage)
            }

            Section("Server (advanced)") {
                TextField("Server URL", text: $baseURLField)
                    .onSubmit(applyServer)
                TextField("OpenAI project ID (optional)", text: $projectField)
                    .onSubmit(applyServer)
                HStack {
                    Button("Apply") { applyServer() }
                    Button("Use OpenAI") {
                        baseURLField = ModelCatalog.defaultBaseURL.absoluteString
                        applyServer()
                    }
                }
                Text("Any OpenAI-compatible server works, including local ones such as Ollama (http://localhost:11434/v1) or LM Studio. Text is sent only to this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MessageView(message: serverMessage)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFields)
    }

    private func loadFields() {
        modelChoice = ModelCatalog.suggested.contains(settings.model) ? settings.model : Self.custom
        customModel = settings.model
        baseURLField = settings.baseURL.absoluteString
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
            modelMessage = .info("Using \(settings.model).")
        } catch {
            modelMessage = .error(error.localizedDescription)
        }
    }

    private func applyServer() {
        do {
            try settings.setBaseURL(baseURLField)
            settings.setProjectID(projectField)
            baseURLField = settings.baseURL.absoluteString
            serverMessage = .info("Using \(settings.baseURL.absoluteString).")
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
            Text(text).font(.caption).foregroundStyle(.secondary)
        case .success(let text)?:
            Label(text, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .error(let text)?:
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Presets

private struct PresetSettings: View {
    @ObservedObject var presets: PresetStore
    @State private var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Active preset", selection: Binding(get: { presets.selectedID }, set: { presets.select($0) })) {
                    Text("None").tag(UUID?.none)
                    ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
                }
                .fixedSize()
                Spacer()
            }
            Text("A preset adds your own style instructions to Improve, Rewrite, Shorten, and Change Tone. Correct never uses presets, and a chosen tone wins over a preset.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $editingID) {
                        ForEach(presets.presets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                    HStack(spacing: 4) {
                        Button {
                            editingID = presets.add().id
                        } label: { Image(systemName: "plus") }
                        .help("Add a preset")
                        Button {
                            if let editingID { presets.remove(id: editingID) }
                            editingID = presets.presets.first?.id
                        } label: { Image(systemName: "minus") }
                        .disabled(editingID == nil)
                        .help("Delete the selected preset")
                        Spacer()
                        Button("Restore Built-ins") { presets.restoreBuiltIns() }
                            .controlSize(.small)
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                }
                .frame(minWidth: 180, maxWidth: 240)

                if let editingID, let preset = presets.presets.first(where: { $0.id == editingID }) {
                    PresetEditor(preset: preset) { presets.update($0) }
                        .id(preset.id)
                        .padding(.leading, 10)
                } else {
                    Text("Select a preset to edit it.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(8)
        .onAppear { editingID = editingID ?? presets.selectedID ?? presets.presets.first?.id }
    }
}

private struct PresetEditor: View {
    @State var preset: WritingPreset
    let save: (WritingPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
            Text("Instructions")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $preset.instructions)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            Text("Example: “Use British spelling. Keep sentences under 20 words.”")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Text("Only the text you select, and only when you choose an action. It is sent directly to the AI server configured under AI Provider (OpenAI by default) with your own key. Tajpo has no backend, account, analytics, or text logging.")
                Text("OpenAI may keep API requests for up to 30 days for abuse monitoring and does not train on API data by default. See OpenAI's API data usage policies for details.")
                    .foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Text("In apps that don't support Accessibility, Tajpo briefly uses the clipboard to copy the selection and paste the result, then restores what you had. These temporary items are marked so clipboard managers skip them.")
            }
            Section("Stored on this Mac") {
                Text("Your API key is kept in the macOS Keychain. Settings and presets are kept in Tajpo's preferences. Nothing else is stored.")
            }
        }
        .formStyle(.grouped)
    }
}
