import AppKit
import Foundation
import Testing
@testable import Tajpo
@testable import TajpoCore

/// A controllable stand-in for the OpenAI client.
final class FakeClient: LLMClient, @unchecked Sendable {
    typealias Handler = @Sendable (PromptRequest, Int) async throws -> String
    private let lock = NSLock()
    private var calls = 0
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    var callCount: Int { lock.withLock { calls } }

    func stream(_ prompt: PromptRequest, model: String, onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        let call = lock.withLock { calls += 1; return calls }
        return try await handler(prompt, call)
    }

    func testConnection(model: String) async throws {}
}

struct FakeKeyStore: APIKeyStoring {
    var key: String?
    func load() throws -> String? { key }
    func save(_ value: String) throws {}
    func delete() throws {}
    func savedKeyHint() -> String? { key.map(APIKeyValidator.hint(for:)) }
}

/// Waits (up to ~3 s) for a condition on the main actor.
@MainActor
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<300 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Resumes after a delay even if the calling task was cancelled.
func uncancellableDelay(_ seconds: Double) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
    }
}

@MainActor
func makeModel(client: FakeClient, key: String? = nil, localServer: Bool = true) -> AppModel {
    let defaults = UserDefaults(suiteName: "tajpo-tests-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    if localServer { try? settings.setBaseURL("http://127.0.0.1:9/v1") }
    let model = AppModel(
        settings: settings,
        presets: PresetStore(defaults: defaults),
        selection: TextSelectionService(),
        keyStore: FakeKeyStore(key: key),
        makeClient: { _, _, _ in client }
    )
    model.refreshStatus()
    return model
}

@MainActor
func capture(_ model: AppModel, _ text: String, blocker: TajpoError? = nil) {
    model.session.captured(TextCapture(text: text, method: .local, element: nil, selectedRange: nil,
                                       sourceApp: nil, bounds: nil, replaceBlocker: blocker))
}

@Suite(.serialized) @MainActor struct AppModelTests {
    @Test func runProducesFinalizedResult() async {
        let client = FakeClient { _, _ in "This is a paragraph." }
        let model = makeModel(client: client)
        capture(model, "Ths is a paragrph.\n")
        model.run(.correct)
        await eventually { model.session.phase == .finished }
        #expect(model.session.result == "This is a paragraph.\n")
        #expect(model.session.diff != nil)
        #expect(model.lastAction == .correct)
        #expect(!model.isWorking)
        #expect(model.session.canReplace)
    }

    @Test func staleRunCannotClobberNewerRun() async {
        let client = FakeClient { _, call in
            if call == 1 {
                // The first run is cancelled when the second starts; its error arrives late.
                do { try await Task.sleep(for: .seconds(5)) } catch {}
                await uncancellableDelay(0.3)
                throw TajpoError.network("late failure from the first run")
            }
            await uncancellableDelay(0.6)
            return "Second result."
        }
        let model = makeModel(client: client)
        capture(model, "Some text.")
        model.run(.improve)
        await eventually { client.callCount == 1 }
        model.run(.shorten)
        // While the second run is still going, the first run's late error must not end it.
        await uncancellableDelay(0.45)
        #expect(model.session.isRunning)
        #expect(model.isWorking)
        #expect(model.session.error == nil)
        #expect(!model.session.canReplace)
        await eventually { model.session.phase == .finished }
        #expect(model.session.result == "Second result.")
        #expect(model.session.action == .shorten)
        #expect(model.session.error == nil)
    }

    @Test func truncatedOutputBlocksReplaceButAllowsCopy() async {
        let client = FakeClient { _, _ in throw TajpoError.outputTruncated }
        let model = makeModel(client: client)
        capture(model, "Long text.")
        model.run(.rewrite)
        await eventually { model.session.phase == .failed }
        #expect(model.session.error == .outputTruncated)
        #expect(!model.session.canReplace)
        #expect(model.session.result == nil)
    }

    @Test func missingKeyIsReportedWithoutCallingTheServer() async {
        let client = FakeClient { _, _ in "unused" }
        let model = makeModel(client: client, key: nil, localServer: false)
        #expect(model.needsAPIKey)
        capture(model, "Hello.")
        model.run(.improve)
        #expect(model.session.error == .missingAPIKey)
        #expect(client.callCount == 0)
    }

    @Test func customRunNeedsAnInstruction() async {
        let client = FakeClient { prompt, _ in
            #expect(prompt.system.contains("make it formal"))
            return "Formal."
        }
        let model = makeModel(client: client)
        capture(model, "hey")
        model.run(.custom)
        #expect(model.session.focusInstruction)
        #expect(client.callCount == 0)
        model.session.instruction = "make it formal"
        model.run(.custom)
        await eventually { model.session.phase == .finished }
        #expect(model.session.result == "Formal.")
        #expect(model.settings.recentInstructions.first == "make it formal")
    }

    @Test func tooLongSelectionIsRejectedBeforeSending() async {
        let client = FakeClient { _, _ in "unused" }
        let model = makeModel(client: client)
        try? model.settings.setModel("gpt-4o-mini")
        capture(model, String(repeating: "word ", count: 16_000))
        model.run(.correct)
        #expect(model.session.phase == .failed)
        #expect(client.callCount == 0)
    }

    @Test func blockedCaptureCannotReplace() async {
        let client = FakeClient { _, _ in "Done." }
        let model = makeModel(client: client)
        capture(model, "Read-only text.", blocker: .replaceNotSupported)
        model.run(.improve)
        await eventually { model.session.phase == .finished }
        #expect(!model.session.canReplace)
        #expect(model.session.copyableText == "Done.")
    }
}

@Suite @MainActor struct HotkeyManagerTests {
    @Test func failedChangeKeepsTheWorkingShortcut() throws {
        let manager = HotkeyManager()
        let working = GlobalShortcut(keyCode: 0x6F, modifiers: GlobalShortcut.Modifier.control | GlobalShortcut.Modifier.option) // ⌃⌥F12
        try manager.register(working, for: .rewrite)
        #expect(throws: TajpoError.self) {
            try manager.register(GlobalShortcut(keyCode: KeyCode.t, modifiers: GlobalShortcut.Modifier.shift), for: .rewrite)
        }
        #expect(manager.shortcuts[.rewrite] == working)
        #expect(throws: TajpoError.hotkeyDuplicate) { try manager.register(working, for: .repeatLast) }
        try manager.register(nil, for: .rewrite)
        #expect(manager.shortcuts[.rewrite] == nil)
    }
}

