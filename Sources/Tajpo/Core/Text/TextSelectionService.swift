import AppKit
import ApplicationServices

struct TextCapture { let text: String; let element: AXUIElement? }

@MainActor
final class TextSelectionService {
    private let maximumCharacters = 100_000

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func capture() async throws -> TextCapture {
        guard AXIsProcessTrusted() else { requestAccessibilityPermission(); throw TajpoError.accessibilityPermissionRequired }
        if let element = focusedElement() {
            try rejectSecureElement(element)
            if let text = selectedText(in: element) {
                try validate(text)
                return TextCapture(text: text, element: element)
            }
        }
        let text = try await copySelectionWithClipboard()
        try validate(text)
        return TextCapture(text: text, element: nil)
    }

    func replace(with text: String, capture: TextCapture) async throws {
        if let element = capture.element {
            try rejectSecureElement(element)
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success { return }
        }
        try await pastePreservingClipboard(text)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide(); var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private func rejectSecureElement(_ element: AXUIElement) throws {
        var roleValue: CFTypeRef?; var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        let role = roleValue as? String ?? ""; let subrole = subroleValue as? String ?? ""
        if role == kAXSecureTextFieldRole as String || subrole.localizedCaseInsensitiveContains("secure") { throw TajpoError.secureField }
    }

    private func selectedText(in element: AXUIElement) -> String? {
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return selected as? String
    }

    private func validate(_ text: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw TajpoError.noSelection }
        if text.count > maximumCharacters { throw TajpoError.textTooLarge }
    }

    private func copySelectionWithClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general; let backup = ClipboardBackup(pasteboard)
        defer { backup.restore(to: pasteboard) }
        pasteboard.clearContents(); postCommandKey(CGKeyCode(kVK_ANSI_C)); try await Task.sleep(for: .milliseconds(220))
        guard let text = pasteboard.string(forType: .string) else { throw TajpoError.noSelection }
        return text
    }

    private func pastePreservingClipboard(_ text: String) async throws {
        let pasteboard = NSPasteboard.general; let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents(); guard pasteboard.setString(text, forType: .string) else { throw TajpoError.noSelection }
        postCommandKey(CGKeyCode(kVK_ANSI_V)); try await Task.sleep(for: .milliseconds(250)); backup.restore(to: pasteboard)
    }

    private func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}

private struct ClipboardBackup {
    let items: [[NSPasteboard.PasteboardType: Data]]
    init(_ pasteboard: NSPasteboard) { items = (pasteboard.pasteboardItems ?? []).map { item in Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }) } }
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let objects = items.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
    }
}
