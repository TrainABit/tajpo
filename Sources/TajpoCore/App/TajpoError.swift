import Foundation

public enum TajpoError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case accessibilityPermissionRequired
    case noSelection
    case secureField
    case textTooLarge
    case hotkeyUnavailable
    case hotkeyNeedsModifier
    case nothingToRepeat
    case nothingToUndo
    case nothingToRedo
    case rateLimited(retryAfter: TimeInterval?)
    case emptyResponse
    case emptyContentFiltered
    case cancelled
    case invalidEndpoint
    case insecureEndpoint
    case localServerUnreachable
    case updateCheckFailed
    case releaseSourceUnavailable
    case activationFailed
    case replaceTargetChanged
    case streamStalled
    case launchAtLoginFailed
    case network(String)
    case api(String)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your API key in Settings, or switch to the on-device demo / a local server."
        case .accessibilityPermissionRequired:
            "Allow Tajpo in System Settings > Privacy & Security > Accessibility, then try again."
        case .noSelection:
            "No selected text found. Select text in another app and try again."
        case .secureField:
            "Tajpo will not read or replace text in password or secure fields."
        case .textTooLarge:
            "The selection is too large. Select fewer than 100,000 characters."
        case .hotkeyUnavailable:
            "That global shortcut is already in use. Choose another one in Settings."
        case .hotkeyNeedsModifier:
            "The global shortcut needs at least one modifier key so it does not steal a regular keystroke."
        case .nothingToRepeat:
            "There is no previous action to repeat yet."
        case .nothingToUndo:
            "There is no replacement to undo yet."
        case .nothingToRedo:
            "There is nothing to redo yet."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                "The model rate limit was reached. Tajpo retried automatically; the server asked to wait \(Int(retryAfter.rounded(.up)))s. Check billing limits."
            } else {
                "The model rate limit was reached. Tajpo retried automatically; wait a moment or check billing limits."
            }
        case .emptyResponse:
            "The model returned no text."
        case .emptyContentFiltered:
            "The model refused the text or filtered every reply. Adjust the selection or the extra instructions."
        case .cancelled:
            "The rewrite was cancelled."
        case .invalidEndpoint:
            "The API base URL is invalid. Use a full URL such as https://api.openai.com/v1 or http://127.0.0.1:11434/v1."
        case .insecureEndpoint:
            "The API base URL must use HTTPS to receive an API key. Plain HTTP is only allowed for loopback servers such as http://127.0.0.1:11434/v1."
        case .localServerUnreachable:
            "The local model server did not respond. Start Ollama, llama.cpp, or an MLX server and check the base URL."
        case .updateCheckFailed:
            "Could not check GitHub for a newer Tajpo release."
        case .releaseSourceUnavailable:
            "The release repository is unavailable or private. Point Tajpo at a public GitHub repository in Settings to check for updates."
        case .activationFailed:
            "Tajpo could not bring the target app to the front to paste. Nothing was changed — select the text and try again."
        case .replaceTargetChanged:
            "The selected text changed since the rewrite started. Re-select the passage and try again."
        case .streamStalled:
            "The model stopped responding mid-stream. Try again or check the server."
        case .launchAtLoginFailed:
            "Could not change Launch at Login. Place Tajpo in Applications and try again."
        case .network(let detail):
            "Network error: \(detail)"
        case .api(let detail):
            "Model error: \(detail)"
        case .keychain:
            "Could not access the API key in Keychain."
        }
    }
}

public enum SelectionValidator {
    public static let maximumCharacters = 100_000

    public static func validate(_ text: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TajpoError.noSelection
        }
        if text.count > maximumCharacters {
            throw TajpoError.textTooLarge
        }
    }
}

public enum APIKeyValidator {
    public static func validate(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TajpoError.missingAPIKey }
        return trimmed
    }

    public static func optional(_ key: String?) -> String {
        key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public enum AppVersion {
    public static let string = "1.2.0"
    public static let build = "12"
}
