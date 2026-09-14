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

protocol LLMClient {
    func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone) async throws -> String
}
