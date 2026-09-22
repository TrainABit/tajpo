import AppKit
import Carbon
import Combine
import TajpoCore

/// Lets a Tajpo window (the onboarding practice field) act as the text source,
/// since Tajpo can't read its own windows through Accessibility.
@MainActor
protocol LocalTextProvider: AnyObject {
    var practiceText: String { get }
    func replacePracticeText(with text: String)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Menu-level state. Per-token state lives in `session`.
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var apiKeyHint: String?
    @Published private(set) var hotkeyErrors: [HotkeyAction: TajpoError] = [:]
    @Published private(set) var secureInputActive = false
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Ready"
    @Published private(set) var lastAction: RewriteAction?
    private var lastInstruction: String?
    @Published private(set) var launchAtLoginEnabled = false

    let settings: AppSettings
    let presets: PresetStore
    let session = RewriteSession()
    let hotkeys = HotkeyManager()

    private let selection: TextSelectionService
    private let keyStore: APIKeyStoring
    private let makeClient: (String?, URL, String) -> LLMClient
    private let panel = InlinePanelController()
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private lazy var onboardingWindow = OnboardingWindowController(model: self)

    private var runID: UUID?
    private var runTask: Task<Void, Never>?
    private var isCapturing = false
    private var didStart = false
    private var statusTimer: Timer?

    /// Set by the onboarding shortcut step: a press is reported instead of opening the panel.
    var shortcutProbe: (() -> Void)?
    weak var localTextProvider: LocalTextProvider?

    init(
        settings: AppSettings = AppSettings(),
        presets: PresetStore = PresetStore(),
        selection: TextSelectionService = TextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore(),
        makeClient: @escaping (String?, URL, String) -> LLMClient = { key, url, project in
            OpenAIClient(apiKey: key, baseURL: url, projectID: project)
        }
    ) {
        self.settings = settings
        self.presets = presets
        self.selection = selection
        self.keyStore = keyStore
        self.makeClient = makeClient
        session.tone = settings.lastTone
    }

    // MARK: Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        hotkeys.onPress = { [weak self] action in self?.handleHotkey(action) }
        for action in HotkeyAction.allCases {
            if let error = applyShortcut(settings.shortcut(for: action), for: action) {
                Log.hotkey.error("Launch registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        panel.onClose = { [weak self] in self?.panelClosed() }
        panel.onOutsideClick = { [weak self] in self?.outsideClick() }
        if !UserDefaults.standard.bool(forKey: "completedOnboarding") {
            showOnboarding()
        }
    }

    func refreshStatus() {
        let trusted = selection.isTrusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputActive { secureInputActive = secure }
        let hint = keyStore.savedKeyHint()
        if hint != apiKeyHint { apiKeyHint = hint }
        let login = LaunchAtLogin.isEnabled
        if login != launchAtLoginEnabled { launchAtLoginEnabled = login }
    }

    var needsAPIKey: Bool { settings.usesOpenAI && apiKeyHint == nil }

    var needsSetup: Bool { !accessibilityTrusted || needsAPIKey || !hotkeyErrors.isEmpty }

    // MARK: Hotkeys

    var lastActionTitle: String? {
        guard let lastAction else { return nil }
        if lastAction == .custom, let lastInstruction { return "“\(lastInstruction)”" }
        return lastAction.title
    }

    private func handleHotkey(_ action: HotkeyAction) {
        if let probe = shortcutProbe {
            probe()
            return
        }
        switch action {
        case .rewrite: openPanel()
        case .repeatLast: repeatLastAction()
        }
    }

    /// Registers a shortcut and stores it only if registration succeeded.
    @discardableResult
    func applyShortcut(_ shortcut: GlobalShortcut?, for action: HotkeyAction) -> TajpoError? {
        do {
            try hotkeys.register(shortcut, for: action)
            settings.storeShortcut(shortcut, for: action)
            hotkeyErrors[action] = nil
            return nil
        } catch {
            let mapped = error as? TajpoError ?? .hotkeyRejectedBySystem(shortcut?.displayString ?? "")
            // The previous shortcut stays active after a failed change; only
            // flag a problem when the action has no working shortcut.
            if hotkeys.shortcuts[action] == nil { hotkeyErrors[action] = mapped }
            return mapped
        }
    }

    // MARK: Panel flow

    func openPanel(thenRun action: RewriteAction? = nil, instruction: String? = nil) {
        guard !isCapturing, !session.isReplacing else { return }
        cancelRun()
        session.reset()
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let capture: TextCapture
                if NSApp.isActive, let provider = localTextProvider {
                    capture = TextCapture(text: provider.practiceText, method: .local, element: nil, selectedRange: nil,
                                          sourceApp: nil, bounds: nil, replaceBlocker: nil)
                    try SelectionValidator.validate(capture.text)
                } else {
                    capture = try await selection.capture()
                }
                session.captured(capture)
                panel.show(model: self, near: capture.bounds)
                if let action {
                    if let instruction { session.instruction = instruction }
                    run(action)
                } else if let problem = configurationProblem() {
                    session.fail(problem)
                }
            } catch {
                session.fail(Self.map(error))
                panel.show(model: self, near: nil)
            }
        }
    }

