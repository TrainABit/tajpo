import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var presets: PresetStore
    @State private var apiKey = ""
    @State private var message = ""
    @State private var presetName = ""
    @State private var presetPrompt = ""
    private let keyStore = KeychainAPIKeyStore()

    init(model: AppModel) {
        self.model = model
        settings = model.settings
        presets = model.presets
    }

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $apiKey)
                TextField("Model", text: $settings.model)
                HStack {
                    Button("Save key") { saveKey() }
                    Button("Remove key", role: .destructive) { removeKey() }
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Global shortcut") {
                Picker("Key", selection: $settings.hotkeyKeyCode) {
                    ForEach(AppSettings.keys, id: \.code) { Text($0.title).tag($0.code) }
                }
                Toggle("Command (⌘)", isOn: binding(UInt32(cmdKey)))
                Toggle("Option (⌥)", isOn: binding(UInt32(optionKey)))
                Toggle("Control (⌃)", isOn: binding(UInt32(controlKey)))
                Toggle("Shift (⇧)", isOn: binding(UInt32(shiftKey)))
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
                Text("Tajpo needs Accessibility access to read and replace selected text.")
                Button("Request Accessibility access") { model.requestAccessibility() }
            }
            Section("Privacy") {
                Text("Text leaves your Mac only in direct requests to OpenAI using your key. Tajpo has no backend and does not log text.")
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear { refreshKeyStatus() }
    }

    private func binding(_ flag: UInt32) -> Binding<Bool> {
        Binding(
            get: { settings.hotkeyModifiers & flag != 0 },
            set: { enabled in
                settings.hotkeyModifiers = enabled
                    ? settings.hotkeyModifiers | flag
                    : settings.hotkeyModifiers & ~flag
            }
        )
    }

    private func saveKey() {
        do {
            try keyStore.save(APIKeyValidator.validate(apiKey))
            apiKey = ""
            message = "Saved in Keychain."
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try keyStore.delete()
            apiKey = ""
            message = "Removed."
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshKeyStatus() {
        if let key = try? keyStore.load(), let key, !key.isEmpty {
            message = "A key is already saved in Keychain."
        }
    }
}
