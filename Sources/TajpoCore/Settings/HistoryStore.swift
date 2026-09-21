import Combine
import Foundation

public struct RewriteHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var action: String
    public var tone: String
    /// Entries written before length was recorded decode with this default.
    public var length: String
    public var original: String
    public var result: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        action: String,
        tone: String,
        length: String = RewriteLength.same.rawValue,
        original: String,
        result: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
        self.tone = tone
        self.length = length
        self.original = original
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, action, tone, length, original, result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        action = try container.decode(String.self, forKey: .action)
        tone = try container.decode(String.self, forKey: .tone)
        length = try container.decodeIfPresent(String.self, forKey: .length) ?? RewriteLength.same.rawValue
        original = try container.decode(String.self, forKey: .original)
        result = try container.decode(String.self, forKey: .result)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(action, forKey: .action)
        try container.encode(tone, forKey: .tone)
        try container.encode(length, forKey: .length)
        try container.encode(original, forKey: .original)
        try container.encode(result, forKey: .result)
    }
}

@MainActor
public final class HistoryStore: ObservableObject {
    public static let maximumEntries = 40

    @Published public var entries: [RewriteHistoryEntry] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key: String
    private var isRestoring = true
    private var enabled: Bool

    public init(defaults: UserDefaults = .standard, key: String = "rewriteHistory", enabled: Bool = true) {
        self.defaults = defaults
        self.key = key
        self.enabled = enabled
        // Entries load regardless of the recording toggle: disabling recording
        // is non-destructive, and Clear must survive a reload while disabled.
        if let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode([RewriteHistoryEntry].self, from: data) {
            entries = value
        } else {
            entries = []
        }
        isRestoring = false
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        // Non-destructive: turning recording off keeps existing entries (and
        // their persistence) until the user explicitly clears history.
    }

    public func record(action: RewriteAction, tone: RewriteTone, length: RewriteLength = .same, original: String, result: String) {
        guard enabled else { return }
        let entry = RewriteHistoryEntry(
            action: action.rawValue,
            tone: tone.rawValue,
            length: length.rawValue,
            original: original,
            result: result
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntries {
            entries = Array(entries.prefix(Self.maximumEntries))
        }
    }

    public func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }

    /// Removes a single entry by id and persists the change.
    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func filtered(query: String, action: String? = nil) -> [RewriteHistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let action, entry.action != action { return false }
            if needle.isEmpty { return true }
            return "\(entry.original) \(entry.result) \(entry.action) \(entry.tone)".lowercased().contains(needle)
        }
    }

    private func persist() {
        // Persist regardless of the recording toggle so a Clear performed while
        // recording is disabled is not resurrected on the next launch.
        guard !isRestoring else { return }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
