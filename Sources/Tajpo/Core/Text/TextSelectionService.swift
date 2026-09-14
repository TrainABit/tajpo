import AppKit
import ApplicationServices

struct TextCapture { let text: String; let element: AXUIElement?; let usedClipboard: Bool }

@MainActor
final class TextSelectionService {
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func capture() async throws -> TextCapture {
        guard AXIsProcessTrusted() else { requestAccessibilityPermission(); throw TajpoError.accessibilityPermissionRequired }
        if let pair = focusedElementAndSelection() { return TextCapture(text: pair.1, element: pair.0, usedClipboard: false) }
        let text = try await copySelectionWithClipboard()
        return TextCapture(text: text, element: nil, usedClipboard: true)
    }

    func replace(with text: String, capture: TextCapture) async throws {
        if let element = capture.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success { return }
        try await pastePreservingClipboard(text)
    }

    private func focusedElementAndSelection() -> (AXUIElement, String)? {
        let system = AXUIElementCreateSystemWide(); var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        let element = value as! AXUIElement; var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.isEmpty else { return nil }
        return (element, text)
    }

    private func copySelectionWithClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general; let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents(); postCommandKey(CGKeyCode(kVK_ANSI_C)); try await Task.sleep(for: .milliseconds(180))
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { backup.restore(to: pasteboard); throw TajpoError.noSelection }
        backup.restore(to: pasteboard); return text
    }

    private func pastePreservingClipboard(_ text: String) async throws {
        let pasteboard = NSPasteboard.general; let backup = ClipboardBackup(pasteboard)
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        postCommandKey(CGKeyCode(kVK_ANSI_V)); try await Task.sleep(for: .milliseconds(180)); backup.restore(to: pasteboard)
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
    func restore(to pasteboard: NSPasteboard) { pasteboard.clearContents(); let restored = items.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); values.forEach { item.setData($1, forType: $0) }; return item }; pasteboard.writeObjects(restored) }
}
