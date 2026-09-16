import Foundation

public enum CaptureDecision: Equatable, Sendable {
    case useAXText
    case rejectSecure
    case rejectEmpty
    case rejectTooLarge
    case rejectClipboardInWebArea
    case useClipboardFallback
}

public enum SelectionSafety {
    public static let webAreaRoles: Set<String> = [
        "AXWebArea",
        "AXHTMLContent",
        "AXBrowser"
    ]

    public static func isSecureRole(role: String, subrole: String, description: String) -> Bool {
        let roleMatch = role == "AXSecureTextField" || role.localizedCaseInsensitiveContains("secure")
        let subroleMatch = subrole.localizedCaseInsensitiveContains("secure")
        let descriptionMatch = description.localizedCaseInsensitiveContains("secure")
            || description.localizedCaseInsensitiveContains("password")
        return roleMatch || subroleMatch || descriptionMatch
    }

    public static func looksLikePassword(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let bullets = CharacterSet(charactersIn: "•●∙○◦‣*•")
        return trimmed.unicodeScalars.allSatisfy { bullets.contains($0) }
    }

    public static func allowsClipboardFallback(focusedRole: String?) -> Bool {
        guard let focusedRole, !focusedRole.isEmpty else { return true }
        return !webAreaRoles.contains(focusedRole)
    }

    public static func decision(
        focusedRole: String?,
        selectedText: String?,
        ancestorOrDescendantSecure: Bool,
        selectedLooksLikePassword: Bool
    ) -> CaptureDecision {
        if ancestorOrDescendantSecure || selectedLooksLikePassword {
            return .rejectSecure
        }
        if let selectedText {
            do {
                try SelectionValidator.validate(selectedText)
                return .useAXText
            } catch TajpoError.noSelection {
                return .rejectEmpty
            } catch TajpoError.textTooLarge {
                return .rejectTooLarge
            } catch {
                return .rejectEmpty
            }
        }
        if !allowsClipboardFallback(focusedRole: focusedRole) {
            return .rejectClipboardInWebArea
        }
        return .useClipboardFallback
    }
}

public struct HostAppCase: Identifiable, Equatable, Sendable {
    public let id: String
    public let app: String
    public let scenario: String
    public let focusedRole: String?
    public let selectedText: String?
    public let secureContext: Bool
    public let expected: CaptureDecision

    public init(
        app: String,
        scenario: String,
        focusedRole: String?,
        selectedText: String?,
        secureContext: Bool,
        expected: CaptureDecision
    ) {
        id = "\(app) - \(scenario)"
        self.app = app
        self.scenario = scenario
        self.focusedRole = focusedRole
        self.selectedText = selectedText
        self.secureContext = secureContext
        self.expected = expected
    }
}

public enum HostAppMatrix {
    public static let cases: [HostAppCase] = [
        HostAppCase(app: "Notes", scenario: "plain selection", focusedRole: "AXTextArea", selectedText: "hello", secureContext: false, expected: .useAXText),
        HostAppCase(app: "Safari", scenario: "web paragraph", focusedRole: "AXWebArea", selectedText: "rewrite this", secureContext: false, expected: .useAXText),
        HostAppCase(app: "Safari", scenario: "web area without AX text", focusedRole: "AXWebArea", selectedText: nil, secureContext: false, expected: .rejectClipboardInWebArea),
        HostAppCase(app: "Safari", scenario: "password field", focusedRole: "AXWebArea", selectedText: "••••••", secureContext: true, expected: .rejectSecure),
        HostAppCase(app: "Chrome", scenario: "password descendant", focusedRole: "AXWebArea", selectedText: nil, secureContext: true, expected: .rejectSecure),
        HostAppCase(app: "Slack", scenario: "message box", focusedRole: "AXTextField", selectedText: "ship it", secureContext: false, expected: .useAXText),
        HostAppCase(app: "VS Code", scenario: "editor", focusedRole: "AXTextArea", selectedText: "func main()", secureContext: false, expected: .useAXText),
        HostAppCase(app: "Electron", scenario: "no AX text, not web", focusedRole: "AXGroup", selectedText: nil, secureContext: false, expected: .useClipboardFallback),
        HostAppCase(app: "System Settings", scenario: "empty selection", focusedRole: "AXTextField", selectedText: "   ", secureContext: false, expected: .rejectEmpty),
        HostAppCase(app: "Keychain Access", scenario: "secure field role", focusedRole: "AXSecureTextField", selectedText: "secret", secureContext: true, expected: .rejectSecure)
    ]
}
