import Testing
@testable import TajpoCore

@Test func correctionPromptIsNarrow() {
    let prompt = PromptBuilder.systemPrompt(action: .correct, tone: .casual, preset: nil)
    #expect(prompt.contains("Correct only"))
    #expect(prompt.contains("Do not change meaning"))
}

@Test func antiSlopIsAlwaysApplied() {
    for action in RewriteAction.allCases {
        #expect(PromptBuilder.systemPrompt(action: action, tone: .friendly, preset: nil).contains(PromptBuilder.antiSlop))
    }
}

@Test func customPresetIsIncluded() {
    let preset = WritingPreset(name: "House", systemPrompt: "Use short sentences.")
    #expect(PromptBuilder.systemPrompt(action: .rewrite, tone: .casual, preset: preset).contains("Use short sentences."))
}

@Test func promptsPreserveLanguageAndFacts() {
    let prompt = PromptBuilder.systemPrompt(action: .improve, tone: .professional, preset: nil)
    #expect(prompt.contains("Preserve the original language"))
    #expect(prompt.contains("Do not add facts"))
}

@Test func changeTonePromptIncludesRequestedTone() {
    let prompt = PromptBuilder.systemPrompt(action: .changeTone, tone: .confident, preset: WritingPreset.professional)
    #expect(prompt.contains("confident"))
    #expect(prompt.contains("must not override the requested confident tone"))
}

@Test func correctionUsesZeroTemperature() {
    #expect(PromptBuilder.temperature(for: .correct) == 0)
    #expect(PromptBuilder.temperature(for: .improve) == 0.3)
}

@Test func rewriteActionTitlesAreStable() {
    #expect(RewriteAction.correct.title == "Correct")
    #expect(RewriteAction.improve.title == "Improve")
    #expect(RewriteAction.rewrite.title == "Rewrite")
    #expect(RewriteAction.shorten.title == "Shorten")
    #expect(RewriteAction.changeTone.title == "Tone")
    #expect(RewriteAction.expand.title == "Expand")
    #expect(RewriteAction.simplify.title == "Simplify")
    #expect(RewriteAction.bullets.title == "Bullets")
    #expect(RewriteAction.continueWriting.title == "Continue")
}

@Test func expandAndBulletPromptsAreSpecific() {
    #expect(PromptBuilder.systemPrompt(action: .expand, tone: .casual, preset: nil).contains("Do not invent facts"))
    #expect(PromptBuilder.systemPrompt(action: .bullets, tone: .casual, preset: nil).contains("bullet list"))
}

@Test func customInstructionsAreAppended() {
    let prompt = PromptBuilder.systemPrompt(
        action: .rewrite,
        tone: .casual,
        preset: nil,
        customInstructions: "Never use the word synergy.",
        length: .shorter
    )
    #expect(prompt.contains("Never use the word synergy."))
    #expect(prompt.contains("shorter than the source"))
}
