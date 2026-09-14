import AppKit
import ApplicationServices

protocol TextSelectionServing: Sendable {
    func readSelectedText() throws -> String
    func replaceSelectedText(with text: String) throws
}

struct AccessibilityTextSelectionService: TextSelectionServing {
    func readSelectedText() throws -> String {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            throw TajpoError.accessibilityPermissionRequired
        }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { throw TajpoError.noSelection }

        var selected: CFTypeRef?
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { throw TajpoError.noSelection }
        return text
    }

    func replaceSelectedText(with text: String) throws {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { throw TajpoError.noSelection }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard status == .success else { throw TajpoError.replacementNotImplemented }
    }
}
