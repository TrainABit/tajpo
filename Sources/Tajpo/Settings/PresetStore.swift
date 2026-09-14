import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [WritingPreset] { didSet { save() } }
    @Published var selectedID: UUID?
    init() {
        if let data = UserDefaults.standard.data(forKey: "writingPresets"), let value = try? JSONDecoder().decode([WritingPreset].self, from: data) { presets = value }
        else { presets = [.professional, .casual] }
        selectedID = presets.first?.id
    }
    var selected: WritingPreset? { presets.first { $0.id == selectedID } }
    func add(name: String, prompt: String) { guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; let item = WritingPreset(name: name, systemPrompt: prompt); presets.append(item); selectedID = item.id }
    func remove(at offsets: IndexSet) { presets.remove(atOffsets: offsets); if !presets.contains(where: { $0.id == selectedID }) { selectedID = presets.first?.id } }
    private func save() { if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: "writingPresets") } }
}
