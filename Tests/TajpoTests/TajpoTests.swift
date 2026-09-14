import Testing
@testable import Tajpo

@Test func actionTitlesExist() { #expect(RewriteAction.allCases.allSatisfy { !$0.title.isEmpty }) }
@Test func improvePromptPreservesLanguage() { #expect(PromptBuilder.systemPrompt(action: .improve, tone: .friendly).contains("Preserve the original language")) }
@Test func tonePromptUsesTone() { #expect(PromptBuilder.systemPrompt(action: .changeTone, tone: .confident).contains("confident")) }
@Test func promptsForbidInventedFacts() { #expect(PromptBuilder.systemPrompt(action: .rewrite, tone: .casual).contains("Do not add facts")) }
