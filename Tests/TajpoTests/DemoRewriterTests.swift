import Testing
@testable import TajpoCore

@Test func demoCorrectsTyposAndCapitalization() {
    let rewriter = DemoRewriter()
    #expect(rewriter.rewrite("teh quick brown fox", action: .correct, tone: .casual) == "The quick brown fox")
    #expect(rewriter.rewrite("i can do this", action: .correct, tone: .casual) == "I can do this")
}

@Test func demoConfidentToneStripsHedgesAndFiller() {
    let rewriter = DemoRewriter()
    #expect(rewriter.rewrite("i think we should really just go", action: .changeTone, tone: .confident) == "We should go")
}

@Test func demoSimplifiesLatinateWords() {
    let rewriter = DemoRewriter()
    #expect(rewriter.rewrite("Utilize the enviroment in order to commence", action: .simplify, tone: .professional) == "Use the environment in order to start")
}

@Test func demoShortensWordyPhrases() {
    let rewriter = DemoRewriter()
    let result = rewriter.rewrite("We did this due to the fact that it was necessary", action: .shorten, tone: .professional)
    #expect(result.contains("because"))
    #expect(!result.lowercased().contains("due to the fact"))
}

@Test func demoBulletsSplitSentences() {
    let rewriter = DemoRewriter()
    #expect(rewriter.rewrite("Hello there. This is a second sentence.", action: .bullets, tone: .casual) == "- Hello there.\n- This is a second sentence.")
}

@Test func demoExpandAddsDeterministicCloser() {
    let rewriter = DemoRewriter()
    #expect(rewriter.rewrite("We need this.", action: .expand, tone: .casual) == "We need this. That is the point to keep in view.")
}

@Test func demoContinueKeepsSourceAndAddsNextStep() {
    let rewriter = DemoRewriter()
    let result = rewriter.rewrite("Ship the rewrite panel.", action: .continueWriting, tone: .casual)
    #expect(result.hasPrefix("Ship the rewrite panel."))
    #expect(result.contains("next step"))
}

@MainActor
@Test func historyRecordsAndCapsEntries() {
    let suite = "tajpo.tests.history.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = HistoryStore(defaults: defaults, key: "entries", enabled: true)
    for index in 0..<45 {
        store.record(action: .correct, tone: .casual, original: "o\(index)", result: "r\(index)")
    }
    #expect(store.entries.count == HistoryStore.maximumEntries)
    #expect(store.entries.first?.original == "o44")
    store.clear()
    #expect(store.entries.isEmpty)
}

@MainActor
@Test func demoProviderRewritesWithoutAPIKey() async {
    let settings = AppSettings()
    settings.provider = .demo
    let selection = MockTextSelectionService(capturedText: "teh fox")
    let model = AppModel(
        settings: settings,
        presets: PresetStore(),
        history: HistoryStore(defaults: UserDefaults(suiteName: "tajpo.tests.demo") ?? .standard, key: "demo", enabled: true),
        selection: selection,
        keyStore: InMemoryAPIKeyStore(),
        startAutomatically: false,
        makeClient: AppModel.liveClient
    )
    await model.openInlineRewrite()
    await model.runCurrentCapture()
    #expect(!model.isError)
    #expect(model.preview == "The fox")
}
