import AppKit
import Combine

@MainActor
public final class AppModel: ObservableObject {
    @Published public var status = "Ready"
    @Published public var isWorking = false
    @Published public var isError = false
    @Published public var action: RewriteAction = .correct
    @Published public var tone: RewriteTone = .professional
    @Published public var length: RewriteLength = .same
    @Published public var originalText = ""
    @Published public var preview = ""
    @Published public var usageLabel = ""
    @Published public var isAccessibilityTrusted = false
    @Published public var launchesAtLogin = false
    @Published public var hotkeyConfirmed = false
    @Published public var updateMessage = ""
    @Published public var updateURL: URL?
    /// When the last successful update check ran, shown in Settings.
    @Published public private(set) var lastUpdateCheck: Date?
    @Published public var canUndo = false
    @Published public var canRedo = false
    /// True while the panel shows a restored history preview with no live edit
    /// target. Replace/Retry stay disabled until the user captures live text.
    @Published public var restorePreviewOnly = false

    public let settings: AppSettings
    public let presets: PresetStore
    public let history: HistoryStore

    private let selection: TextSelectionServing
    private let keyStore: APIKeyStoring
    private let panel = InlinePanelController()
    private let makeClient: @Sendable (LLMEndpoint, String) -> any LLMClient
    private var currentCapture: TextCapture?
    private var undoStack: [(original: String, rewritten: String, capture: TextCapture, receipt: MutationReceipt)] = []
    private var redoStack: [(original: String, rewritten: String, capture: TextCapture, receipt: MutationReceipt)] = []
    private var generateTask: Task<Void, Never>?
    /// Monotonically increasing epoch; a generate pass only mutates state while
    /// it still owns the current epoch, so a cancelled task cannot clobber the
    /// state of the generation that replaced it.
    private var generation = 0
    private var isApplyingPreview = false
    private var parameterRewriteTask: Task<Void, Never>?
    private var didStart = false
    private var lastAction: RewriteAction?
    private var lastTone: RewriteTone?
    private var accessibilityTask: Task<Void, Never>?

    public convenience init(
        settings: AppSettings = AppSettings(),
        presets: PresetStore = PresetStore(),
        selection: TextSelectionServing = TextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore(),
        startAutomatically: Bool = true,
        makeClient: @escaping @Sendable (LLMEndpoint, String) -> any LLMClient = { endpoint, key in
            OpenAICompatibleClient(endpoint: endpoint, apiKey: key)
        }
    ) {
        self.init(
            settings: settings,
            presets: presets,
            history: HistoryStore(enabled: settings.historyEnabled),
            selection: selection,
            keyStore: keyStore,
            startAutomatically: startAutomatically,
            makeClient: makeClient
        )
    }

    public init(
        settings: AppSettings,
        presets: PresetStore,
        history: HistoryStore,
        selection: TextSelectionServing,
        keyStore: APIKeyStoring,
        startAutomatically: Bool,
        makeClient: @escaping @Sendable (LLMEndpoint, String) -> any LLMClient
    ) {
        self.settings = settings
        self.presets = presets
        self.history = history
        self.selection = selection
        self.keyStore = keyStore
        self.makeClient = makeClient
        launchesAtLogin = LaunchAtLogin.isEnabled
        isAccessibilityTrusted = selection.isTrusted
        length = settings.rewriteLength
        if let stored = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Double {
            lastUpdateCheck = Date(timeIntervalSince1970: stored)
        }
        if startAutomatically {
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        configureHotkey()
        refreshSystemState()
        accessibilityTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refreshSystemState() }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        if CommandLine.arguments.contains("-TajpoSetup") {
            openOnboarding()
        } else if !UserDefaults.standard.bool(forKey: "completedOnboarding") {
            settings.onboardingStep = min(max(settings.onboardingStep, 0), 4)
            OnboardingController.shared.show(model: self)
        }
        Task { await checkForUpdates(quiet: true) }
    }

    /// Reopens the guided setup even after onboarding has been completed.
    public func openOnboarding() {
        settings.onboardingStep = 0
        UserDefaults.standard.set(false, forKey: "completedOnboarding")
        OnboardingController.shared.show(model: self)
    }

