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
    case rateLimited
    case emptyResponse
    case cancelled
    case invalidEndpoint
    case localServerUnreachable
    case updateCheckFailed
    case launchAtLoginFailed
    case network(String)
    case api(String)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings, or switch to a local server that does not need a key."
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
        case .rateLimited:
            "The model rate limit was reached. Tajpo retried automatically; wait a moment or check billing limits."
        case .emptyResponse:
            "The model returned no text."
        case .cancelled:
            "The rewrite was cancelled."
        case .invalidEndpoint:
            "The API base URL is invalid. Use a full URL such as https://api.openai.com/v1 or http://127.0.0.1:11434/v1."
        case .localServerUnreachable:
            "The local model server did not respond. Start Ollama, llama.cpp, or an MLX server and check the base URL."
        case .updateCheckFailed:
            "Could not check GitHub for a newer Tajpo release."
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
    public static let string = "1.1.0"
    public static let build = "11"
}
