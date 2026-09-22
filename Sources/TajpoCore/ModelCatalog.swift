import Foundation

public enum ModelCatalog {
    public static let defaultModel = "gpt-4.1-mini"

    /// Models offered in Settings. Anything else can be typed as a custom model.
    public static let suggested: [String] = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "gpt-5-mini", "gpt-5"]

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    /// Reasoning models (o-series, GPT-5 family except the chat variants) only
    /// accept the default temperature, so Tajpo must not send one.
    public static func isReasoningModel(_ model: String) -> Bool {
        let name = normalized(model)
        if name.hasPrefix("gpt-5") { return !name.contains("chat") }
        return ["o1", "o3", "o4"].contains { name == $0 || name.hasPrefix($0 + "-") }
    }

    /// Maximum output tokens, used to refuse selections that cannot be
    /// returned in full. Unknown models get a conservative limit.
    public static func outputTokenLimit(for model: String) -> Int {
        let name = normalized(model)
        if name.hasPrefix("gpt-5") || isReasoningModel(name) { return 100_000 }
        if name.hasPrefix("gpt-4.1") { return 32_768 }
        return 16_384
    }

    public static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Checks a model name typed by the user.
    public static func validate(_ model: String) throws -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TajpoError.invalidModel("The model name is empty.") }
        guard !trimmed.contains(where: \.isWhitespace) else {
            throw TajpoError.invalidModel("Model names cannot contain spaces.")
        }
        return trimmed
    }
}

public enum ProviderSettings {
    /// Checks a base URL typed by the user and removes a trailing slash.
    public static func validateBaseURL(_ text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw TajpoError.invalidBaseURL
        }
        return url
    }

    /// The official OpenAI API needs a key; local OpenAI-compatible servers
    /// (Ollama, LM Studio, llama.cpp) usually do not.
    public static func requiresAPIKey(baseURL: URL) -> Bool {
        baseURL.host?.lowercased().hasSuffix("openai.com") ?? true
    }

    public static func chatCompletionsURL(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("chat/completions")
    }
}
