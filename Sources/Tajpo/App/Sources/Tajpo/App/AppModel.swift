import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var status = "Ready"
    var isWorking = false

    private let hotkey: GlobalHotkeyRegistering
    private let textSelection: TextSelectionServing
    private let keyStore: APIKeyStoring

    init(
        hotkey: GlobalHotkeyRegistering = CarbonGlobalHotkey(),
        textSelection: TextSelectionServing = AccessibilityTextSelectionService(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore()
    ) {
        self.hotkey = hotkey
        self.textSelection = textSelection
        self.keyStore = keyStore
    }

    func start() {
        do {
            try hotkey.registerDefault { [weak self] in
                Task { @MainActor in await self?.rewriteSelection() }
            }
            status = "Ready - press ⌥⌘T"
        } catch {
            status = error.localizedDescription
        }
    }

    func rewriteSelection() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let text = try textSelection.readSelectedText()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TajpoError.noSelection
            }
            guard let apiKey = try keyStore.load(), !apiKey.isEmpty else {
                throw TajpoError.missingAPIKey
            }
            let client: any LLMClient = OpenAIClient(apiKey: apiKey)
            let rewritten = try await client.rewrite(text, instruction: .improve)
            try textSelection.replaceSelectedText(with: rewritten)
            status = "Rewritten"
        } catch {
            status = error.localizedDescription
        }
    }
}

enum TajpoError: LocalizedError {
    case noSelection, missingAPIKey, accessibilityPermissionRequired, replacementNotImplemented

    var errorDescription: String? {
        switch self {
        case .noSelection: "Select text first."
        case .missingAPIKey: "Add an OpenAI API key in Settings."
        case .accessibilityPermissionRequired: "Grant Tajpo Accessibility access in System Settings."
        case .replacementNotImplemented: "Text replacement is the next implementation step."
        }
    }
}
