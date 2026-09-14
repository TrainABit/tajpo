import Foundation

enum TajpoError: LocalizedError {
    case missingAPIKey, accessibilityPermissionRequired, noSelection, hotkeyUnavailable, rateLimited, emptyResponse, network(String), api(String), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your OpenAI API key in Settings."
        case .accessibilityPermissionRequired: "Allow Tajpo in System Settings > Privacy & Security > Accessibility, then try again."
        case .noSelection: "No selected text found. Select text in another app and try again."
        case .hotkeyUnavailable: "That global shortcut is already in use. Choose another one in Settings."
        case .rateLimited: "OpenAI rate limit reached. Wait a moment or check your API billing limits."
        case .emptyResponse: "OpenAI returned no text."
        case .network(let detail): "Network error: \(detail)"
        case .api(let detail): "OpenAI error: \(detail)"
        case .keychain: "Could not access the API key in Keychain."
        }
    }
}
