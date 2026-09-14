import Testing
@testable import Tajpo

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
    let prompt = PromptBuilder.systemPrompt(action: .changeTone, tone: .confident, preset: nil)
    #expect(prompt.contains("confident"))
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
}

@Test func emptySelectionIsRejected() {
    #expect(throws: TajpoError.noSelection) {
        try SelectionValidator.validate("   \n\t")
    }
}

@Test func oversizedSelectionIsRejected() {
    #expect(throws: TajpoError.textTooLarge) {
        try SelectionValidator.validate(String(repeating: "a", count: SelectionValidator.maximumCharacters + 1))
    }
}

@Test func validSelectionIsAccepted() throws {
    try SelectionValidator.validate("Hello there")
}

@Test func emptyAPIKeyIsRejected() {
    #expect(throws: TajpoError.missingAPIKey) {
        try APIKeyValidator.validate("   ")
    }
}

@Test func apiKeyIsTrimmed() throws {
    #expect(try APIKeyValidator.validate("  sk-test  ") == "sk-test")
}

@Test @MainActor func unknownHotkeyTitleDoesNotCrash() {
    #expect(AppSettings.keyTitle(for: 999) == "?")
    #expect(AppSettings.keyTitle(for: AppSettings.keys[0].code) == "T")
}

@Test func openAIErrorParserReadsMessage() {
    let body = #"{"error":{"message":"Incorrect API key provided"}}"#
    #expect(OpenAIErrorParser.message(from: body, status: 401) == "Incorrect API key provided")
}

@Test func openAIErrorParserFallsBackToStatus() {
    #expect(OpenAIErrorParser.message(from: "not-json", status: 502) == "HTTP 502")
}
