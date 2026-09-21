import Foundation
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

/// The first call keeps emitting partials and returns a result even after its
/// task is cancelled, simulating a generation that outlives its cancellation.
final class ZombieLLMClient: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        lock.lock()
        calls += 1
        let call = calls
        lock.unlock()
        if call == 1 {
            try? await Task.sleep(for: .milliseconds(300))
            await onPartial("stale partial")
            return RewriteResult(text: "stale result")
        }
        await onPartial("fresh result")
        return RewriteResult(text: "fresh result")
    }

    func ping() async throws {}
}

@MainActor
final class FailingReplaceSelection: TextSelectionServing {
    var isTrusted = true
    var shouldFail = false
    var shouldFailVerify = false
    private(set) var replaceAttempts = 0
    private(set) var verifyAttempts = 0

    func requestAccessibilityPermission() {}

    func capture() async throws -> TextCapture {
        TextCapture(text: "hello world", element: nil, sourceApp: nil)
    }

    @discardableResult
    func replace(with text: String, capture: TextCapture) async throws -> MutationReceipt {
        replaceAttempts += 1
        if shouldFail { throw TajpoError.api("simulated replace failure") }
        return MutationReceipt(
            pid: capture.pid,
            element: capture.element,
            replacedContent: capture.text,
            writtenContent: text,
            utf16Range: capture.utf16Range
        )
    }

    func verify(_ receipt: MutationReceipt) throws {
        verifyAttempts += 1
        if shouldFailVerify { throw TajpoError.replaceTargetChanged }
    }
}

@MainActor
private func makeModel(
    selection: TextSelectionServing & AnyObject,
    client: any LLMClient = ScriptedLLMClient(),
    historyKey: String = "flow.\(UUID().uuidString)"
) -> AppModel {
    let settings = AppSettings()
    settings.provider = .openAI
    return AppModel(
        settings: settings,
        presets: PresetStore(),
        history: HistoryStore(defaults: UserDefaults(suiteName: "tajpo.tests.flow.\(UUID().uuidString)") ?? .standard, key: historyKey, enabled: true),
        selection: selection,
        keyStore: InMemoryAPIKeyStore(value: "sk-test"),
        startAutomatically: false,
        makeClient: { _, _ in client }
    )
}

@MainActor
@Test func generateReplaceAndUndoUseSelectionService() async throws {
    let selection = MockTextSelectionService(capturedText: "hello world")
    let keys = InMemoryAPIKeyStore(value: "sk-test")
    let settings = AppSettings()
    settings.provider = .openAI
    let model = AppModel(
        settings: settings,
        presets: PresetStore(),
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
    await model.redoLastReplacement()
    #expect(selection.replacedText == "rewritten hello world")
}

@MainActor
@Test func redoWithoutHistoryIsExplicit() async {
    let model = AppModel(
        selection: MockTextSelectionService(),
        keyStore: InMemoryAPIKeyStore(value: "sk-test"),
        startAutomatically: false,
        makeClient: { _, _ in ScriptedLLMClient() }
    )
    await model.redoLastReplacement()
    #expect(model.status == TajpoError.nothingToRedo.errorDescription)
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

@MainActor
@Test func failedUndoKeepsEntryAndFlags() async {
    let selection = FailingReplaceSelection()
    let model = makeModel(selection: selection)
    await model.openInlineRewrite()
    await model.runCurrentCapture()
    await model.applyPreview()
    #expect(model.canUndo)
    #expect(!model.canRedo)
    selection.shouldFail = true
    await model.undoLastReplacement()
    // The failed replace must not consume the entry or change the flags.
    #expect(model.canUndo)
    #expect(!model.canRedo)
    selection.shouldFail = false
    await model.undoLastReplacement()
    #expect(!model.canUndo)
    #expect(model.canRedo)
}

@MainActor
@Test func failedRedoKeepsEntryAndFlags() async {
    let selection = FailingReplaceSelection()
    let model = makeModel(selection: selection)
    await model.openInlineRewrite()
    await model.runCurrentCapture()
    await model.applyPreview()
    await model.undoLastReplacement()
    #expect(model.canRedo)
    selection.shouldFail = true
    await model.redoLastReplacement()
    #expect(model.canRedo)
    #expect(!model.canUndo)
    selection.shouldFail = false
    await model.redoLastReplacement()
    #expect(model.canUndo)
    #expect(!model.canRedo)
}

@MainActor
@Test func concurrentApplyPreviewAppliesExactlyOnce() async {
    let selection = FailingReplaceSelection()
    let model = makeModel(selection: selection)
    await model.openInlineRewrite()
    await model.runCurrentCapture()
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await model.applyPreview() }
        group.addTask { await model.applyPreview() }
    }
    #expect(selection.replaceAttempts == 1)
    #expect(model.history.entries.count == 1)
    #expect(model.canUndo)
}

@MainActor
@Test func cancelledGenerationCannotClobberNewOne() async {
    let model = makeModel(selection: MockTextSelectionService(capturedText: "hello world"), client: ZombieLLMClient())
    await model.openInlineRewrite()
    let first = Task { await model.runCurrentCapture() }
    // Let the first generation start streaming, then cancel it and start a new one.
    try? await Task.sleep(for: .milliseconds(50))
    model.cancelWork()
    await model.runCurrentCapture()
    #expect(model.preview == "fresh result")
    // The first (zombie) generation resolves later; none of its callbacks may leak through.
    await first.value
    #expect(model.preview == "fresh result")
    #expect(model.status != "Cancelled")
    #expect(!model.isWorking)
    #expect(!model.isError)
}

@MainActor
@Test func copyPreviewSkipsDuplicateConsecutiveEntries() {
    let selection = MockTextSelectionService(capturedText: "hello world")
    let model = makeModel(selection: selection)
    model.preview = "rewritten hello world"
    model.copyPreview()
    model.copyPreview()
    #expect(model.history.entries.count == 1)
    model.preview = "another result"
    model.copyPreview()
    #expect(model.history.entries.count == 2)
}

@MainActor
@Test func restoreHistoryRestoresLengthAndLegacyEntriesDefault() throws {
    let selection = MockTextSelectionService(capturedText: "hello world")
    let model = makeModel(selection: selection)
    let entry = RewriteHistoryEntry(action: "shorten", tone: "casual", length: "shorter", original: "o", result: "r")
    model.restoreHistory(entry)
    #expect(model.length == .shorter)
    #expect(model.settings.rewriteLength == .shorter)

    // Entries written before length was recorded decode with the .same default.
    let legacyJSON = #"[{"id":"B2E36BC1-0D31-4FB6-9A1B-63B5F1E6B734","createdAt":700000000,"action":"correct","tone":"casual","original":"o","result":"r"}]"#
    let decoded = try JSONDecoder().decode([RewriteHistoryEntry].self, from: Data(legacyJSON.utf8))
    #expect(decoded.first?.length == RewriteLength.same.rawValue)
}