    public func configureHotkey() {
        do {
            try HotkeyCenter.shared.register(id: HotkeyCenter.rewriteID, spec: settings.hotkeySpec) { [weak self] in
                Task { @MainActor in
                    await self?.handleHotkey()
                }
            }
            showStatus("Ready - \(settings.hotkeyLabel)")
        } catch {
            show(error)
        }
    }

    public func requestAccessibility() {
        selection.requestAccessibilityPermission()
        refreshSystemState()
    }

    public func refreshSystemState() {
        isAccessibilityTrusted = selection.isTrusted
        launchesAtLogin = LaunchAtLogin.isEnabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchesAtLogin = LaunchAtLogin.isEnabled
        } catch {
            show(error)
        }
    }

    public func handleHotkey() async {
        hotkeyConfirmed = true
        await openInlineRewrite()
    }

    public func openInlineRewrite() async {
        generation += 1
        parameterRewriteTask?.cancel()
        parameterRewriteTask = nil
        generateTask?.cancel()
        preview = ""
        usageLabel = ""
        restorePreviewOnly = false
        do {
            currentCapture = try await selection.capture()
            originalText = currentCapture?.text ?? ""
            showStatus("Choose an action")
            panel.show(model: self, near: SelectionGeometry.frame(for: currentCapture?.element))
        } catch {
            currentCapture = nil
            originalText = ""
            show(error)
            panel.show(model: self, near: nil)
        }
    }

    public func runCurrentCapture() async {
        parameterRewriteTask?.cancel()
        parameterRewriteTask = nil
        guard let capture = currentCapture else {
            show(TajpoError.noSelection)
            return
        }
        generation += 1
        generateTask?.cancel()
        generateTask = Task { [weak self] in
            guard let self else { return }
            await self.generate(capture.text)
        }
        await generateTask?.value
    }

    /// Debounced rewrite for panel parameter changes (length/tone), so each
    /// click does not fire a full network rewrite. A newer change supersedes
    /// the pending one; closing the panel cancels it via cancelWork().
    public func scheduleParameterRewrite() {
        parameterRewriteTask?.cancel()
        guard currentCapture != nil else { return }
        parameterRewriteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.runCurrentCapture()
        }
    }

    public func applyPreview() async {
        guard !isApplyingPreview else { return }
        guard !restorePreviewOnly else {
            show(TajpoError.replaceTargetChanged)
            return
        }
        guard let capture = currentCapture, !preview.isEmpty else { return }
        isApplyingPreview = true
        defer { isApplyingPreview = false }
        do {
            let receipt = try await selection.replace(with: preview, capture: capture)
            undoStack.append((original: capture.text, rewritten: preview, capture: capture, receipt: receipt))
            redoStack.removeAll()
            recomputeUndoRedoState()
            recordHistory(original: capture.text, result: preview)
            showStatus("Replaced")
            panel.close()
        } catch {
            show(error)
        }
    }

    public func undoLastReplacement() async {
        guard let last = undoStack.last else {
            show(TajpoError.nothingToUndo)
            return
        }
        do {
            // Revalidate the receipt before mutating, so a step never writes
            // into a destination that moved on.
            try selection.verify(last.receipt)
            let receipt = try await selection.replace(with: last.original, capture: last.capture)
            undoStack.removeLast()
            redoStack.append((original: last.original, rewritten: last.rewritten, capture: last.capture, receipt: receipt))
            showStatus("Undid last replace")
        } catch {
            // Keep the entry: a failed replace must not lose the undo step.
            show(error)
        }
        recomputeUndoRedoState()
    }

    public func redoLastReplacement() async {
        guard let last = redoStack.last else {
            show(TajpoError.nothingToRedo)
            return
        }
        do {
            try selection.verify(last.receipt)
            let receipt = try await selection.replace(with: last.rewritten, capture: last.capture)
            redoStack.removeLast()
            undoStack.append((original: last.original, rewritten: last.rewritten, capture: last.capture, receipt: receipt))
            showStatus("Redid last replace")
        } catch {
            // Keep the entry: a failed replace must not lose the redo step.
            show(error)
        }
        recomputeUndoRedoState()
    }

    private func recomputeUndoRedoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    public func copyPreview() {
        guard !preview.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview, forType: .string)
        if let currentCapture {
            let latest = history.entries.first
            if latest?.original != currentCapture.text || latest?.result != preview {
                recordHistory(original: currentCapture.text, result: preview)
            }
        }
        showStatus("Copied")
    }

    public func restoreHistory(_ entry: RewriteHistoryEntry) {
        // Preview-only restore: cancel outstanding work and clear the live edit
        // target so a stored rewrite can never be applied to an unrelated
        // destination. The user must capture live text to replace.
        cancelWork()
        currentCapture = nil
        restorePreviewOnly = true
        originalText = entry.original
        preview = entry.result
        if let action = RewriteAction(rawValue: entry.action) {
            self.action = action
        }
        if let tone = RewriteTone(rawValue: entry.tone) {
            self.tone = tone
        }
        if let length = RewriteLength(rawValue: entry.length) {
            self.length = length
            settings.rewriteLength = length
        }
        showStatus("Restored from history — select the passage live to replace it")
        panel.show(model: self, near: nil)
    }

    public func setHistoryEnabled(_ enabled: Bool) {
        settings.historyEnabled = enabled
        history.setEnabled(enabled)
    }

    /// Removes a single history entry. Does not touch undo/redo state.
    public func deleteHistory(_ id: UUID) {
        history.delete(id: id)
    }

    /// Wipes every piece of local data Tajpo owns: history, presets, settings,
    /// onboarding state, the update-check timestamp, and all Keychain API keys
    /// (both per-provider scoped and the legacy shared account).
    public func eraseAllData() {
        cancelWork()
        history.clear()
        presets.resetToDefaults()
        settings.resetToDefaults()
        UserDefaults.standard.removeObject(forKey: "lastUpdateCheck")
        UserDefaults.standard.removeObject(forKey: "rewriteHistory")
        lastUpdateCheck = nil
        try? KeychainAPIKeyStore(account: KeychainAPIKeyStore.legacyAccount).delete()
        for provider in LLMProvider.allCases {
            try? KeychainAPIKeyStore(provider: provider).delete()
        }
        updateMessage = ""
        updateURL = nil
        preview = ""
        originalText = ""
        showStatus("All local data erased.")
    }

    public func rewriteSelection() async {
        await openInlineRewrite()
    }

    public func repeatLastAction() async {
        guard let lastAction else {
            show(TajpoError.nothingToRepeat)
            return
        }
        action = lastAction
        if let lastTone {
            tone = lastTone
        }
        do {
            currentCapture = try await selection.capture()
            originalText = currentCapture?.text ?? ""
            await runCurrentCapture()
        } catch {
            show(error)
        }
    }

    public func cancelWork() {
        generation += 1
        parameterRewriteTask?.cancel()
        parameterRewriteTask = nil
        generateTask?.cancel()
        generateTask = nil
        isWorking = false
    }

    public func testConnection() async -> String {
        if settings.provider == .demo {
            return "Demo engine is ready. Nothing leaves this Mac."
        }
        do {
            let client = try makeConfiguredClient()
            try await client.ping()
            return "Connected to \(settings.provider.title)."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func checkForUpdates(quiet: Bool) async {
        // Drop any stale "update available" state before the new check resolves.
        updateURL = nil
        updateMessage = ""
        do {
            let status = try await UpdateChecker(repository: settings.githubRepository).check()
            lastUpdateCheck = Date()
            UserDefaults.standard.set(lastUpdateCheck!.timeIntervalSince1970, forKey: "lastUpdateCheck")
            switch status {
            case .upToDate:
                updateURL = nil
                if !quiet { updateMessage = "Tajpo \(AppVersion.string) is up to date." }
            case .available(let version, let url):
                updateURL = url
                updateMessage = "Version \(version) is available."
            }
        } catch {
            updateURL = nil
            if !quiet {
                // Surface the distinct reason (e.g. a private release source)
                // instead of a generic failure.
                updateMessage = (error as? LocalizedError)?.errorDescription
                    ?? TajpoError.updateCheckFailed.errorDescription
                    ?? "Update check failed."
            }
        }
    }

    public func openUpdatePage() {
        guard let updateURL else { return }
        NSWorkspace.shared.open(updateURL)
    }

    public func saveAPIKey(_ key: String) throws {
        if let scoped = scopedKeyStore() {
            try scoped.save(key)
        } else {
            try keyStore.save(key)
        }
    }

    public func deleteAPIKey() throws {
        if let scoped = scopedKeyStore() {
            try scoped.delete()
        } else {
            try keyStore.delete()
        }
    }

    public func hasSavedAPIKey() -> Bool {
        do {
            if let scoped = scopedKeyStore() {
                return !(try scoped.loadMigratingLegacy() ?? "").isEmpty
            }
            return !(try keyStore.load() ?? "").isEmpty
        } catch {
            return false
        }
    }

    /// Keys are scoped per provider so one provider cannot overwrite another's
    /// credential. Custom or injected stores keep their existing behavior.
    private func scopedKeyStore() -> KeychainAPIKeyStore? {
        guard keyStore is KeychainAPIKeyStore else { return nil }
        return KeychainAPIKeyStore(provider: settings.provider)
    }

    private func generate(_ text: String) async {
        let myGeneration = generation
        do {
            let client = try makeConfiguredClient()
            guard generation == myGeneration else { return }
            isWorking = true
            isError = false
            preview = ""
            usageLabel = ""
            defer {
                if generation == myGeneration { isWorking = false }
            }
            lastAction = action
            lastTone = tone
            let result = try await client.rewrite(text, action: action, tone: tone, preset: settings.effectivePreset(presets.selected)) { [weak self] partial in
                guard let self, self.generation == myGeneration else { return }
                self.preview = partial
                self.status = "Writing... \(partial.count) characters"
            }
            guard generation == myGeneration else { return }
            preview = result.text
            switch (result.finishReason, result.usage) {
            case (.contentFiltered, _):
                show(TajpoError.emptyContentFiltered)
            case (.truncated, _):
                usageLabel = result.usage.map { TokenCost.label(model: settings.model, usage: $0) } ?? ""
                showStatus(usageLabel.isEmpty
                    ? "Ready to replace - the model stopped early; consider Retry or a longer limit."
                    : "Ready to replace (truncated by the model) · \(usageLabel)")
            case (_, let usage?):
                usageLabel = TokenCost.label(model: settings.model, usage: usage)
                showStatus(usageLabel.isEmpty ? "Ready to replace" : "Ready to replace · \(usageLabel)")
            default:
                showStatus("Ready to replace")
            }
        } catch is CancellationError {
            guard generation == myGeneration else { return }
            showStatus("Cancelled")
        } catch let error as TajpoError {
            guard generation == myGeneration else { return }
            if case .cancelled = error {
                showStatus("Cancelled")
            } else {
                show(error)
            }
        } catch {
            guard generation == myGeneration else { return }
            show(error)
        }
    }

    private func makeConfiguredClient() throws -> any LLMClient {
        if settings.provider == .demo {
            return DemoClient(length: length, customInstructions: settings.customInstructions)
        }
        let stored = APIKeyValidator.optional(try loadProviderKey())
        let key = (settings.provider.requiresAPIKey || settings.authStyle != .none)
            ? try APIKeyValidator.validate(stored)
            : stored
        let client = makeClient(settings.endpoint, key)
        if var remote = client as? OpenAICompatibleClient {
            remote.length = length
            remote.customInstructions = settings.customInstructions
            return remote
        }
        return client
    }

    /// Loads the API key for the current provider. When the store is the
    /// Keychain, the account is scoped per provider and any key stored under
    /// the legacy shared "openai-api-key" account is migrated into it.
    private func loadProviderKey() throws -> String? {
        guard keyStore is KeychainAPIKeyStore else { return try keyStore.load() }
        return try KeychainAPIKeyStore(provider: settings.provider).loadMigratingLegacy()
    }

    private func recordHistory(original: String, result: String) {
        history.record(action: action, tone: tone, length: length, original: original, result: result)
    }

    private func showStatus(_ message: String) {
        status = message
        isError = false
    }

    private func show(_ error: Error) {
        status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isError = true
        isWorking = false
    }
}
