import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Ready"
    @Published var isWorking = false
    @Published var isError = false
    @Published var action: RewriteAction = .correct
    @Published var tone: RewriteTone = .professional
    @Published var preview = ""

    let settings = AppSettings()
    let presets = PresetStore()

    private let selection: TextSelectionService
    private let keyStore: APIKeyStoring
    private let panel = InlinePanelController()
    private var hotkey: GlobalHotkey?
    private var currentCapture: TextCapture?
    private var generateTask: Task<Void, Never>?
    private var didStart = false
    private var lastAction: RewriteAction?
    private var lastTone: RewriteTone?

    init(
        selection: TextSelectionService = TextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore()
    ) {
        self.selection = selection
        self.keyStore = keyStore
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        configureHotkey()
        if !UserDefaults.standard.bool(forKey: "completedOnboarding") {
            OnboardingController.shared.show(model: self)
        }
    }

    func configureHotkey() {
        hotkey = nil
        do {
            hotkey = try GlobalHotkey(
                keyCode: settings.hotkeyKeyCode,
                modifiers: settings.hotkeyModifiers
            ) { [weak self] in
                Task { @MainActor in
                    await self?.openInlineRewrite()
                }
            }
            showStatus("Ready - \(settings.hotkeyLabel)")
        } catch {
            show(error)
        }
    }

    func requestAccessibility() {
        selection.requestAccessibilityPermission()
    }

    func openInlineRewrite() async {
        generateTask?.cancel()
        preview = ""
        do {
            currentCapture = try await selection.capture()
            showStatus("Choose an action")
            panel.show(model: self, near: SelectionGeometry.frame(for: currentCapture?.element))
        } catch {
            currentCapture = nil
            show(error)
            panel.show(model: self, near: nil)
        }
    }

    func runCurrentCapture() async {
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

    func applyPreview() async {
        guard let capture = currentCapture, !preview.isEmpty else { return }
        do {
            try await selection.replace(with: preview, capture: capture)
            showStatus("Replaced")
            panel.close()
        } catch {
            show(error)
        }
    }

    func copyPreview() {
        guard !preview.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview, forType: .string)
        showStatus("Copied")
    }

    func rewriteSelection() async {
        await openInlineRewrite()
    }

    func repeatLastAction() async {
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
            await runCurrentCapture()
        } catch {
            show(error)
        }
    }

    func cancelWork() {
        generateTask?.cancel()
        generateTask = nil
        isWorking = false
    }

    private func generate(_ text: String) async {
        do {
            let key = try APIKeyValidator.validate(try keyStore.load() ?? "")
            isWorking = true
            isError = false
            preview = ""
            defer { isWorking = false }
            lastAction = action
            lastTone = tone
            let client = OpenAIClient(apiKey: key, model: settings.model)
            preview = try await client.rewrite(text, action: action, tone: tone, preset: presets.selected) { [weak self] partial in
                self?.preview = partial
                self?.status = "Writing... \(partial.count) characters"
            }
            showStatus("Ready to replace")
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
