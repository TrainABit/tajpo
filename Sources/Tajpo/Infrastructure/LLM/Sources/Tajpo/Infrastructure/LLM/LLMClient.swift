import Foundation

enum RewriteInstruction: String, Codable, Sendable {
    case improve
    case concise
    case professional

    var prompt: String {
        switch self {
        case .improve: "Improve clarity, grammar, and flow. Preserve meaning, language, and tone. Return only the rewritten text."
        case .concise: "Make the text concise. Preserve meaning and language. Return only the rewritten text."
        case .professional: "Rewrite in a natural professional tone. Preserve meaning and language. Return only the rewritten text."
        }
    }
}

protocol LLMClient: Sendable {
    func rewrite(_ text: String, instruction: RewriteInstruction) async throws -> String
}
