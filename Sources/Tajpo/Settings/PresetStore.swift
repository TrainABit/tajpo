import Combine
import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [WritingPreset] {
        didSet { persistPresets() }
    }
    @Published var selectedID: UUID? {
        didSet { persistSelection() }
    }

    private var isRestoring = true

    init() {
        if let data = UserDefaults.standard.data(forKey: "writingPresets"),
           let value = try? JSONDecoder().decode([WritingPreset].self, from: data),
           !value.isEmpty {
            presets = value
        } else {
            presets = [.professional, .casual]
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

    var selected: WritingPreset? {
        presets.first { $0.id == selectedID }
    }

    func add(name: String, prompt: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }
        let item = WritingPreset(name: trimmedName, systemPrompt: trimmedPrompt)
        presets.append(item)
        selectedID = item.id
    }

    func remove(id: UUID) {
        presets.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = presets.first?.id
        }
    }

    func remove(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        if let selectedID, !presets.contains(where: { $0.id == selectedID }) {
            self.selectedID = presets.first?.id
        }
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
