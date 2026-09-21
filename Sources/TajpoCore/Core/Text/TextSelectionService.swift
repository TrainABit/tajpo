import AppKit
@preconcurrency import ApplicationServices
import Carbon

public struct TextCapture: @unchecked Sendable {
    public let text: String
    public let element: AXUIElement?
    public let sourceApp: NSRunningApplication?
    /// Identity contract: the pid that owned the captured element.
    public let pid: pid_t?
    /// UTF-16 range of the selection inside the element, when available.
    public let utf16Range: NSRange?

    public init(
        text: String,
        element: AXUIElement?,
        sourceApp: NSRunningApplication?,
        pid: pid_t? = nil,
        utf16Range: NSRange? = nil
    ) {
        self.text = text
        self.element = element
        self.sourceApp = sourceApp
        self.pid = pid
        self.utf16Range = utf16Range
    }
}

/// Receipt for a completed mutation. Undo/redo revalidate against it before
/// writing again, so a stack step never mutates an unrelated destination.
public struct MutationReceipt: @unchecked Sendable {
    public let pid: pid_t?
    public let element: AXUIElement?
    public let replacedContent: String
    public let writtenContent: String
    public let utf16Range: NSRange?

    public init(
        pid: pid_t?,
        element: AXUIElement?,
        replacedContent: String,
        writtenContent: String,
        utf16Range: NSRange?
    ) {
        self.pid = pid
        self.element = element
        self.replacedContent = replacedContent
        self.writtenContent = writtenContent
        self.utf16Range = utf16Range
    }
}

@MainActor
public protocol TextSelectionServing: AnyObject {
    var isTrusted: Bool { get }
    func requestAccessibilityPermission()
    func capture() async throws -> TextCapture
    @discardableResult
    func replace(with text: String, capture: TextCapture) async throws -> MutationReceipt
    /// Best-effort check that a receipt still describes the live destination.
    func verify(_ receipt: MutationReceipt) throws
}

public extension TextSelectionServing {
    func verify(_ receipt: MutationReceipt) throws {}
}

