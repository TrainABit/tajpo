import Foundation

enum RewriteAction: String, CaseIterable, Identifiable {
    case improve, rewrite, shorten, changeTone
    var id: String { rawValue }
    var title: String { switch self { case .improve: "Improve"; case .rewrite: "Rewrite"; case .shorten: "Shorten"; case .changeTone: "Change tone" } }
}

enum RewriteTone: String, CaseIterable, Identifiable {
    case professional, friendly, confident, casual
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PromptBuilder {
    static func systemPrompt(action: RewriteAction, tone: RewriteTone) -> String {
        let task: String = switch action {
        case .improve: "Improve grammar, clarity, and flow."
        case .rewrite: "Rewrite naturally while preserving the meaning."
        case .shorten: "Make it substantially shorter without losing key information."
        case .changeTone: "Rewrite it in a \(tone.rawValue) tone."
        }
        return "\(task) Preserve the original language unless asked otherwise. Do not add facts. Return only the final text, without quotes or commentary."
    }
}

protocol LLMClient {
    func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone, onPartial: @escaping @MainActor (String) -> Void) async throws -> String
}
