import Testing
@testable import TajpoCore

struct ScriptedLLMClient: LLMClient, Sendable {
    func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        let result = "rewritten \(text)"
        await onPartial(result)
        return RewriteResult(text: result, usage: TokenUsage(promptTokens: 4, completionTokens: 3))
    }

    func ping() async throws {}
}

@MainActor
@Test func generateReplaceAndUndoUseSelectionService() async throws {
    let selection = MockTextSelectionService(capturedText: "hello world")
    let keys = InMemoryAPIKeyStore(value: "sk-test")
    let settings = AppSettings()
    settings.provider = .openAI
    let model = AppModel(
        settings: settings,
        history: HistoryStore(defaults: UserDefaults(suiteName: "tajpo.tests.flow") ?? .standard, key: "flow", enabled: true),
        selection: selection,
        keyStore: keys,
        startAutomatically: false,
        makeClient: { _, _ in ScriptedLLMClient() }
    )
    await model.openInlineRewrite()
    #expect(model.originalText == "hello world")
    await model.runCurrentCapture()
    #expect(model.preview == "rewritten hello world")
    await model.applyPreview()
    #expect(selection.replacedText == "rewritten hello world")
    await model.undoLastReplacement()
    #expect(selection.replacedText == "hello world")
}

@MainActor
@Test func missingKeyIsReportedForOpenAI() async {
    let settings = AppSettings()
    settings.provider = .openAI
    let model = AppModel(
        settings: settings,
        selection: MockTextSelectionService(),
        keyStore: InMemoryAPIKeyStore(),
        startAutomatically: false,
        makeClient: { _, _ in ScriptedLLMClient() }
    )
    await model.openInlineRewrite()
    await model.runCurrentCapture()
    #expect(model.isError)
    #expect(model.status.contains("API key") || model.status.contains("key"))
}

@MainActor
@Test func repeatWithoutHistoryIsExplicit() async {
    let model = AppModel(
        selection: MockTextSelectionService(),
        keyStore: InMemoryAPIKeyStore(value: "sk-test"),
        startAutomatically: false,
        makeClient: { _, _ in ScriptedLLMClient() }
    )
    await model.repeatLastAction()
    #expect(model.status == TajpoError.nothingToRepeat.errorDescription)
}
