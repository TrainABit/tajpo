import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Ready"; @Published var isWorking = false; @Published var isError = false
    @Published var action: RewriteAction = .correct; @Published var tone: RewriteTone = .professional; @Published var preview = ""
    let settings = AppSettings(); let presets = PresetStore()
    private let selection = TextSelectionService(); private let keyStore = KeychainAPIKeyStore(); private let panel = InlinePanelController()
    private var hotkey: GlobalHotkey?; private var currentCapture: TextCapture?

    func start() { configureHotkey(); if !UserDefaults.standard.bool(forKey: "completedOnboarding") { OnboardingController.shared.show(model: self) } }
    func configureHotkey() { hotkey = nil; do { hotkey = try GlobalHotkey(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers) { [weak self] in Task { @MainActor in await self?.openInlineRewrite() } }; showStatus("Ready - \(settings.hotkeyLabel)") } catch { show(error) } }
    func requestAccessibility() { selection.requestAccessibilityPermission() }

    func openInlineRewrite() async {
        do { currentCapture = try await selection.capture(); preview = ""; panel.show(model: self, near: SelectionGeometry.frame(for: currentCapture?.element)) }
        catch { show(error); panel.show(model: self, near: nil) }
    }
    func runCurrentCapture() async {
        guard let capture = currentCapture else { show(TajpoError.noSelection); return }
        do { try await generate(capture.text) } catch { show(error) }
    }
    func applyPreview() async { guard let capture = currentCapture, !preview.isEmpty else { return }; do { try await selection.replace(with: preview, capture: capture); showStatus("Replaced") } catch { show(error) } }
    func copyPreview() { guard !preview.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(preview, forType: .string); showStatus("Copied") }
    func rewriteSelection() async { await openInlineRewrite() }
    func repeatLastAction() async { await runCurrentCapture() }

    private func generate(_ text: String) async throws {
        guard let key = try keyStore.load(), !key.isEmpty else { throw TajpoError.missingAPIKey }
        isWorking = true; isError = false; preview = ""; defer { isWorking = false }
        let client = OpenAIClient(apiKey: key, model: settings.model)
        preview = try await client.rewrite(text, action: action, tone: tone, preset: presets.selected) { [weak self] partial in self?.preview = partial; self?.status = "Writing... \(partial.count) characters" }
        showStatus("Ready to replace")
    }
    private func showStatus(_ message: String) { status = message; isError = false }
    private func show(_ error: Error) { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; isError = true; isWorking = false }
}
