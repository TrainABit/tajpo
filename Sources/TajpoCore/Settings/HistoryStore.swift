import Combine
import Foundation

public struct RewriteHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var action: String
    public var tone: String
    public var original: String
    public var result: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        action: String,
        tone: String,
        original: String,
        result: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
        self.tone = tone
        self.original = original
        self.result = result
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
        if enabled,
           let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode([RewriteHistoryEntry].self, from: data) {
            entries = value
        } else {
            entries = []
        }
        isRestoring = false
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled {
            clear()
        }
    }

    public func record(action: RewriteAction, tone: RewriteTone, original: String, result: String) {
        guard enabled else { return }
        let entry = RewriteHistoryEntry(
            action: action.rawValue,
            tone: tone.rawValue,
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

    public func filtered(query: String, action: String? = nil) -> [RewriteHistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let action, entry.action != action { return false }
            if needle.isEmpty { return true }
            return "\(entry.original) \(entry.result) \(entry.action) \(entry.tone)".lowercased().contains(needle)
        }
    }

    private func persist() {
        guard !isRestoring, enabled else { return }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
