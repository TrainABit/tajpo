import Foundation

public enum RewriteAction: String, CaseIterable, Identifiable, Sendable {
    case correct, improve, rewrite, shorten, changeTone, expand, simplify, bullets, continueWriting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .correct: "Correct"
        case .improve: "Improve"
        case .rewrite: "Rewrite"
        case .shorten: "Shorten"
        case .changeTone: "Tone"
        case .expand: "Expand"
        case .simplify: "Simplify"
        case .bullets: "Bullets"
        case .continueWriting: "Continue"
        }
    }

    public var subtitle: String {
        switch self {
        case .correct: "Grammar and spelling only"
        case .improve: "Clearer, same meaning"
        case .rewrite: "Fresh wording"
        case .shorten: "Keep the point, cut words"
        case .changeTone: "Same facts, new voice"
        case .expand: "Add a little room"
        case .simplify: "Shorter words"
        case .bullets: "Turn it into a list"
        case .continueWriting: "Write the next beat"
        }
    }

    public var shortcutDigit: String {
        String((Self.allCases.firstIndex(of: self) ?? 0) + 1)
    }
}

public enum RewriteTone: String, CaseIterable, Identifiable, Sendable {
    case professional, friendly, confident, casual

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum RewriteLength: String, CaseIterable, Identifiable, Sendable {
    case shorter, same, longer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shorter: "Shorter"
        case .same: "Same length"
        case .longer: "Longer"
        }
    }
}

public struct WritingPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var systemPrompt: String

    public init(id: UUID = UUID(), name: String, systemPrompt: String) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
    }

    public static let professional = WritingPreset(
        name: "Professional",
        systemPrompt: "Use a clear, direct, professional tone. Prefer simple words. Avoid corporate jargon."
    )
    public static let casual = WritingPreset(
        name: "Casual",
        systemPrompt: "Sound relaxed and human. Use natural contractions where the language supports them. Do not sound performative."
    )
    public static let concise = WritingPreset(
        name: "Concise",
        systemPrompt: "Prefer short sentences and concrete verbs. Cut anything that does not carry information."
    )
    public static let warm = WritingPreset(
        name: "Warm",
        systemPrompt: "Be considerate and plain. Keep warmth in the voice without cheerleading or exclamation marks."
    )
}

public enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    case demo
    case openAI
    case localCompatible

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .demo: "On-device demo"
        case .openAI: "OpenAI"
        case .localCompatible: "Local server (Ollama, llama.cpp, MLX)"
        }
    }

    public var requiresAPIKey: Bool {
        self == .openAI
    }

    public var defaultBaseURL: String {
        switch self {
        case .demo: ""
        case .openAI: "https://api.openai.com/v1"
        case .localCompatible: "http://127.0.0.1:11434/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .demo: "tajpo-demo"
        case .openAI: "gpt-4o-mini"
        case .localCompatible: "llama3.2"
        }
    }
}

public enum LLMAuthStyle: String, CaseIterable, Identifiable, Sendable {
    case bearer
    case apiKeyHeader
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bearer: "Bearer token"
        case .apiKeyHeader: "api-key header (Azure)"
        case .none: "No key"
        }
    }
}

public struct LLMEndpoint: Equatable, Sendable {
    public var provider: LLMProvider
    public var model: String
    public var baseURL: String
    public var apiVersion: String
    public var authStyle: LLMAuthStyle

    public init(
        provider: LLMProvider,
        model: String,
        baseURL: String,
        apiVersion: String = "",
        authStyle: LLMAuthStyle = .bearer
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.authStyle = authStyle
    }

    public func chatCompletionsURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { throw TajpoError.invalidEndpoint }
        if !apiVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encodedVersion = apiVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiVersion
            let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            guard let url = URL(string: "\(trimmed)/openai/deployments/\(encodedModel)/chat/completions?api-version=\(encodedVersion)") else {
                throw TajpoError.invalidEndpoint
            }
            return url
        }
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw TajpoError.invalidEndpoint
        }
        return url
    }

    public func modelsURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !apiVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encodedVersion = apiVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiVersion
            guard let url = URL(string: "\(trimmed)/openai/models?api-version=\(encodedVersion)") else {
                throw TajpoError.invalidEndpoint
            }
            return url
        }
        guard let url = URL(string: "\(trimmed)/models") else { throw TajpoError.invalidEndpoint }
        return url
    }

    /// HTTPS is required before an API key may be attached to a request.
    /// Plain HTTP is tolerated only for loopback servers (local Ollama, llama.cpp, MLX).
    public func validateTransportSecurity(apiKey: String) throws {
        guard !apiKey.isEmpty, authStyle != .none else { return }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw TajpoError.invalidEndpoint
        }
        guard scheme != "https" else { return }
        let host = (url.host ?? "").lowercased()
        guard Self.loopbackHosts.contains(host) else { throw TajpoError.insecureEndpoint }
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]
}

public struct TokenUsage: Equatable, Sendable {
    /// Optional because streaming usage events may report only one side; cost labels require both.
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public var totalTokens: Int? {
        guard let promptTokens, let completionTokens else { return nil }
        return promptTokens + completionTokens
    }

    /// A cost label is only meaningful when both prompt and completion tokens are present.
    public var isComplete: Bool { totalTokens != nil }
}

