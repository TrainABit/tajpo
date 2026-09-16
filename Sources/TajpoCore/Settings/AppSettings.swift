import Carbon
import Combine
import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    @Published public var provider: LLMProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") }
    }
    @Published public var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }
    @Published public var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }
    @Published public var apiVersion: String {
        didSet { UserDefaults.standard.set(apiVersion, forKey: "apiVersion") }
    }
    @Published public var authStyle: LLMAuthStyle {
        didSet { UserDefaults.standard.set(authStyle.rawValue, forKey: "authStyle") }
    }
    @Published public var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }
    @Published public var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers") }
    }
    @Published public var githubRepository: String {
        didSet { UserDefaults.standard.set(githubRepository, forKey: "githubRepository") }
    }
    @Published public var customInstructions: String {
        didSet { UserDefaults.standard.set(customInstructions, forKey: "customInstructions") }
    }
    @Published public var historyEnabled: Bool {
        didSet { UserDefaults.standard.set(historyEnabled, forKey: "historyEnabled") }
    }
    @Published public var rewriteLength: RewriteLength {
        didSet { UserDefaults.standard.set(rewriteLength.rawValue, forKey: "rewriteLength") }
    }

    public init() {
        let storedProvider = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .demo
        provider = storedProvider
        model = UserDefaults.standard.string(forKey: "model") ?? storedProvider.defaultModel
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? storedProvider.defaultBaseURL
        apiVersion = UserDefaults.standard.string(forKey: "apiVersion") ?? ""
        authStyle = LLMAuthStyle(rawValue: UserDefaults.standard.string(forKey: "authStyle") ?? "") ?? (storedProvider == .openAI ? .bearer : .none)
        hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_T)
        hotkeyModifiers = UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? (optionKey | cmdKey))
        githubRepository = UserDefaults.standard.string(forKey: "githubRepository") ?? "TrainABit/tajpo"
        customInstructions = UserDefaults.standard.string(forKey: "customInstructions") ?? ""
        if UserDefaults.standard.object(forKey: "historyEnabled") == nil {
            historyEnabled = true
        } else {
            historyEnabled = UserDefaults.standard.bool(forKey: "historyEnabled")
        }
        rewriteLength = RewriteLength(rawValue: UserDefaults.standard.string(forKey: "rewriteLength") ?? "") ?? .same
    }

    public var hotkeySpec: HotkeySpec {
        HotkeySpec(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    public var hotkeyLabel: String { hotkeySpec.label }

    public var endpoint: LLMEndpoint {
        LLMEndpoint(
            provider: provider,
            model: model,
            baseURL: baseURL,
            apiVersion: apiVersion,
            authStyle: authStyle
        )
    }

    public func applyProviderDefaults() {
        model = provider.defaultModel
        baseURL = provider.defaultBaseURL
        authStyle = provider == .openAI ? .bearer : .none
        if provider != .openAI {
            apiVersion = ""
        }
    }

    public func effectivePreset(_ selected: WritingPreset?) -> WritingPreset? {
        let extra = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return selected }
        if let selected {
            return WritingPreset(
                id: selected.id,
                name: selected.name,
                systemPrompt: selected.systemPrompt + " " + extra
            )
        }
        return WritingPreset(name: "Custom", systemPrompt: extra)
    }
}
