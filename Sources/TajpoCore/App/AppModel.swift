import AppKit
import Combine

@MainActor
public final class AppModel: ObservableObject {
    @Published public var status = "Ready"
    @Published public var isWorking = false
    @Published public var isError = false
    @Published public var action: RewriteAction = .correct
    @Published public var tone: RewriteTone = .professional
    @Published public var originalText = ""
    @Published public var preview = ""
    @Published public var usageLabel = ""
    @Published public var isAccessibilityTrusted = false
    @Published public var launchesAtLogin = false
    @Published public var hotkeyConfirmed = false
    @Published public var updateMessage = ""
    @Published public var updateURL: URL?

    public let settings: AppSettings
    public let presets: PresetStore

    private let selection: TextSelectionServing
    private let keyStore: APIKeyStoring
    private let panel = InlinePanelController()
    private let makeClient: @Sendable (LLMEndpoint, String) -> any LLMClient
    private var currentCapture: TextCapture?
    private var lastReplacement: (original: String, rewritten: String, capture: TextCapture)?
    private var generateTask: Task<Void, Never>?
    private var didStart = false
    private var lastAction: RewriteAction?
    private var lastTone: RewriteTone?
    private var accessibilityTask: Task<Void, Never>?

    public init(
        settings: AppSettings = AppSettings(),
        presets: PresetStore = PresetStore(),
        selection: TextSelectionServing = TextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore(),
        startAutomatically: Bool = true,
        makeClient: @escaping @Sendable (LLMEndpoint, String) -> any LLMClient = { endpoint, key in
            OpenAICompatibleClient(endpoint: endpoint, apiKey: key)
        }
    ) {
        self.settings = settings
        self.presets = presets
        self.selection = selection
        self.keyStore = keyStore
        self.makeClient = makeClient
        launchesAtLogin = LaunchAtLogin.isEnabled
        isAccessibilityTrusted = selection.isTrusted
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
        if !UserDefaults.standard.bool(forKey: "completedOnboarding") {
            OnboardingController.shared.show(model: self)
        }
        Task { await checkForUpdates(quiet: true) }
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
        generateTask?.cancel()
        preview = ""
        usageLabel = ""
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
        guard let capture = currentCapture else {
            show(TajpoError.noSelection)
            return
        }
        generateTask?.cancel()
        let task = Task { [weak self] in
            await self?.generate(capture.text)
        }
        generateTask = task
        await task.value
    }

    public func applyPreview() async {
        guard let capture = currentCapture, !preview.isEmpty else { return }
        do {
            try await selection.replace(with: preview, capture: capture)
            lastReplacement = (original: capture.text, rewritten: preview, capture: capture)
            showStatus("Replaced")
            panel.close()
        } catch {
            show(error)
        }
    }

    public func undoLastReplacement() async {
        guard let lastReplacement else {
            show(TajpoError.nothingToUndo)
            return
        }
        do {
            try await selection.replace(with: lastReplacement.original, capture: lastReplacement.capture)
            showStatus("Undid last replace")
            self.lastReplacement = nil
        } catch {
            show(error)
        }
    }

    public func copyPreview() {
        guard !preview.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview, forType: .string)
        showStatus("Copied")
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
        generateTask?.cancel()
        generateTask = nil
        isWorking = false
    }

    public func testConnection() async -> String {
        do {
            let client = try makeConfiguredClient()
            try await client.ping()
            return "Connected to \(settings.provider.title)."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func checkForUpdates(quiet: Bool) async {
        do {
            let status = try await UpdateChecker(repository: settings.githubRepository).check()
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
            if !quiet { updateMessage = TajpoError.updateCheckFailed.errorDescription ?? "Update check failed." }
        }
    }

    public func openUpdatePage() {
        guard let updateURL else { return }
        NSWorkspace.shared.open(updateURL)
    }

    public func saveAPIKey(_ key: String) throws {
        try keyStore.save(key)
    }

    public func deleteAPIKey() throws {
        try keyStore.delete()
    }

    public func hasSavedAPIKey() -> Bool {
        if let key = try? keyStore.load(), let key, !key.isEmpty { return true }
        return false
    }

    private func generate(_ text: String) async {
        do {
            let client = try makeConfiguredClient()
            isWorking = true
            isError = false
            preview = ""
            usageLabel = ""
            defer { isWorking = false }
            lastAction = action
            lastTone = tone
            let result = try await client.rewrite(text, action: action, tone: tone, preset: presets.selected) { [weak self] partial in
                self?.preview = partial
                self?.status = "Writing... \(partial.count) characters"
            }
            preview = result.text
            if let usage = result.usage {
                usageLabel = TokenCost.label(model: settings.model, usage: usage)
                showStatus("Ready to replace · \(usageLabel)")
            } else {
                showStatus("Ready to replace")
            }
        } catch is CancellationError {
            showStatus("Cancelled")
        } catch let error as TajpoError {
            if case .cancelled = error {
                showStatus("Cancelled")
            } else {
                show(error)
            }
        } catch {
            show(error)
        }
    }

    private func makeConfiguredClient() throws -> any LLMClient {
        let stored = APIKeyValidator.optional(try keyStore.load())
        if settings.provider.requiresAPIKey || settings.authStyle != .none {
            let key = try APIKeyValidator.validate(stored)
            return makeClient(settings.endpoint, key)
        }
        return makeClient(settings.endpoint, stored)
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
