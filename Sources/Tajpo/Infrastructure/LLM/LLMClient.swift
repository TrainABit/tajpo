import Foundation

enum RewriteAction: String, CaseIterable, Identifiable, Sendable {
    case correct, improve, rewrite, shorten, changeTone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correct: "Correct"
        case .improve: "Improve"
        case .rewrite: "Rewrite"
        case .shorten: "Shorten"
        case .changeTone: "Tone"
        }
    }
}

enum RewriteTone: String, CaseIterable, Identifiable, Sendable {
    case professional, friendly, confident, casual

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct WritingPreset: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var systemPrompt: String

    static let professional = WritingPreset(
        name: "Professional",
        systemPrompt: "Use a clear, direct, professional tone. Prefer simple words. Avoid corporate jargon."
    )
    static let casual = WritingPreset(
        name: "Casual",
        systemPrompt: "Sound relaxed and human. Use natural contractions where the language supports them. Do not sound performative."
    )
}

enum PromptBuilder {
    static let antiSlop = "Avoid filler, canned openings, inflated language, fake enthusiasm, generic transitions, repetitive conclusions, and AI-sounding phrases. Do not use em dashes. Keep the author's voice and level of formality."

    static func systemPrompt(action: RewriteAction, tone: RewriteTone, preset: WritingPreset?) -> String {
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
            "Rewrite in a \(tone.rawValue) tone while preserving meaning and facts."
        }
        return [task, preset?.systemPrompt, antiSlop, "Preserve the original language. Do not add facts. Return only the final text without quotes or commentary."]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    static func temperature(for action: RewriteAction) -> Double {
        action == .correct ? 0 : 0.3
    }
}

protocol LLMClient: Sendable {
    func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> String
}
