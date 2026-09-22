import Foundation

public enum RewriteAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case correct, improve, rewrite, shorten, changeTone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .correct: "Correct"
        case .improve: "Improve"
        case .rewrite: "Rewrite"
        case .shorten: "Shorten"
        case .changeTone: "Change Tone"
        }
    }

    /// Number used for the ⌘1–⌘5 shortcuts in the panel.
    public var shortcutNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

public enum RewriteTone: String, CaseIterable, Identifiable, Codable, Sendable {
    case professional, friendly, confident, casual

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct WritingPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var instructions: String

    public init(id: UUID = UUID(), name: String, instructions: String) {
        self.id = id
        self.name = name
        self.instructions = instructions
    }

    enum CodingKeys: String, CodingKey { case id, name, instructions, systemPrompt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        // Versions before 0.2 stored the text under `systemPrompt`.
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            ?? container.decode(String.self, forKey: .systemPrompt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(instructions, forKey: .instructions)
    }

    // Built-in presets have fixed IDs so a saved selection survives relaunches.
    public static let professional = WritingPreset(
        id: UUID(uuidString: "5A0C1E7E-8D2B-4C4E-9E0A-7A1B00000001")!,
        name: "Professional",
        instructions: "Use clear, direct wording. Prefer simple words. Avoid corporate jargon."
    )
    public static let casual = WritingPreset(
        id: UUID(uuidString: "5A0C1E7E-8D2B-4C4E-9E0A-7A1B00000002")!,
        name: "Casual",
        instructions: "Sound relaxed and human. Use natural contractions where the language supports them. Do not sound performative."
    )
    public static let builtIns: [WritingPreset] = [.professional, .casual]

    public var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }
}

/// The saved list of presets plus which one is active (`nil` means "None").
public struct PresetLibrary: Codable, Equatable, Sendable {
    public var presets: [WritingPreset]
    public var selectedID: UUID?

    public init(presets: [WritingPreset] = WritingPreset.builtIns, selectedID: UUID? = nil) {
        self.presets = presets
        self.selectedID = selectedID
    }

    public var selected: WritingPreset? {
        presets.first { $0.id == selectedID }
    }

    /// Restores a library from saved data, migrating older formats:
    /// built-in presets saved with random IDs get their fixed IDs back, and a
    /// selection that no longer exists falls back to "None".
    public static func restore(presetsData: Data?, selectedIDString: String?) -> PresetLibrary {
        var presets = WritingPreset.builtIns
        if let presetsData, let decoded = try? JSONDecoder().decode([WritingPreset].self, from: presetsData) {
            presets = decoded
        }
        var selected = selectedIDString.flatMap(UUID.init(uuidString:))
        for index in presets.indices {
            guard !presets[index].isBuiltIn,
                  let builtIn = WritingPreset.builtIns.first(where: { $0.name == presets[index].name }),
                  !presets.contains(where: { $0.id == builtIn.id }) else { continue }
            if selected == presets[index].id { selected = builtIn.id }
            presets[index].id = builtIn.id
        }
        if let current = selected, !presets.contains(where: { $0.id == current }) {
            selected = nil
        }
        return PresetLibrary(presets: presets, selectedID: selected)
    }

    public mutating func addPreset() -> WritingPreset {
        var name = "New Preset"
        var counter = 2
        while presets.contains(where: { $0.name == name }) {
            name = "New Preset \(counter)"
            counter += 1
        }
        let preset = WritingPreset(name: name, instructions: "")
        presets.append(preset)
        return preset
    }

    public mutating func remove(id: UUID) {
        presets.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    /// Re-adds any built-in preset that was deleted, keeping custom ones.
    public mutating func restoreBuiltIns() {
        for builtIn in WritingPreset.builtIns.reversed() {
            if let index = presets.firstIndex(where: { $0.id == builtIn.id }) {
                presets[index] = builtIn
            } else {
                presets.insert(builtIn, at: 0)
            }
        }
    }
}
