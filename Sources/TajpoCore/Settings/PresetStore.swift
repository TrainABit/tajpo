import Combine
import Foundation

@MainActor
public final class PresetStore: ObservableObject {
    @Published public var presets: [WritingPreset] {
        didSet { persistPresets() }
    }
    @Published public var selectedID: UUID? {
        didSet { persistSelection() }
    }

    private var isRestoring = true

    public init() {
        if let data = UserDefaults.standard.data(forKey: "writingPresets"),
           let value = try? JSONDecoder().decode([WritingPreset].self, from: data),
           !value.isEmpty {
            presets = value
        } else {
            presets = [.professional, .casual, .concise, .warm]
        }

        if let raw = UserDefaults.standard.string(forKey: "selectedPresetID"),
           let id = UUID(uuidString: raw),
           presets.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = presets.first?.id
        }
        isRestoring = false
    }

    public var selected: WritingPreset? {
        presets.first { $0.id == selectedID }
    }

    public func add(name: String, prompt: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }
        let item = WritingPreset(name: trimmedName, systemPrompt: trimmedPrompt)
        presets.append(item)
        selectedID = item.id
    }

    public func remove(id: UUID) {
        presets.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = presets.first?.id
        }
    }

    /// Restores the factory presets. Used by "Erase All Data".
    public func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: "writingPresets")
        UserDefaults.standard.removeObject(forKey: "selectedPresetID")
        presets = [.professional, .casual, .concise, .warm]
        selectedID = presets.first?.id
    }

    private func persistPresets() {
        guard !isRestoring, let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: "writingPresets")
    }

    private func persistSelection() {
        guard !isRestoring else { return }
        if let selectedID {
            UserDefaults.standard.set(selectedID.uuidString, forKey: "selectedPresetID")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedPresetID")
        }
    }
}
