import AppKit
import SwiftUI
import Carbon
import Combine
import TajpoCore

/// Lets a Tajpo window (the onboarding practice field) act as the text source,
/// since Tajpo can't read its own windows through Accessibility.
@MainActor
protocol LocalTextProvider: AnyObject {
    var practiceText: String { get }
    func replacePracticeText(with text: String, diff: [DiffSegment]?)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Menu-level state. Per-token state lives in `session`.
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var apiKeyHint: String?
    @Published private(set) var apiKeyValidated = false
    @Published private(set) var hotkeyErrors: [HotkeyAction: TajpoError] = [:]
    @Published private(set) var secureInputActive = false
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Ready"
    @Published private(set) var lastAction: RewriteAction?
    private var lastInstruction: String?
    @Published private(set) var launchAtLoginEnabled = false
    /// Briefly true after setup so the menu bar icon draws attention to itself.
    @Published private(set) var celebrating = false

    let settings: AppSettings
    let presets: PresetStore
    let session = RewriteSession()
    let hotkeys = HotkeyManager()
    let updates = UpdateChecker()

    private let selection: TextSelectionService
    private let keyStore: APIKeyStoring
    private let makeClient: (String?, URL, String?) -> LLMClient
    let panel = InlinePanelController()
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private lazy var onboardingWindow = OnboardingWindowController(model: self)

    private var runID: UUID?
    private var runTask: Task<Void, Never>?
    private var replaceID: UUID?
    private var replaceTask: Task<Void, Never>?
    private var isCapturing = false
    private var didStart = false
    private var statusTimer: Timer?
    private(set) var isDemo = false

    /// Set by the onboarding shortcut step: a press is reported instead of opening the panel.
    var shortcutProbe: (() -> Void)?
    weak var localTextProvider: LocalTextProvider?

    init(
        settings: AppSettings = AppSettings(),
        presets: PresetStore = PresetStore(),
        selection: TextSelectionService = TextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore(),
        makeClient: @escaping (String?, URL, String?) -> LLMClient = { key, url, project in
            OpenAIClient(apiKey: key, baseURL: url, projectID: project)
        }
    ) {
        self.settings = settings
        self.presets = presets
        self.selection = selection
        self.keyStore = keyStore
        self.makeClient = makeClient
        self.isDemo = DemoScene.requested != nil
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
        if isDemo {
            // Demo scenes are deliberately offline, including update checks.
        } else {
            updates.checkOnLaunchIfDue()
        }
        if let scene = DemoScene.requested {
            showDemo(scene)
        } else if !UserDefaults.standard.bool(forKey: "completedOnboarding") {
            showOnboarding()
        }
    }

    func refreshStatus() {
        let trusted = DemoScene.simulatesReady || (selection.isTrusted && !DemoScene.simulatesNoAccess)
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputActive { secureInputActive = secure }
        let hint = keyStore.savedKeyHint()
        if hint != apiKeyHint {
            apiKeyHint = hint
            // A different Keychain value is a new credential until it has
            // been tested, even if a previous value was valid.
            apiKeyValidated = false
        }
        let login = LaunchAtLogin.isEnabled
        if login != launchAtLoginEnabled { launchAtLoginEnabled = login }
    }

    var needsAPIKey: Bool {
        guard !isDemo, settings.usesOpenAI, !DemoScene.simulatesReady else { return false }
        return apiKeyHint == nil || !apiKeyValidated
    }

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
        if hotkeys.isSuspended { resumeHotkeys() }
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

    /// Ends a suspension (shortcut recording) and reports shortcuts that failed to come back.
    func resumeHotkeys() {
        for (action, error) in hotkeys.resume() {
            hotkeyErrors[action] = error
        }
    }

    // MARK: Panel flow

