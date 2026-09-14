import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Ready"
    @Published var isWorking = false
    @Published var isError = false
    @Published var action: RewriteAction = .improve
    @Published var tone: RewriteTone = .professional

    let settings = AppSettings()
    private let selection = TextSelectionService()
    private let keyStore = KeychainAPIKeyStore()
    private var hotkey: GlobalHotkey?

    func start() { configureHotkey() }

    func configureHotkey() {
        hotkey = nil
        do {
            hotkey = try GlobalHotkey(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers) { [weak self] in
                Task { @MainActor in await self?.rewriteSelection() }
            }
            status = "Ready - \(settings.hotkeyLabel)"
            isError = false
        } catch { show(error) }
    }

    func requestAccessibility() { selection.requestAccessibilityPermission() }

    func rewriteSelection() async {
        guard !isWorking else { return }
        isWorking = true; isError = false; status = "Reading selection..."
        defer { isWorking = false }
        do {
            guard let key = try keyStore.load(), !key.isEmpty else { throw TajpoError.missingAPIKey }
            let capture = try await selection.capture()
            status = "Rewriting..."
            let client = OpenAIClient(apiKey: key, model: settings.model)
            let output = try await client.rewrite(capture.text, action: action, tone: tone)
            status = "Replacing text..."
            try await selection.replace(with: output, capture: capture)
            status = "Done"; isError = false
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isError = true
    }
}