@MainActor
public final class TextSelectionService: TextSelectionServing {
    private let clipboardTransactions = ClipboardTransactionCoordinator()

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
                return TextCapture(
                    text: text,
                    element: element,
                    sourceApp: runningApp(for: element, fallback: frontmost),
                    pid: elementPID(element) ?? frontmost?.processIdentifier,
                    utf16Range: selectedRange(in: element)
                )
            }
            if !SelectionSafety.allowsClipboardFallback(focusedRole: role) {
                throw TajpoError.noSelection
            }
        } else if let appElement = appFocusedElement(of: frontmost) {
            // The system-wide focus query failed; before trusting synthetic Cmd+C,
            // verify the frontmost app's focused element is not a secure context.
            try rejectSecureContext(appElement)
        }

        let text = try await copySelectionWithClipboard()
        if SelectionSafety.looksLikePassword(text) { throw TajpoError.secureField }
        try SelectionValidator.validate(text)
        return TextCapture(
            text: text,
            element: nil,
            sourceApp: frontmost,
            pid: frontmost?.processIdentifier
        )
    }

    @discardableResult
    public func replace(with text: String, capture: TextCapture) async throws -> MutationReceipt {
        if let element = capture.element {
            try rejectSecureContext(element)
            try revalidate(capture, element: element)
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                return MutationReceipt(
                    pid: capture.pid,
                    element: element,
                    replacedContent: capture.text,
                    writtenContent: text,
                    utf16Range: capture.utf16Range
                )
            }
        }
        try await pastePreservingClipboard(text, into: capture.sourceApp)
        return MutationReceipt(
            pid: capture.pid,
            element: nil,
            replacedContent: capture.text,
            writtenContent: text,
            utf16Range: nil
        )
    }

    /// Pre-mutation validation: the captured element must still belong to the
    /// captured app and still hold the captured text. A mismatch means the
    /// destination moved on, so nothing is written.
    private func revalidate(_ capture: TextCapture, element: AXUIElement) throws {
        if let expected = capture.pid {
            var elementPID: pid_t = 0
            if AXUIElementGetPid(element, &elementPID) == .success, elementPID != expected {
                throw TajpoError.replaceTargetChanged
            }
        }
        if let current = selectedText(in: element), current != capture.text {
            throw TajpoError.replaceTargetChanged
        }
        if let range = capture.utf16Range,
           let value = stringAttribute(element, kAXValueAttribute as CFString) {
            let utf16 = Array(value.utf16)
            if range.location >= 0, range.length >= 0, range.location + range.length <= utf16.count {
                let slice = String(decoding: utf16[range.location..<(range.location + range.length)], as: UTF16.self)
                if slice != capture.text { throw TajpoError.replaceTargetChanged }
            }
        }
    }

    public func verify(_ receipt: MutationReceipt) throws {
        guard let element = receipt.element else { return }
        if let expected = receipt.pid {
            var elementPID: pid_t = 0
            if AXUIElementGetPid(element, &elementPID) == .success, elementPID != expected {
                throw TajpoError.replaceTargetChanged
            }
        }
        if let current = selectedText(in: element), current != receipt.writtenContent {
            throw TajpoError.replaceTargetChanged
        }
    }

    private func elementPID(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return axElement(value)
    }

    private func appFocusedElement(of app: NSRunningApplication?) -> AXUIElement? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
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
        try await clipboardTransactions.run {
            let pasteboard = NSPasteboard.general
            let backup = ClipboardBackup(pasteboard)
            let ownedChangeCount = pasteboard.clearContents()
            defer {
                if pasteboard.changeCount == ownedChangeCount {
                    backup.restore(to: pasteboard)
                }
            }
            postCommandKey(CGKeyCode(kVK_ANSI_C))
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
            while pasteboard.changeCount == ownedChangeCount {
                if ContinuousClock.now >= deadline { throw TajpoError.noSelection }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard let text = pasteboard.string(forType: .string) else { throw TajpoError.noSelection }
            return text
        }
    }

    private func pastePreservingClipboard(_ text: String, into app: NSRunningApplication?) async throws {
        // Verify the target is actually frontmost before posting any keystroke;
        // an unverified post could paste into the wrong window.
        if let app {
            try await activateAndVerify(app)
        }
        try await clipboardTransactions.run {
            let pasteboard = NSPasteboard.general
            let backup = ClipboardBackup(pasteboard)
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else { throw TajpoError.noSelection }
            let ownedChangeCount = pasteboard.changeCount
            defer {
                if pasteboard.changeCount == ownedChangeCount {
                    backup.restore(to: pasteboard)
                }
            }
            postCommandKey(CGKeyCode(kVK_ANSI_V))
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Brings the target app forward with the macOS 14 activation API and
    /// confirms it became frontmost. Throws instead of posting a keystroke that
    /// could land in the wrong window.
    private func activateAndVerify(_ app: NSRunningApplication) async throws {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            return
        }
        app.activate()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TajpoError.activationFailed
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

    @discardableResult
    public func replace(with text: String, capture: TextCapture) async throws -> MutationReceipt {
        replacements.append((original: capture.text, replacement: text))
        replacedText = text
        return MutationReceipt(
            pid: capture.pid,
            element: capture.element,
            replacedContent: capture.text,
            writtenContent: text,
            utf16Range: capture.utf16Range
        )
    }
}

/// Serializes clipboard backup/stage/restore transactions so concurrent
/// capture()/replace() calls cannot interleave and corrupt each other's
/// backup/restore sequence. A queued transaction suspends until the
/// in-flight one (including its deferred restore) has finished.
private actor ClipboardTransactionCoordinator {
    func run<T: Sendable>(_ body: @MainActor () async throws -> T) async throws -> T {
        try await body()
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
