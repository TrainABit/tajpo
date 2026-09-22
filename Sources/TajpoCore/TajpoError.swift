import Foundation

/// What the UI can offer next to an error.
public enum RecoveryAction: String, Sendable, Equatable {
    case openSettings
    case openAccessibilitySettings
    case openBilling
    case openAPIKeys
    case retry
}

public enum TajpoError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKeyFormat
    case invalidAPIKey(String)
    case insufficientQuota
    case rateLimited(retryAfterSeconds: Int?)
    case modelNotFound(String)
    case invalidModel(String)
    case invalidBaseURL
    case serverError(Int)
    case api(String)
    case network(String)
    case emptyResponse
    case outputTruncated
    case contentFiltered
    case incompleteResponse
    case cancelled
    case accessibilityPermissionRequired
    case noSelection
    case selectionInTajpo
    case secureField
    case textTooLarge
    case textTooLargeForModel(maximumCharacters: Int)
    case busy
    case selectionChanged
    case targetAppChanged
    case replaceNotSupported
    case replaceFailed
    case pasteboardUnavailable
    case pasteboardAccessDenied
    case hotkeyNeedsCommandOrControl
    case hotkeyReserved(String)
    case hotkeyInUse(String)
    case hotkeyRejectedBySystem(String)
    case hotkeyDuplicate
    case keychain(status: Int32, message: String?)
    case nothingToRepeat

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings."
        case .invalidAPIKeyFormat:
            "That doesn't look like an API key. Keys contain no spaces or line breaks; paste it again."
        case .invalidAPIKey(let detail):
            "OpenAI rejected the API key. \(detail)"
        case .insufficientQuota:
            "Your OpenAI account has no API credit. API usage is billed separately from ChatGPT; add credit in your OpenAI billing settings."
        case .rateLimited(let seconds):
            if let seconds {
                "OpenAI rate limit reached. Try again in \(seconds) seconds."
            } else {
                "OpenAI rate limit reached. Wait a moment and try again."
            }
        case .modelNotFound(let detail):
            "The model isn't available to your account. \(detail)"
        case .invalidModel(let detail):
            "Invalid model name. \(detail)"
        case .invalidBaseURL:
            "The server URL must start with http:// or https://."
        case .serverError(let status):
            "OpenAI is having problems (HTTP \(status)). Try again shortly."
        case .api(let detail):
            "OpenAI error: \(detail)"
        case .network(let detail):
            "Network error: \(detail)"
        case .emptyResponse:
            "The model returned no text."
        case .outputTruncated:
            "The result was cut off because it hit the model's length limit. Replace is disabled so your text isn't shortened; select less text or use Shorten."
        case .contentFiltered:
            "The result was stopped by OpenAI's content filter. Replace is disabled."
        case .incompleteResponse:
            "The connection ended before the result was complete. Try again."
        case .cancelled:
            "Cancelled."
        case .accessibilityPermissionRequired:
            "Tajpo needs Accessibility access to read and replace selected text."
        case .noSelection:
            "No selected text found. Select text in another app and try again."
        case .selectionInTajpo:
            "Select text in another app, then press the shortcut."
        case .secureField:
            "Tajpo will not read or replace text in password or secure fields."
        case .textTooLarge:
            "The selection is too large. Select 100,000 characters or fewer."
        case .textTooLargeForModel(let maximum):
            "The selection is too long for this model to return in full. Select about \(maximum.formatted()) characters or fewer."
        case .busy:
            "Tajpo is still working on the previous request."
        case .selectionChanged:
            "The selection changed since Tajpo read it, so nothing was replaced. Copy the result instead, or select the text again."
        case .targetAppChanged:
            "The original app isn't in front anymore, so nothing was pasted. Copy the result instead."
        case .replaceNotSupported:
            "This text can't be edited here. Copy the result instead."
        case .replaceFailed:
            "The app didn't accept the replacement. Copy the result instead."
        case .pasteboardUnavailable:
            "Tajpo couldn't use the clipboard."
        case .pasteboardAccessDenied:
            "Tajpo isn't allowed to read the clipboard. Allow it in System Settings > Privacy & Security > Paste from Other Apps."
        case .hotkeyNeedsCommandOrControl:
            "Shortcuts must include ⌘ or ⌃ so they don't block normal typing."
        case .hotkeyReserved(let shortcut):
            "\(shortcut) is a standard system shortcut. Choose another one."
        case .hotkeyInUse(let shortcut):
            "\(shortcut) is already used by another app. Choose another one."
        case .hotkeyRejectedBySystem(let shortcut):
            "macOS refused \(shortcut). Choose a shortcut that includes ⌘ or ⌃."
        case .hotkeyDuplicate:
            "Both actions can't use the same shortcut."
        case .keychain(let status, let message):
            "Could not access the API key in Keychain (\(message ?? "error \(status)"))."
        case .nothingToRepeat:
            "There is no previous action to repeat yet."
        }
    }

    public var recoveryAction: RecoveryAction? {
        switch self {
        case .missingAPIKey, .invalidAPIKeyFormat, .modelNotFound, .invalidModel, .invalidBaseURL:
            .openSettings
        case .invalidAPIKey:
            .openAPIKeys
        case .insufficientQuota:
            .openBilling
        case .accessibilityPermissionRequired:
            .openAccessibilitySettings
        case .rateLimited, .serverError, .network, .incompleteResponse, .emptyResponse, .api:
            .retry
        default:
            nil
        }
    }

    /// Errors after which the preview can still be copied but must not replace text.
    public var blocksReplace: Bool {
        self == .outputTruncated || self == .contentFiltered || self == .incompleteResponse
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

    /// Rough token estimate: about four ASCII characters per token, and one
    /// token per non-ASCII character (a conservative bound for CJK and emoji).
    public static func estimatedTokens(_ text: String) -> Int {
        var ascii = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { other += 1 }
        }
        return (ascii + 3) / 4 + other
    }

    /// Rejects text whose rewrite would not fit in the model's output limit.
    public static func validate(_ text: String, action: RewriteAction, model: String) throws {
        try validate(text)
        guard action != .shorten else { return }
        let limit = ModelCatalog.outputTokenLimit(for: model)
        let budget = limit * 8 / 10
        let tokens = estimatedTokens(text)
        if tokens > budget {
            let maximum = max(1, text.count * budget / max(tokens, 1))
            throw TajpoError.textTooLargeForModel(maximumCharacters: maximum >= 1000 ? maximum / 1000 * 1000 : maximum)
        }
    }
}

public enum APIKeyValidator {
    public static func validate(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TajpoError.missingAPIKey }
        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw TajpoError.invalidAPIKeyFormat
        }
        return trimmed
    }

    public static func looksLikeOpenAIKey(_ key: String) -> Bool {
        key.hasPrefix("sk-")
    }

    /// "sk-…abcd", safe to show in the UI.
    public static func hint(for key: String) -> String {
        let suffix = key.suffix(4)
        return key.hasPrefix("sk-") ? "sk-…\(suffix)" : "…\(suffix)"
    }
}
