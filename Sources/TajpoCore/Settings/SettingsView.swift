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
    @State private var historyQuery = ""
    @State private var confirmingErase = false
    @State private var eraseMessage = ""
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
                if let lastCheck = model.lastUpdateCheck {
                    Text("Last checked: \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Section("Length") {
                Picker("Default length", selection: $model.length) {
                    ForEach(RewriteLength.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: model.length) { _, value in
                    settings.rewriteLength = value
                }
            }
            Section("Always-on instructions") {
                TextField("Optional notes for every rewrite", text: $settings.customInstructions, axis: .vertical)
                    .lineLimit(3...8)
                Text("These stay on this Mac. The demo engine honors “never use the word …” and “no exclamation”. Remote models receive the full note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                Toggle("Record new rewrite history", isOn: Binding(
                    get: { settings.historyEnabled },
                    set: { model.setHistoryEnabled($0) }
                ))
                Text("Off stops recording new entries and keeps the existing ones. Clear History is the only action that removes them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $historyQuery)
                Text(history.entries.isEmpty ? "No rewrites stored yet." : "\(history.filtered(query: historyQuery).count) of \(history.entries.count) shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(history.filtered(query: historyQuery).prefix(8)) { entry in
                    HStack(alignment: .top) {
                        Button {
                            model.restoreHistory(entry)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.action.capitalized)
                                Text(entry.result)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button {
                            model.deleteHistory(entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .tint(TajpoTheme.terracotta)
                        .help("Delete this history entry")
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
            Section("Erase everything") {
                Text("Removes history, presets, settings, onboarding state, and every saved API key from this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erase All Data…", role: .destructive) {
                    confirmingErase = true
                }
                .confirmationDialog(
                    "Erase all Tajpo data on this Mac?",
                    isPresented: $confirmingErase,
                    titleVisibility: .visible
                ) {
                    Button("Erase All Data", role: .destructive) {
                        model.eraseAllData()
                        eraseMessage = "All local data erased."
                        refreshKeyStatus()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("History, presets, settings, and saved API keys are removed. This cannot be undone.")
                }
                if !eraseMessage.isEmpty {
                    Text(eraseMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
