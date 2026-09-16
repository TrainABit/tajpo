import SwiftUI

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var presets: PresetStore
    @State private var apiKey = ""
    @State private var message = ""
    @State private var presetName = ""
    @State private var presetPrompt = ""

    public init(model: AppModel) {
        self.model = model
        settings = model.settings
        presets = model.presets
    }

    public var body: some View {
        Form {
            Section("Model") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.provider) { _, _ in
                    settings.applyProviderDefaults()
                }
                TextField("Model", text: $settings.model)
                TextField("Base URL", text: $settings.baseURL)
                Picker("Auth", selection: $settings.authStyle) {
                    ForEach(LLMAuthStyle.allCases) { Text($0.title).tag($0) }
                }
                TextField("Azure API version", text: $settings.apiVersion)
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("Save key") { saveKey() }
                    Button("Remove key", role: .destructive) { removeKey() }
                    Button("Test connection") {
                        Task { message = await model.testConnection() }
                    }
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Local servers: start Ollama (`ollama serve`), llama.cpp (`llama-server`), or `mlx_lm.server`, then use their OpenAI-compatible /v1 URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Global shortcut") {
                ShortcutRecorderView(
                    keyCode: $settings.hotkeyKeyCode,
                    modifiers: $settings.hotkeyModifiers,
                    onApply: { model.configureHotkey() }
                )
                Button("Apply shortcut") { model.configureHotkey() }
            }
            Section("Writing presets") {
                Picker("Active", selection: $presets.selectedID) {
                    ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
                }
                ForEach(presets.presets) { preset in
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            presets.remove(id: preset.id)
                        }
                        .disabled(presets.presets.count == 1)
                    }
                }
                TextField("New preset name", text: $presetName)
                TextField("System prompt", text: $presetPrompt, axis: .vertical)
                Button("Add preset") {
                    presets.add(name: presetName, prompt: presetPrompt)
                    presetName = ""
                    presetPrompt = ""
                }
            }
            Section("Permissions") {
                Text(model.isAccessibilityTrusted
                     ? "Accessibility access is granted."
                     : "Tajpo needs Accessibility access to read and replace selected text.")
                Button("Request Accessibility access") { model.requestAccessibility() }
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            Section("Updates") {
                Text("Tajpo \(AppVersion.string)")
                TextField("GitHub repository", text: $settings.githubRepository)
                if !model.updateMessage.isEmpty {
                    Text(model.updateMessage).font(.caption)
                }
                HStack {
                    Button("Check for updates") {
                        Task { await model.checkForUpdates(quiet: false) }
                    }
                    if model.updateURL != nil {
                        Button("Open latest release") { model.openUpdatePage() }
                    }
                }
            }
            Section("Privacy") {
                Text("Tajpo has no account or backend. Text leaves this Mac only when you use a remote provider. A local Ollama / llama.cpp / MLX server keeps text on-device. The API key is stored in Keychain. The app is not App Sandboxed because Accessibility, a global hotkey, and clipboard fallback cannot work in the sandbox.")
            }
        }
        .padding(20)
        .frame(width: 560, height: 720)
        .onAppear {
            model.refreshSystemState()
            refreshKeyStatus()
        }
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(apiKey)
            apiKey = ""
            message = "Saved in Keychain."
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try model.deleteAPIKey()
            apiKey = ""
            message = "Removed."
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshKeyStatus() {
        if model.hasSavedAPIKey() {
            message = "A key is already saved in Keychain."
        }
    }
}