    func run(_ action: RewriteAction) {
        guard let capture = session.capture, !session.isReplacing else { return }
        let instruction = session.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .custom && instruction.isEmpty {
            session.focusInstruction = true
            return
        }
        if let problem = configurationProblem() {
            session.fail(problem)
            return
        }
        let model = settings.model
        do {
            try SelectionValidator.validate(capture.text, action: action, model: model)
        } catch {
            session.fail(Self.map(error))
            return
        }
        cancelRun()
        let id = UUID()
        runID = id
        let tone = session.tone
        let request = PromptBuilder.request(text: capture.text, action: action, tone: tone, preset: presets.selected, model: model,
                                            instruction: action == .custom ? instruction : nil)
        let tag = PromptBuilder.tagName(for: capture.text)
        let client = makeClient(try? keyStore.load(), settings.baseURL, settings.projectID)
        session.begin(action)
        isWorking = true
        status = "Writing…"

        runTask = Task { [weak self] in
            do {
                let output = try await client.stream(request, model: model) { [weak self] partial in
                    guard let self, self.runID == id else { return }
                    self.session.update(preview: partial)
                }
                guard let self, self.runID == id else { return }
                self.session.finish(OutputCleaner.finalize(output, original: capture.text, tag: tag))
                self.lastAction = action
                self.lastInstruction = action == .custom ? instruction : nil
                if action == .custom { self.settings.rememberInstruction(instruction) }
                self.settings.lastTone = tone
                self.endRun(status: "Ready to replace")
            } catch {
                // Errors from a superseded run must not touch the current one.
                guard let self, self.runID == id else { return }
                let mapped = Self.map(error)
                if mapped == .cancelled {
                    self.session.cancelled()
                    self.endRun(status: "Cancelled")
                } else {
                    self.session.fail(mapped)
                    self.endRun(status: mapped.localizedDescription)
                }
            }
        }
    }

    func stop() {
        cancelRun()
        session.cancelled()
    }

    func retry() {
        if let action = session.action { run(action) }
    }

    func runTone(_ tone: RewriteTone) {
        session.tone = tone
        run(.changeTone)
    }

    func replace() {
        guard session.canReplace, let capture = session.capture, let text = session.result else { return }
        session.isReplacing = true
        Task {
            defer { session.isReplacing = false }
            if capture.method == .local {
                localTextProvider?.replacePracticeText(with: text)
                closePanel(status: "Replaced")
                return
            }
            do {
                let outcome = try await selection.replace(with: text, capture: capture, hidePanel: { panel.hide() })
                closePanel(status: outcome == .verified ? "Replaced" : "Pasted. Check the result")
            } catch {
                panel.reshow()
                session.report(Self.map(error))
            }
        }
    }

    func copyResult() {
        guard let text = session.copyableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        session.note("Copied to the clipboard")
    }

    func repeatLastAction() {
        guard let lastAction else {
            session.reset()
            session.fail(.nothingToRepeat)
            panel.show(model: self, near: nil)
            return
        }
        openPanel(thenRun: lastAction, instruction: lastInstruction)
    }

    func closePanel(status: String? = nil) {
        cancelRun()
        panel.close()
        session.reset()
        if let status { self.status = status }
    }

    private func panelClosed() {
        cancelRun()
        session.reset()
    }

    private func outsideClick() {
        // Keep the panel while a result is being written or waiting to be used.
        if session.phase == .ready || (session.phase == .failed && session.copyableText == nil) {
            closePanel()
        }
    }

    private func cancelRun() {
        runID = nil
        runTask?.cancel()
        runTask = nil
        if isWorking { endRun(status: "Ready") }
    }

    private func endRun(status: String) {
        isWorking = false
        self.status = status
    }

    private func configurationProblem() -> TajpoError? {
        needsAPIKey ? .missingAPIKey : nil
    }

    static func map(_ error: Error) -> TajpoError {
        if let error = error as? TajpoError { return error }
        if error is CancellationError { return .cancelled }
        return .network(error.localizedDescription)
    }

    // MARK: Recovery and windows

    func perform(_ recovery: RecoveryAction) {
        switch recovery {
        case .openSettings: showSettings(tab: .ai)
        case .openAccessibilitySettings: openAccessibilitySettings()
        case .openBilling: open("https://platform.openai.com/settings/organization/billing/overview")
        case .openAPIKeys: open("https://platform.openai.com/api-keys")
        case .retry: retry()
        }
    }

    func requestAccessibility() {
        selection.requestAccessibilityPermission()
        refreshStatus()
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func showSettings(tab: SettingsTab = .general) {
        settingsWindow.show(tab: tab)
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "completedOnboarding")
        onboardingWindow.close()
    }

    func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tajpo",
            .applicationVersion: version,
            .credits: NSAttributedString(string: "Select text anywhere, press a shortcut, and improve it. Your text goes only to the AI provider you configure.")
        ])
    }

    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            refreshStatus()
            return nil
        } catch {
            refreshStatus()
            return error.localizedDescription
        }
    }

    // MARK: API key

    func saveAPIKey(_ text: String) throws {
        try keyStore.save(text)
        refreshStatus()
    }

    func removeAPIKey() throws {
        try keyStore.delete()
        refreshStatus()
    }

    /// Checks the saved key, credit, and model with a tiny request.
    func testConnection() async throws {
        if needsAPIKey { throw TajpoError.missingAPIKey }
        let client = makeClient(try keyStore.load(), settings.baseURL, settings.projectID)
        try await client.testConnection(model: settings.model)
    }
}
