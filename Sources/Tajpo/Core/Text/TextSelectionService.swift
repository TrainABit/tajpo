import AppKit
import ApplicationServices
import Carbon

struct TextCapture {
    let text: String
    let element: AXUIElement?
    let sourceApp: NSRunningApplication?
}

@MainActor
final class TextSelectionService {
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func capture() async throws -> TextCapture {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            throw TajpoError.accessibilityPermissionRequired
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if let element = focusedElement() {
            try rejectSecureElement(element)
            if let text = selectedText(in: element) {
                try SelectionValidator.validate(text)
                return TextCapture(text: text, element: element, sourceApp: runningApp(for: element, fallback: frontmost))
            }
        }

        let text = try await copySelectionWithClipboard()
        try SelectionValidator.validate(text)
        return TextCapture(text: text, element: nil, sourceApp: frontmost)
    }

    func replace(with text: String, capture: TextCapture) async throws {
        if let element = capture.element {
            try rejectSecureElement(element)
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                return
            }
        }
        try await pastePreservingClipboard(text, into: capture.sourceApp)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return axElement(value)
    }

    private func rejectSecureElement(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 12 {
            if isSecure(node) { throw TajpoError.secureField }
            current = parent(of: node)
            depth += 1
        }
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString) ?? ""
        let description = stringAttribute(element, kAXRoleDescriptionAttribute as CFString) ?? ""
        return role == (kAXSecureTextFieldRole as String)
            || subrole.localizedCaseInsensitiveContains("secure")
            || description.localizedCaseInsensitiveContains("secure")
            || description.localizedCaseInsensitiveContains("password")
    }

    private func selectedText(in element: AXUIElement) -> String? {
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }

    private func copySelectionWithClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general
        let backup = ClipboardBackup(pasteboard)
        defer { backup.restore(to: pasteboard) }
        pasteboard.clearContents()
        postCommandKey(CGKeyCode(kVK_ANSI_C))
        try await Task.sleep(for: .milliseconds(220))
        guard let text = pasteboard.string(forType: .string) else { throw TajpoError.noSelection }
        return text
    }

    private func pastePreservingClipboard(_ text: String, into app: NSRunningApplication?) async throws {
        app?.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(80))
        let pasteboard = NSPasteboard.general
        let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw TajpoError.noSelection }
        postCommandKey(CGKeyCode(kVK_ANSI_V))
        try await Task.sleep(for: .milliseconds(250))
        backup.restore(to: pasteboard)
    }

    private func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else { return nil }
        return axElement(value)
    }

    private func axElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func runningApp(for element: AXUIElement, fallback: NSRunningApplication?) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return fallback }
        return NSRunningApplication(processIdentifier: pid) ?? fallback
    }
}

private struct ClipboardBackup {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } },
                uniquingKeysWith: { _, last in last }
            )
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let objects = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
    }
}