@Suite @MainActor struct PersistenceTests {
    @Test func shortcutsAndPresetsSurviveRelaunch() {
        let defaults = UserDefaults(suiteName: "tajpo-persist-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.storeShortcut(nil, for: .repeatLast)
        let custom = GlobalShortcut(keyCode: KeyCode.k, modifiers: GlobalShortcut.Modifier.command | GlobalShortcut.Modifier.option)
        settings.storeShortcut(custom, for: .rewrite)
        let presets = PresetStore(defaults: defaults)
        presets.select(WritingPreset.casual.id)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.rewriteShortcut == custom)
        #expect(reloaded.repeatShortcut == nil)
        #expect(PresetStore(defaults: defaults).selectedID == WritingPreset.casual.id)
    }

    @Test func legacyShortcutIsMigrated() {
        let defaults = UserDefaults(suiteName: "tajpo-legacy-\(UUID().uuidString)")!
        defaults.set(Int(KeyCode.t), forKey: "hotkeyKeyCode")
        defaults.set(Int(GlobalShortcut.Modifier.command | GlobalShortcut.Modifier.option), forKey: "hotkeyModifiers")
        #expect(AppSettings(defaults: defaults).rewriteShortcut?.displayString == "⌥⌘T")

        let invalid = UserDefaults(suiteName: "tajpo-legacy-bad-\(UUID().uuidString)")!
        invalid.set(Int(KeyCode.e), forKey: "hotkeyKeyCode")
        invalid.set(Int(GlobalShortcut.Modifier.option), forKey: "hotkeyModifiers")
        #expect(AppSettings(defaults: invalid).rewriteShortcut == .defaultRewrite)
    }
}
