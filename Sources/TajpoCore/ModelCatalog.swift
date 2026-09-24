import Foundation

public enum ModelCatalog {
    public static let defaultModel = "gpt-4.1-mini"

    /// Models offered in Settings. Anything else can be typed as a custom model.
    public static let suggested: [String] = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "gpt-5-mini", "gpt-5"]

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    /// Cost reassurance shown during setup. Based on gpt-4.1-mini list prices
    /// (~$0.40 / $1.60 per million input/output tokens, ~400 tokens per edit).
    /// Re-check against OpenAI's pricing page when `defaultModel` changes.
    public static let costHint = "A typical edit costs well under a tenth of a cent with the default model, so $5 of credit covers thousands of edits."

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
    public static let officialOpenAIHost = "api.openai.com"

    /// Checks a base URL typed by the user and removes a trailing slash.
    /// Plain HTTP is intentionally limited to literal loopback addresses;
    /// every remote provider must use HTTPS.
    public static func validateBaseURL(_ text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            throw TajpoError.invalidBaseURL
        }
        if scheme == "http", !isLoopbackHost(host) {
            throw TajpoError.invalidBaseURL
        }
        return url
    }

    /// The official OpenAI API is the only provider that receives Tajpo's
    /// OpenAI credential. This is intentionally an exact-origin check rather
    /// than a suffix check (`evilopenai.com` must never match).
    public static func isOfficialOpenAI(baseURL: URL) -> Bool {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host?.lowercased() == officialOpenAIHost,
              baseURL.port == nil || baseURL.port == 443,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else {
            return false
        }
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty || path == "v1"
    }

    /// The official OpenAI API needs a key; local OpenAI-compatible servers
    /// and custom HTTPS endpoints must never receive that credential.
    public static func requiresAPIKey(baseURL: URL) -> Bool {
        isOfficialOpenAI(baseURL: baseURL)
    }

    public static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    public static func chatCompletionsURL(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("chat/completions")
    }
}