    func openPanel(thenRun action: RewriteAction? = nil, instruction: String? = nil) {
        guard !isCapturing, !session.isReplacing else { return }
        cancelRun()
        cancelReplace()
        session.reset()
        let generation = session.generation
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
                // The user closed the panel (or started over) while we were reading.
                guard session.generation == generation else { return }
                session.captured(capture)
                session.tip = nextTip()
                panel.show(model: self, near: capture.bounds,
                           sourceName: capture.sourceApp?.localizedName ?? (capture.method == .local ? "Practice" : nil),
                           sourceIcon: capture.sourceApp?.icon)
                if let action {
                    if let instruction { session.instruction = instruction }
                    run(action)
                } else if let problem = configurationProblem() {
                    session.fail(problem)
                }
            } catch {
                guard session.generation == generation else { return }
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
        let tag = PromptBuilder.tagName(for: capture.text)
        let request = PromptBuilder.request(text: capture.text, action: action, tone: tone, preset: presets.selected, model: model,
                                            instruction: action == .custom ? instruction : nil, tag: tag)
        let key: String?
        let project: String?
        if isDemo {
            key = nil
            project = nil
        } else if settings.usesOpenAI {
            do {
                key = try keyStore.load()
            } catch {
                session.fail(Self.map(error))
                return
            }
            project = settings.projectID
        } else {
            // Never load or forward the OpenAI credential to a custom server.
            key = nil
            project = nil
        }
        let client: LLMClient
        if isDemo {
            client = DemoLLMClient()
        } else {
            client = makeClient(key, settings.baseURL, project)
        }
        session.begin(action)
        isWorking = true
        status = "Writing…"

        runTask = Task { [weak self] in
            do {
                let output = try await client.stream(request, model: model) { [weak self] partial in
                    guard let self, self.runID == id else { return }
                    self.session.update(preview: partial)
                }
                try Task.checkCancellation()
                guard let self, self.runID == id else { return }
                let finalized = OutputCleaner.finalize(output, original: capture.text, tag: tag)
                try OutputValidator.validate(finalized, action: action, original: capture.text)
                self.session.finish(finalized)
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
                    self.endRun(status: "Last request failed: \(InlineRewriteView.errorTitle(mapped).lowercased())")
                }
            }
        }
    }

    func stop() {
        cancelRun()
        cancelReplace()
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
        guard replaceTask == nil else { return }
        session.isReplacing = true
        let generation = session.generation
        let id = UUID()
        replaceID = id
        replaceTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.replaceID == id {
                    self.replaceID = nil
                    self.replaceTask = nil
                    if self.session.generation == generation { self.session.isReplacing = false }
                }
            }
            do {
                try Task.checkCancellation()
                guard self.replaceID == id, self.session.generation == generation else { return }
                if capture.method == .local {
                    guard let provider = self.localTextProvider else {
                        self.session.report(.targetAppChanged)
                        return
                    }
                    provider.replacePracticeText(with: text, diff: self.session.diff)
                    try Task.checkCancellation()
                    await self.finishSuccessfully(notice: "Replaced", status: "Replaced")
                    return
                }
                let outcome = try await self.selection.replace(with: text, capture: capture, hidePanel: { self.panel.hide() })
                try Task.checkCancellation()
                guard self.replaceID == id, self.session.generation == generation else { return }
                switch outcome {
                case .verified:
                    // Paste path hid the panel; only flash the confirmation when it's visible.
                    await self.finishSuccessfully(notice: "Replaced", status: "Replaced")
                case .pasteUnverified:
                    self.settings.recordUse()
                    if self.session.generation == generation { self.closePanel(status: "Pasted. Check the result") }
                case .axUnverified:
                    self.panel.reshow()
                    self.session.report(.api("The replacement could not be verified. The result is still available to copy."))
                }
            } catch {
                guard self.replaceID == id, self.session.generation == generation else { return }
                self.panel.reshow()
                self.session.report(Self.map(error))
            }
        }
    }

    func copyResult(closeAfter: Bool = false) {
        guard let text = session.copyableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if closeAfter {
            Task { await finishSuccessfully(notice: "Copied. Paste it wherever you need it.", status: "Copied") }
        } else {
            settings.recordUse()
            session.note("Copied to the clipboard")
        }
    }

    /// Shows a short confirmation in the panel, then closes it.
    private func finishSuccessfully(notice: String, status: String) async {
        let generation = session.generation
        settings.recordUse()
        session.note(notice)
        AccessibilityNotification.Announcement(notice).post()
        try? await Task.sleep(for: .milliseconds(650))
        // Only close the session this confirmation belongs to.
        if session.generation == generation {
            closePanel(status: status)
        } else {
            self.status = status
        }
    }

    /// One-time tips that teach features after the user has used the basics.
    private func nextTip() -> String? {
        let uses = settings.totalUses
        if uses >= 3, !settings.hasShownTip("repeat"), let shortcut = settings.repeatShortcut {
            settings.markTipShown("repeat")
            return "Tip: \(shortcut.displayString) repeats your last action on new text."
        }
        if uses >= 6, !settings.hasShownTip("custom") {
            settings.markTipShown("custom")
            return "Tip: type your own instruction below, like “translate to Spanish”."
        }
        if uses >= 10, !settings.hasShownTip("presets"), presets.selected == nil {
            settings.markTipShown("presets")
            return "Tip: a style preset (e.g. “use British spelling”) applies your preferences every time."
        }
        return nil
    }

    func repeatLastAction() {
        guard !isCapturing else { return }
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
        cancelReplace()
        panel.close()
        session.reset()
        if let status { self.status = status }
    }

    private func panelClosed() {
        cancelRun()
        cancelReplace()
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

    private func cancelReplace() {
        replaceID = nil
        replaceTask?.cancel()
        replaceTask = nil
        session.isReplacing = false
    }

    private func endRun(status: String) {
        isWorking = false
        self.status = status
    }

    private func configurationProblem() -> TajpoError? {
        if isDemo { return nil }
        return needsAPIKey ? .missingAPIKey : nil
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

    func reportProblem() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        let body = """
        **What happened?**


        **Which app were you writing in?**


        ---
        Tajpo \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(arch)
        """
        var components = URLComponents(string: "https://github.com/TrainABit/tajpo/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func showSettings(tab: SettingsTab = .general) {
        settingsWindow.show(tab: tab)
    }

    /// Opens the setup guide, optionally at a specific step (see `OnboardingStep`).
    func showOnboarding(at step: Int? = nil) {
        if let step {
            UserDefaults.standard.set(step, forKey: OnboardingStep.storageKey)
            onboardingWindow.close()
        }
        onboardingWindow.show()
    }

    func celebrateMenuBarIcon() {
        celebrating = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            celebrating = false
        }
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
            .credits: NSAttributedString(string: "Select text anywhere, press a shortcut, and improve it. Your text goes only to the AI provider you configure.\n\nSupport: github.com/TrainABit/tajpo/issues")
        ])
    }

    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            let message = try LaunchAtLogin.setEnabled(enabled)
            refreshStatus()
            return message
        } catch {
            refreshStatus()
            return error.localizedDescription
        }
    }

    // MARK: API key

    func invalidateAPIKeyValidation() {
        if settings.usesOpenAI { apiKeyValidated = false }
    }

    /// Tests a candidate key before replacing a previously working key. A
    /// failed candidate is never written to the Keychain.
    func saveAndValidateAPIKey(_ text: String) async throws {
        guard settings.usesOpenAI, !isDemo else { throw TajpoError.missingAPIKey }
        let candidate = try APIKeyValidator.validate(text)
        let client = makeClient(candidate, settings.baseURL, settings.projectID)
        try await client.testConnection(model: settings.model)
        try keyStore.save(candidate)
        refreshStatus()
        // refreshStatus invalidates when the hint changes; the candidate was
        // just tested, so record that validation after refreshing the hint.
        apiKeyValidated = true
    }

    func removeAPIKey() throws {
        try keyStore.delete()
        apiKeyValidated = false
        refreshStatus()
    }

    /// Checks the saved key, credit, and model with a tiny request.
    func testConnection() async throws {
        if isDemo { return }
        if settings.usesOpenAI && apiKeyHint == nil { throw TajpoError.missingAPIKey }
        let key: String?
        let project: String?
        if settings.usesOpenAI {
            key = try keyStore.load()
            project = settings.projectID
        } else {
            key = nil
            project = nil
        }
        let client = makeClient(key, settings.baseURL, project)
        try await client.testConnection(model: settings.model)
        if settings.usesOpenAI { apiKeyValidated = true }
    }
}