public struct RewriteResult: Equatable, Sendable {
    public var text: String
    public var usage: TokenUsage?
    /// Set when the model stopped for a reason other than a natural stop (e.g. max_tokens).
    public var finishReason: RewriteFinishReason?

    public init(text: String, usage: TokenUsage? = nil, finishReason: RewriteFinishReason? = nil) {
        self.text = text
        self.usage = usage
        self.finishReason = finishReason
    }
}

public enum RewriteFinishReason: String, Equatable, Sendable {
    case truncated
    case contentFiltered
    case other

    public var isNoteworthy: Bool { self != .other }

    public static func parse(_ raw: String?) -> RewriteFinishReason? {
        switch raw {
        case "length", "max_tokens": return .truncated
        case "content_filter": return .contentFiltered
        case nil, "stop", "": return nil
        default: return .other
        }
    }
}

public enum PromptBuilder {
    public static let antiSlop = "Avoid filler, canned openings, inflated language, fake enthusiasm, generic transitions, repetitive conclusions, and AI-sounding phrases. Do not use em dashes. Keep the author's voice and level of formality."

    public static func systemPrompt(
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        customInstructions: String? = nil,
        length: RewriteLength = .same
    ) -> String {
        let task: String = switch action {
        case .correct:
            "Correct only grammar, spelling, and punctuation. Do not change meaning, tone, structure, or word choice unless required for correctness."
        case .improve:
            "Improve clarity and flow while preserving meaning and voice."
        case .rewrite:
            "Rewrite naturally while preserving meaning and all facts."
        case .shorten:
            "Make it shorter without losing key information."
        case .changeTone:
            "Rewrite in a \(tone.rawValue) tone while preserving meaning and facts. The requested tone wins if any other style note conflicts."
        case .expand:
            "Expand slightly with one or two clarifying sentences. Do not invent facts, numbers, or names."
        case .simplify:
            "Rewrite with shorter, more common words. Keep meaning and facts."
        case .bullets:
            "Turn the text into a tight bullet list. Keep every fact. Do not add a heading unless the source already has one."
        case .continueWriting:
            "Return the COMPLETE text: first the user's passage verbatim, unchanged, then exactly one continuation of one or two sentences in the same voice. Never return only the continuation. Do not add facts that are not implied."
        }
        let presetClause = preset.map { preset in
            if action == .changeTone {
                "Style notes (must not override the requested \(tone.rawValue) tone): \(preset.systemPrompt)"
            } else {
                preset.systemPrompt
            }
        }
        let custom = customInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let customClause: String? = if let custom, !custom.isEmpty {
            "Extra instructions from the user: \(custom)"
        } else {
            nil
        }
        let lengthClause: String? = switch length {
        case .shorter: "Make the result shorter than the source without losing key facts."
        case .longer: "Make the result a little longer with one clarifying sentence. Do not invent facts."
        case .same: nil
        }
        return [task, presetClause, customClause, lengthClause, antiSlop, "Preserve the original language. Do not add facts. Return only the final text without quotes or commentary."]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    public static func temperature(for action: RewriteAction) -> Double {
        switch action {
        case .correct, .bullets: 0
        case .improve, .simplify, .shorten: 0.3
        case .changeTone, .expand, .rewrite, .continueWriting: 0.5
        }
    }
}

public protocol LLMClient: Sendable {
    func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult

    func ping() async throws
}

public enum TokenCost {
    public static func estimateUSD(model: String, usage: TokenUsage) -> Double? {
        guard let rates = rates[model],
              let prompt = usage.promptTokens,
              let completion = usage.completionTokens else { return nil }
        return (Double(prompt) * rates.inputPerMillion + Double(completion) * rates.outputPerMillion) / 1_000_000
    }

    /// Returns an empty string when the usage event is partial: a zero-filled token count
    /// would render a misleading cost label.
    public static func label(model: String, usage: TokenUsage) -> String {
        guard let total = usage.totalTokens else { return "" }
        let tokens = "\(total) tokens"
        if let usd = estimateUSD(model: model, usage: usage) {
            return String(format: "%@ · about $%.4f", tokens, usd)
        }
        return tokens
    }

    private static let rates: [String: (inputPerMillion: Double, outputPerMillion: Double)] = [
        "gpt-4o-mini": (0.15, 0.60),
        "gpt-4o": (2.50, 10.00),
        "gpt-4.1-mini": (0.40, 1.60),
        "gpt-4.1": (2.00, 8.00)
    ]
}

public enum RetryPolicy {
    public static let maxAttempts = 3

    public static func delay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, 20)
        }
        return min(pow(2, Double(attempt)), 8)
    }

    /// Parses a Retry-After header in either of its HTTP forms:
    /// a delay in seconds ("3") or an absolute HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT").
    public static func retryAfter(from header: String?) -> TimeInterval? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(trimmed) {
            return seconds >= 0 ? seconds : nil
        }
        guard let date = httpDate(from: trimmed) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    private static func httpDate(from string: String) -> Date? {
        if let date = httpDateFormatter.date(from: string) { return date }
        // RFC 850 ("Monday, 02-Jan-06 15:04:05 GMT") and asctime forms are rare but legal.
        let alternates = ["EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"]
        for format in alternates {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
