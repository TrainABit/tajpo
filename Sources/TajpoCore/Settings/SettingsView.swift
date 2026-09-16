import SwiftUI

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var presets: PresetStore
    @ObservedObject private var history: HistoryStore
    @State private var apiKey = ""
    @State private var message = ""
    @State private var presetName = ""
    @State private var presetPrompt = ""
    @State private var tab = SettingsTab.model

    public init(model: AppModel) {
        self.model = model
        settings = model.settings
        presets = model.presets
        history = model.history
    }

    public var body: some View {
        TabView(selection: $tab) {
            modelPane.tabItem { Label("Model", systemImage: "cpu") }.tag(SettingsTab.model)
            writingPane.tabItem { Label("Writing", systemImage: "text.book.closed") }.tag(SettingsTab.writing)
            shortcutPane.tabItem { Label("Shortcut", systemImage: "keyboard") }.tag(SettingsTab.shortcut)
            privacyPane.tabItem { Label("Privacy", systemImage: "lock.shield") }.tag(SettingsTab.privacy)
        }
        .frame(width: 620, height: 560)
        .onAppear {
            model.refreshSystemState()
            refreshKeyStatus()
        }
    }

    private var modelPane: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.provider) { _, _ in
                    settings.applyProviderDefaults()
                }
                if settings.provider != .demo {
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
                } else {
                    Text("The on-device demo rewrites text on this Mac. No key, no network, and nothing leaves the machine.")
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Local servers: start Ollama (`ollama serve`), llama.cpp (`llama-server`), or `mlx_lm.server`, then use their OpenAI-compatible /v1 URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .padding(8)
    }

    private var writingPane: some View {
        Form {
            Section("Presets") {
                Picker("Active", selection: $presets.selectedID) {
                    ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
                }
                ForEach(presets.presets) { preset in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text(preset.systemPrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
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
            Section("Always-on instructions") {
                TextField("Optional notes for every rewrite", text: $settings.customInstructions, axis: .vertical)
                    .lineLimit(3...8)
                Text("These stay on this Mac and are appended to the system prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                Toggle("Keep a local rewrite history", isOn: Binding(
                    get: { settings.historyEnabled },
                    set: { model.setHistoryEnabled($0) }
                ))
                Text(history.entries.isEmpty ? "No rewrites stored yet." : "\(history.entries.count) stored on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let latest = history.entries.first {
                    Button("Reopen last rewrite") {
                        model.restoreHistory(latest)
                    }
                }
                Button("Clear history", role: .destructive) {
                    history.clear()
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .padding(8)
    }

    private var shortcutPane: some View {
        Form {
            Section("Global shortcut") {
                ShortcutRecorderView(
                    keyCode: $settings.hotkeyKeyCode,
                    modifiers: $settings.hotkeyModifiers,
                    onApply: { model.configureHotkey() }
                )
                Text("Current: \(settings.hotkeyLabel). At least one modifier is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply shortcut") { model.configureHotkey() }
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
        }
        .padding(8)
    }

    private var privacyPane: some View {
        Form {
            Section("What Tajpo stores") {
                Text("Tajpo has no account or backend. The demo engine never leaves this Mac. A local Ollama / llama.cpp / MLX server keeps text on-device. Remote providers receive only the selection you send. API keys live in Keychain. History, if enabled, stays in local defaults and can be cleared.")
            }
            Section("Sandbox") {
                Text("The app is not App Sandboxed because Accessibility, a global hotkey, and clipboard fallback cannot work in the sandbox.")
            }
        }
        .padding(8)
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

private enum SettingsTab: Hashable {
    case model, writing, shortcut, privacy
}
