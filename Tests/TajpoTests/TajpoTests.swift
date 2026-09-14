import Testing
@testable import Tajpo

@Test func correctionPromptIsNarrow() { let p = PromptBuilder.systemPrompt(action: .correct, tone: .casual, preset: nil); #expect(p.contains("Correct only")); #expect(p.contains("Do not change meaning")) }
@Test func antiSlopIsAlwaysApplied() { for action in RewriteAction.allCases { #expect(PromptBuilder.systemPrompt(action: action, tone: .friendly, preset: nil).contains(PromptBuilder.antiSlop)) } }
@Test func customPresetIsIncluded() { let preset = WritingPreset(name: "House", systemPrompt: "Use short sentences."); #expect(PromptBuilder.systemPrompt(action: .rewrite, tone: .casual, preset: preset).contains("Use short sentences.")) }
@Test func promptsPreserveLanguageAndFacts() { let p = PromptBuilder.systemPrompt(action: .improve, tone: .professional, preset: nil); #expect(p.contains("Preserve the original language")); #expect(p.contains("Do not add facts")) }
