import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Ready"
    @Published var isWorking = false
    @Published var isError = false
    @Published var action: RewriteAction = .improve
    @Published var tone: RewriteTone = .professional
    @Published private(set) var streamedCharacterCount = 0

    let settings = AppSettings()
    private let selection = TextSelectionService()
    private let keyStore = KeychainAPIKeyStore()
    private var hotkey: GlobalHotkey?
    private var lastInput: String?
    private var lastOutput: String?

    func start() { configureHotkey() }

    func configureHotkey() {
        hotkey = nil
        do {
            hotkey = try GlobalHotkey(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers) { [weak self] in
                Task { @MainActor in await self?.rewriteSelection() }
            }
            showStatus("Ready - \(settings.hotkeyLabel)")
        } catch { show(error) }
    }

    func requestAccessibility() { selection.requestAccessibilityPermission() }

    func rewriteSelection() async {
        guard !isWorking else { return }
        do {
            let capture = try await selection.capture()
            lastInput = capture.text
            try await run(text: capture.text, capture: capture)
        } catch { show(error) }
    }

    func repeatLastAction() async {
        guard let text = lastInput else { show(TajpoError.nothingToRepeat); return }
        do { try await run(text: text, capture: nil) } catch { show(error) }
    }

    private func run(text: String, capture: TextCapture?) async throws {
        guard !isWorking else { return }
        guard let key = try keyStore.load(), !key.isEmpty else { throw TajpoError.missingAPIKey }
        isWorking = true; isError = false; streamedCharacterCount = 0; showStatus("Contacting OpenAI...")
        defer { isWorking = false }
        let client = OpenAIClient(apiKey: key, model: settings.model)
        let output = try await client.rewrite(text, action: action, tone: tone) { [weak self] partial in
            self?.streamedCharacterCount = partial.count
            self?.status = "Writing... \(partial.count) characters"
        }
        lastOutput = output
        if let capture {
            showStatus("Replacing selection...")
            try await selection.replace(with: output, capture: capture)
            showStatus("Done")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
            showStatus("Repeated result copied")
        }
    }

    private func showStatus(_ message: String) { status = message; isError = false }
    private func show(_ error: Error) { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; isError = true; isWorking = false }
}
