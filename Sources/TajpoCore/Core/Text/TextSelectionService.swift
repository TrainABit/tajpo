import AppKit
@preconcurrency import ApplicationServices
import Carbon

public struct TextCapture: @unchecked Sendable {
    public let text: String
    public let element: AXUIElement?
    public let sourceApp: NSRunningApplication?

    public init(text: String, element: AXUIElement?, sourceApp: NSRunningApplication?) {
        self.text = text
        self.element = element
        self.sourceApp = sourceApp
    }
}

@MainActor
public protocol TextSelectionServing: AnyObject {
    var isTrusted: Bool { get }
    func requestAccessibilityPermission()
    func capture() async throws -> TextCapture
    func replace(with text: String, capture: TextCapture) async throws
}

@MainActor
public final class TextSelectionService: TextSelectionServing {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public func capture() async throws -> TextCapture {
        guard isTrusted else {
            requestAccessibilityPermission()
            throw TajpoError.accessibilityPermissionRequired
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if let element = focusedElement() {
            let role = stringAttribute(element, kAXRoleAttribute as CFString)
            try rejectSecureContext(element)
            if let text = selectedText(in: element) {
                if SelectionSafety.looksLikePassword(text) { throw TajpoError.secureField }
                try SelectionValidator.validate(text)
                return TextCapture(text: text, element: element, sourceApp: runningApp(for: element, fallback: frontmost))
            }
            if !SelectionSafety.allowsClipboardFallback(focusedRole: role) {
                throw TajpoError.noSelection
            }
        }

        let text = try await copySelectionWithClipboard()
        if SelectionSafety.looksLikePassword(text) { throw TajpoError.secureField }
        try SelectionValidator.validate(text)
        return TextCapture(text: text, element: nil, sourceApp: frontmost)
    }

    public func replace(with text: String, capture: TextCapture) async throws {
        if let element = capture.element {
            try rejectSecureContext(element)
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

    private func rejectSecureContext(_ element: AXUIElement) throws {
        if hasSecureAncestor(element) || hasSecureDescendant(element, depth: 0) {
            throw TajpoError.secureField
        }
    }

    private func hasSecureAncestor(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 12 {
            if isSecure(node) { return true }
            current = parent(of: node)
            depth += 1
        }
        return false
    }

    private func hasSecureDescendant(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 4 else { return false }
        if isSecure(element) { return true }
        for child in children(of: element).prefix(12) {
            if hasSecureDescendant(child, depth: depth + 1) { return true }
        }
        return false
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        SelectionSafety.isSecureRole(
            role: stringAttribute(element, kAXRoleAttribute as CFString) ?? "",
            subrole: stringAttribute(element, kAXSubroleAttribute as CFString) ?? "",
            description: stringAttribute(element, kAXRoleDescriptionAttribute as CFString) ?? ""
        )
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

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let value else { return [] }
        let array = value as? [Any] ?? []
        return array.compactMap { item in
            axElement(item as AnyObject)
        }
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

public final class MockTextSelectionService: TextSelectionServing {
    public var isTrusted: Bool
    public var capturedText: String
    public var replacedText: String?
    public var replacements: [(original: String, replacement: String)] = []

    public init(isTrusted: Bool = true, capturedText: String = "hello") {
        self.isTrusted = isTrusted
        self.capturedText = capturedText
    }

    public func requestAccessibilityPermission() {}

    public func capture() async throws -> TextCapture {
        guard isTrusted else { throw TajpoError.accessibilityPermissionRequired }
        try SelectionValidator.validate(capturedText)
        return TextCapture(text: capturedText, element: nil, sourceApp: nil)
    }

    public func replace(with text: String, capture: TextCapture) async throws {
        replacements.append((original: capture.text, replacement: text))
        replacedText = text
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
