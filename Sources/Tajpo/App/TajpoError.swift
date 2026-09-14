import Foundation

enum TajpoError: LocalizedError, Equatable {
    case missingAPIKey
    case accessibilityPermissionRequired
    case noSelection
    case secureField
    case textTooLarge
    case hotkeyUnavailable
    case hotkeyNeedsModifier
    case nothingToRepeat
    case rateLimited
    case emptyResponse
    case cancelled
    case network(String)
    case api(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings."
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
        case .rateLimited:
            "OpenAI rate limit reached. Wait a moment or check your API billing limits."
        case .emptyResponse:
            "OpenAI returned no text."
        case .cancelled:
            "The rewrite was cancelled."
        case .network(let detail):
            "Network error: \(detail)"
        case .api(let detail):
            "OpenAI error: \(detail)"
        case .keychain:
            "Could not access the API key in Keychain."
        }
    }
}

enum SelectionValidator {
    static let maximumCharacters = 100_000

    static func validate(_ text: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TajpoError.noSelection
        }
        if text.count > maximumCharacters {
            throw TajpoError.textTooLarge
        }
    }
}

enum APIKeyValidator {
    static func validate(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TajpoError.missingAPIKey }
        return trimmed
    }
}
