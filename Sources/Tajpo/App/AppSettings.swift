import Combine
import Foundation
import TajpoCore

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let model = "model"
        static let baseURL = "baseURL"
        static let projectID = "openAIProjectID"
        static let rewriteShortcut = "rewriteShortcut"
        static let repeatShortcut = "repeatShortcut"
        static let lastTone = "lastTone"
        static let recentInstructions = "recentInstructions"
        static let useDates = "useDates"
        static let totalUses = "totalUses"
        static let shownTips = "shownTips"
        // Versions before 0.2.
        static let legacyKeyCode = "hotkeyKeyCode"
        static let legacyModifiers = "hotkeyModifiers"
    }

    private let defaults: UserDefaults

    @Published private(set) var model: String
    @Published private(set) var baseURL: URL
    @Published private(set) var projectID: String
    @Published private(set) var rewriteShortcut: GlobalShortcut?
    @Published private(set) var repeatShortcut: GlobalShortcut?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        model = (try? ModelCatalog.validate(defaults.string(forKey: Key.model) ?? "")) ?? ModelCatalog.defaultModel
        baseURL = (try? ProviderSettings.validateBaseURL(defaults.string(forKey: Key.baseURL) ?? "")) ?? ModelCatalog.defaultBaseURL
        projectID = defaults.string(forKey: Key.projectID) ?? ""
        rewriteShortcut = Self.loadShortcut(defaults, key: Key.rewriteShortcut, fallback: Self.migratedLegacyShortcut(defaults))
        repeatShortcut = Self.loadShortcut(defaults, key: Key.repeatShortcut, fallback: .defaultRepeat)
    }

    var usesOpenAI: Bool { ProviderSettings.requiresAPIKey(baseURL: baseURL) }

    func setModel(_ text: String) throws {
        let value = try ModelCatalog.validate(text)
        model = value
        defaults.set(value, forKey: Key.model)
    }

    func setBaseURL(_ text: String) throws {
        let value = try ProviderSettings.validateBaseURL(text)
        baseURL = value
        defaults.set(value.absoluteString, forKey: Key.baseURL)
    }

    func setProjectID(_ text: String) {
        projectID = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(projectID, forKey: Key.projectID)
    }

    func shortcut(for action: HotkeyAction) -> GlobalShortcut? {
        action == .rewrite ? rewriteShortcut : repeatShortcut
    }

    /// Stores a shortcut that has already been registered successfully.
    func storeShortcut(_ shortcut: GlobalShortcut?, for action: HotkeyAction) {
        switch action {
        case .rewrite: rewriteShortcut = shortcut
        case .repeatLast: repeatShortcut = shortcut
        }
        let key = action == .rewrite ? Key.rewriteShortcut : Key.repeatShortcut
        // `null` means "disabled"; a missing key means "use the default".
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    var lastTone: RewriteTone {
        get { defaults.string(forKey: Key.lastTone).flatMap(RewriteTone.init(rawValue:)) ?? .professional }
        set { defaults.set(newValue.rawValue, forKey: Key.lastTone) }
    }

    /// Custom instructions the user ran recently, newest first.
    var recentInstructions: [String] {
        defaults.stringArray(forKey: Key.recentInstructions) ?? []
    }

    func rememberInstruction(_ instruction: String) {
        var list = recentInstructions.filter { $0.caseInsensitiveCompare(instruction) != .orderedSame }
        list.insert(instruction, at: 0)
        defaults.set(Array(list.prefix(6)), forKey: Key.recentInstructions)
        objectWillChange.send()
    }

    // MARK: Local usage counts (never leave the Mac)

    var totalUses: Int { defaults.integer(forKey: Key.totalUses) }

    /// Replacements and copies in the last 7 days.
    var usesThisWeek: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        return (defaults.array(forKey: Key.useDates) as? [Double] ?? []).filter { $0 >= cutoff }.count
    }

    func recordUse() {
        defaults.set(totalUses + 1, forKey: Key.totalUses)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        var dates = (defaults.array(forKey: Key.useDates) as? [Double] ?? []).filter { $0 >= cutoff }
        dates.append(Date().timeIntervalSince1970)
        defaults.set(Array(dates.suffix(500)), forKey: Key.useDates)
        objectWillChange.send()
    }

    func hasShownTip(_ id: String) -> Bool {
        (defaults.stringArray(forKey: Key.shownTips) ?? []).contains(id)
    }

    func markTipShown(_ id: String) {
        defaults.set((defaults.stringArray(forKey: Key.shownTips) ?? []) + [id], forKey: Key.shownTips)
    }

    private static func loadShortcut(_ defaults: UserDefaults, key: String, fallback: GlobalShortcut?) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return (try? JSONDecoder().decode(GlobalShortcut?.self, from: data)) ?? fallback
    }

    /// Keeps a shortcut chosen in an older version if it is still valid.
    private static func migratedLegacyShortcut(_ defaults: UserDefaults) -> GlobalShortcut {
        guard let code = defaults.object(forKey: Key.legacyKeyCode) as? Int,
              let modifiers = defaults.object(forKey: Key.legacyModifiers) as? Int else {
            return .defaultRewrite
        }
        let legacy = GlobalShortcut(keyCode: UInt32(code), modifiers: UInt32(modifiers))
        return (try? legacy.validate()) == nil ? .defaultRewrite : legacy
    }
}

@MainActor
final class PresetStore: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var library: PresetLibrary

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        library = PresetLibrary.restore(
            presetsData: defaults.data(forKey: "writingPresets"),
            selectedIDString: defaults.string(forKey: "selectedPresetID")
        )
        persist()
    }

    var presets: [WritingPreset] { library.presets }
    var selected: WritingPreset? { library.selected }
    var selectedID: UUID? { library.selectedID }

    func select(_ id: UUID?) {
        library.selectedID = id
        persist()
    }

    func update(_ preset: WritingPreset) {
        guard let index = library.presets.firstIndex(where: { $0.id == preset.id }) else { return }
        library.presets[index] = preset
        persist()
    }

    func add() -> WritingPreset {
        let preset = library.addPreset()
        persist()
        return preset
    }

    func remove(id: UUID) {
        library.remove(id: id)
        persist()
    }

    func restoreBuiltIns() {
        library.restoreBuiltIns()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(library.presets) {
            defaults.set(data, forKey: "writingPresets")
        }
        if let id = library.selectedID {
            defaults.set(id.uuidString, forKey: "selectedPresetID")
        } else {
            defaults.removeObject(forKey: "selectedPresetID")
        }
    }
}
