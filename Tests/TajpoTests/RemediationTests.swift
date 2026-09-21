import Foundation
import Testing
@testable import TajpoCore

/// Regression coverage for the remediation pass: preview-only history restore,
/// receipts gating undo/redo, and non-destructive history recording.
@MainActor
@Suite struct RemediationTests {
    private func makeModel(
        selection: TextSelectionServing & AnyObject,
        client: any LLMClient = ScriptedLLMClient()
    ) -> AppModel {
        let settings = AppSettings()
        settings.provider = .openAI
        return AppModel(
            settings: settings,
            presets: PresetStore(),
            history: HistoryStore(
                defaults: UserDefaults(suiteName: "tajpo.tests.remediation.\(UUID().uuidString)") ?? .standard,
                key: "history",
                enabled: true
            ),
            selection: selection,
            keyStore: InMemoryAPIKeyStore(value: "sk-test"),
            startAutomatically: false,
            makeClient: { _, _ in client }
        )
    }

    private func historyEntry() -> RewriteHistoryEntry {
        RewriteHistoryEntry(
            action: RewriteAction.improve.rawValue,
            tone: RewriteTone.friendly.rawValue,
            length: RewriteLength.same.rawValue,
            original: "a stored passage",
            result: "A stored passage, improved."
        )
    }

    @Test func restoreHistoryIsPreviewOnlyAndCannotReplace() async {
        let selection = MockTextSelectionService(capturedText: "live text")
        let model = makeModel(selection: selection)
        await model.openInlineRewrite()
        #expect(model.restorePreviewOnly == false)

        model.restoreHistory(historyEntry())
        #expect(model.restorePreviewOnly)
        #expect(model.preview == "A stored passage, improved.")
        #expect(model.originalText == "a stored passage")

        // Replace must be a no-op while the preview has no live target.
        await model.applyPreview()
        #expect(selection.replacements.isEmpty)
    }

    @Test func freshCaptureClearsPreviewOnlyMode() async {
        let selection = MockTextSelectionService(capturedText: "live text")
        let model = makeModel(selection: selection)
        model.restoreHistory(historyEntry())
        #expect(model.restorePreviewOnly)

        await model.openInlineRewrite()
        #expect(model.restorePreviewOnly == false)
        #expect(model.originalText == "live text")

        await model.runCurrentCapture()
        await model.applyPreview()
        #expect(selection.replacements.count == 1)
    }

    @Test func undoBlockedByReceiptVerificationKeepsTheEntry() async {
        let selection = FailingReplaceSelection()
        let model = makeModel(selection: selection)
        await model.openInlineRewrite()
        await model.runCurrentCapture()
        await model.applyPreview()
        #expect(selection.replaceAttempts == 1)
        #expect(model.canUndo)

        // A receipt that no longer describes the destination blocks the write
        // and must not consume the undo step.
        selection.shouldFailVerify = true
        await model.undoLastReplacement()
        #expect(selection.replaceAttempts == 1)
        #expect(model.canUndo)
        #expect(model.status == TajpoError.replaceTargetChanged.errorDescription)

        // Once verification passes the step behaves normally again.
        selection.shouldFailVerify = false
        await model.undoLastReplacement()
        #expect(selection.replaceAttempts == 2)
        #expect(model.canRedo)
    }

    @Test func deletingHistoryDoesNotTouchUndoState() async {
        let selection = MockTextSelectionService(capturedText: "live text")
        let model = makeModel(selection: selection)
        await model.openInlineRewrite()
        await model.runCurrentCapture()
        await model.applyPreview()
        #expect(model.canUndo)
        #expect(!model.history.entries.isEmpty)

        model.deleteHistory(model.history.entries[0].id)
        #expect(model.history.entries.isEmpty)
        #expect(model.canUndo)
    }
}

@MainActor
@Suite struct HistoryRecordingToggleTests {
    private func makeStore(suite: UserDefaults, key: String = "history") -> HistoryStore {
        HistoryStore(defaults: suite, key: key, enabled: true)
    }

    @Test func disablingRecordingKeepsExistingEntriesAcrossReload() {
        let suite = UserDefaults(suiteName: "tajpo.tests.history-toggle.\(UUID().uuidString)") ?? .standard
        let store = makeStore(suite: suite)
        store.record(action: .correct, tone: .casual, original: "a", result: "b")
        store.record(action: .improve, tone: .friendly, original: "c", result: "d")
        #expect(store.entries.count == 2)

        store.setEnabled(false)
        #expect(store.entries.count == 2)
        store.record(action: .rewrite, tone: .professional, original: "e", result: "f")
        #expect(store.entries.count == 2)

        let reloaded = makeStore(suite: suite)
        #expect(reloaded.entries.count == 2)
    }

    @Test func clearWhileRecordingIsDisabledPersists() {
        let suite = UserDefaults(suiteName: "tajpo.tests.history-toggle.\(UUID().uuidString)") ?? .standard
        let store = makeStore(suite: suite)
        store.record(action: .correct, tone: .casual, original: "a", result: "b")
        store.setEnabled(false)
        store.clear()
        #expect(store.entries.isEmpty)

        let reloaded = makeStore(suite: suite)
        #expect(reloaded.entries.isEmpty)
    }
}