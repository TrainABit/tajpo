import AppKit
import ApplicationServices
import Carbon
import TajpoCore

struct TextCapture {
    enum Method { case accessibility, clipboard, local }

    let text: String
    let method: Method
    /// The focused element, when the text was read through Accessibility or
    /// could be verified again after a clipboard capture.
    let element: AXUIElement?
    let selectedRange: CFRange?
    let sourceApp: NSRunningApplication?
    /// Selection bounds in Cocoa screen coordinates, if the app reports them.
    let bounds: CGRect?
    /// Why Replace isn't possible (read-only text, terminals, or an
    /// unverifiable clipboard target), or nil.
    let replaceBlocker: TajpoError?

    var canReplace: Bool { replaceBlocker == nil }
}

enum ReplaceOutcome {
    /// The app's text was read back and contains the replacement.
    case verified
    /// AX reported success but the target could not be verified; no paste was sent.
    case axUnverified
}

/// Reads selections in other apps. Synthetic ⌘C is used only to read a
/// clipboard-only target; replacement is Accessibility-only and fails closed
/// when the target cannot be verified.
@MainActor
final class TextSelectionService {
    private struct ClipboardCapture {
        let text: String
        let element: AXUIElement?
        let selectedRange: CFRange?
        let sourceApp: NSRunningApplication?
        let hasRichTypes: Bool
    }

    private let systemWideElement: AXUIElement
    private static let axTimeout: Float = 0.10
    private var isBusy = false
    private var didPromptThisLaunch = false

    init() {
        systemWideElement = AXUIElementCreateSystemWide()
        configure(systemWideElement)
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        // Literal value of kAXTrustedCheckOptionPrompt (a mutable C global Swift 6 rejects).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Capture

    func capture() async throws -> TextCapture {
        guard isTrusted else {
            if !didPromptThisLaunch {
                didPromptThisLaunch = true
                requestAccessibilityPermission()
            }
            throw TajpoError.accessibilityPermissionRequired
        }
        guard !isBusy else { throw TajpoError.busy }
        isBusy = true
        defer { isBusy = false }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            throw TajpoError.selectionInTajpo
        }
        let terminalBlocker: TajpoError? = AppPolicy.isTerminal(bundleID: frontmost?.bundleIdentifier) ? .replaceNotSupported : nil

        if let element = focusedElement(in: frontmost) {
            try rejectSecure(element)
            if let text = selectedText(of: element), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try SelectionValidator.validate(text)
                return TextCapture(
                    text: text,
                    method: .accessibility,
                    element: element,
                    selectedRange: selectedRange(of: element),
                    sourceApp: runningApp(for: element) ?? frontmost,
                    bounds: selectionBounds(of: element),
                    replaceBlocker: terminalBlocker ?? (isEditable(element) ? nil : .replaceNotSupported)
                )
            }
            Log.selection.debug("AX selection empty or unsupported; trying the clipboard")
        }

        let clipboard = try await copySelectionWithClipboard(expectedApp: frontmost)
        try SelectionValidator.validate(clipboard.text)
        // A clipboard capture is only replaceable if we can re-identify the
        // focused element and selected text. Otherwise Copy is the safe mode.
        let blocker: TajpoError? = terminalBlocker
            ?? (clipboard.element == nil || !isEditable(clipboard.element!) || clipboard.hasRichTypes
                ? .replaceNotSupported : nil)
        return TextCapture(
            text: clipboard.text,
            method: .clipboard,
            element: clipboard.element,
            selectedRange: clipboard.selectedRange,
            sourceApp: clipboard.sourceApp ?? frontmost,
            bounds: nil,
            replaceBlocker: blocker
        )
    }

    // MARK: Replace

    /// Replaces the captured selection with `text`. `hidePanel` is called
    /// before any synthetic paste so the keystroke reaches the source app.
    func replace(with text: String, capture: TextCapture) async throws -> ReplaceOutcome {
        if let blocker = capture.replaceBlocker { throw blocker }
        guard let app = capture.sourceApp, !app.isTerminated else { throw TajpoError.targetAppChanged }
        try Task.checkCancellation()
        try ensureFrontmost(app)

        if let element = capture.element {
            try rejectSecure(element)
            try ensureSelectionUnchanged(element, capture: capture)
            let status = setAttribute(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if status == .success {
                switch verify(element, inserted: text, capture: capture) {
                case .inserted: return .verified
                case .unknown: return .axUnverified
                case .unchanged: Log.selection.info("AX set reported success but changed nothing; leaving the result available to copy")
                }
            }
        }
        // Synthetic paste is intentionally never used as a fallback. A
        // clipboard-only or unresponsive target may be an unknown terminal,
        // where multiline text can become commands. Keep the result available
        // for Copy and ask the user to paste it deliberately.
        return .axUnverified
    }

    // MARK: Clipboard capture

    private func copySelectionWithClipboard(expectedApp: NSRunningApplication?) async throws -> ClipboardCapture {
        let pasteboard = NSPasteboard.general
        if pasteboard.deniesProgrammaticAccess { throw TajpoError.pasteboardAccessDenied }
        await Keyboard.waitForModifierRelease()
        try Task.checkCancellation()
        let current = NSWorkspace.shared.frontmostApplication
        if let expectedApp, current?.processIdentifier != expectedApp.processIdentifier {
            throw TajpoError.targetAppChanged
        }

        let originalCount = pasteboard.changeCount
        guard let snapshot = ClipboardSnapshot(pasteboard) else { throw TajpoError.pasteboardUnavailable }
        guard pasteboard.changeCount == originalCount else { throw TajpoError.pasteboardUnavailable }
        pasteboard.clearContents()
        let cleared = pasteboard.changeCount
        try Task.checkCancellation()
        try ensureFrontmost(current)
        Keyboard.postCommandShortcut("c", fallback: CGKeyCode(kVK_ANSI_C))

        let deadline = ContinuousClock.now + .seconds(1)
        while pasteboard.changeCount == cleared, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let observed = pasteboard.changeCount
        var text: String?
        var hasRichTypes = false
        if observed != cleared {
            let types = pasteboard.types ?? []
            hasRichTypes = types.contains { type in
                let raw = type.rawValue.lowercased()
                return raw.contains("rtf") || raw.contains("html") || raw.contains("webarchive") || raw.contains("web.archive")
            }
            // A file copy (e.g. in Finder) also carries the file name as text.
            if !types.contains(.fileURL) {
                text = pasteboard.string(forType: .string)
            }
        }

        // Best effort: re-write the observed text with transient/concealed
        // markers before restoring the user's original clipboard. The source
        // app created the item, so a clipboard manager may already have seen
        // it; the privacy copy must not claim otherwise.
        var restoreCount = observed
        if pasteboard.changeCount == observed, let text, pasteboard.writeTransient(text) {
            restoreCount = pasteboard.changeCount
        }
        // Restore only if no other process wrote after our observation or
        // marker write. A changed count is intentionally left untouched.
        if pasteboard.changeCount == restoreCount {
            snapshot.restore(to: pasteboard)
        }
        guard let text else { throw TajpoError.noSelection }

        let verifiedElement = focusedElement(in: current)
        let verifiedText = verifiedElement.flatMap { selectedText(of: $0) }
        let verifiedRange = verifiedElement.flatMap { selectedRange(of: $0) }
        let element = (verifiedText?.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines)) ? verifiedElement : nil
        return ClipboardCapture(
            text: text,
            element: element,
            selectedRange: element == nil ? nil : verifiedRange,
            sourceApp: current,
            hasRichTypes: hasRichTypes
        )
    }

    // MARK: Accessibility helpers

    private func focusedElement(in app: NSRunningApplication?) -> AXUIElement? {
        if let element = elementAttribute(systemWideElement, kAXFocusedUIElementAttribute),
           app == nil || runningApp(for: element)?.processIdentifier == app?.processIdentifier {
            return element
        }
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        configure(appElement)
        if let element = elementAttribute(appElement, kAXFocusedUIElementAttribute) {
            return element
        }
        // Electron apps only expose their UI after an assistive app asks.
        _ = setAttribute(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return elementAttribute(appElement, kAXFocusedUIElementAttribute)
    }

    private func rejectSecure(_ element: AXUIElement) throws {
        var current: AXUIElement?
        var depth = 0
        current = element
        while let node = current, depth < 6 {
            try Task.checkCancellation()
            let role = stringAttribute(node, kAXRoleAttribute) ?? ""
            let subrole = stringAttribute(node, kAXSubroleAttribute) ?? ""
            let description = stringAttribute(node, kAXRoleDescriptionAttribute) ?? ""
            if subrole == kAXSecureTextFieldSubrole
                || description.localizedCaseInsensitiveContains("password")
                || description.localizedCaseInsensitiveContains("secure text") {
                throw TajpoError.secureField
            }
            if [kAXWindowRole, kAXApplicationRole, "AXWebArea"].contains(role) { return }
            current = elementAttribute(node, kAXParentAttribute)
            depth += 1
        }
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute] {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success, settable.boolValue {
                return true
            }
        }
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { return true }
        // Web content marks editable regions with an editable ancestor.
        return elementAttribute(element, "AXEditableAncestor") != nil
    }

    private func selectedText(of element: AXUIElement) -> String? {
        stringAttribute(element, kAXSelectedTextAttribute)
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard copyAttribute(element, kAXSelectedTextRangeAttribute as CFString, into: &value),
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    private func selectionBounds(of element: AXUIElement) -> CGRect? {
        guard let rangeValue = selectedRange(of: element) else { return nil }
        var range = rangeValue
        let value = AXValueCreate(.cfRange, &range)!
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return PanelPlacement.cocoaRect(fromAX: rect, primaryScreenHeight: primaryHeight)
    }

    /// Requires the original selected text to still be selected. We never
    /// re-select a saved range: doing so could move the user's caret silently.
    private func ensureSelectionUnchanged(_ element: AXUIElement, capture: TextCapture) throws {
        guard Self.normalized(selectedText(of: element)) == Self.normalized(capture.text) else {
            throw TajpoError.selectionChanged
        }
    }

    private enum Verification { case inserted, unchanged, unknown }

    private func verify(_ element: AXUIElement, inserted insertedText: String, capture: TextCapture) -> Verification {
        let text = insertedText
        let expected = Self.normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = capture.selectedRange {
            let replacementRange = CFRange(location: range.location, length: text.utf16.count)
            if let value = textInRange(replacementRange, of: element), Self.normalized(value) == expected {
                return .inserted
            }
        }
        if Self.normalized(selectedText(of: element)) == Self.normalized(capture.text) { return .unchanged }
        return .unknown
    }

    private func textInRange(_ range: CFRange, of element: AXUIElement) -> String? {
        var value = range
        guard let rangeValue = AXValueCreate(.cfRange, &value) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForRange" as CFString, rangeValue, &result) == .success else { return nil }
        return result as? String
    }

    private func ensureFrontmost(_ app: NSRunningApplication?) throws {
        guard let app, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw TajpoError.targetAppChanged
        }
    }

    private func configure(_ element: AXUIElement) {
        // AX calls run on the main actor in this UI-owned service. Keep each
        // individual call short; a timeout is converted into the clipboard /
        // Copy-only path rather than freezing the menu-bar app.
        AXUIElementSetMessagingTimeout(element, Self.axTimeout)
    }

    private func setAttribute(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
        configure(element)
        return AXUIElementSetAttributeValue(element, attribute, value)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString, into value: inout CFTypeRef?) -> Bool {
        configure(element)
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard copyAttribute(element, attribute as CFString, into: &value) else { return nil }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard copyAttribute(element, attribute as CFString, into: &value),
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func runningApp(for element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    private static func normalized(_ text: String?) -> String {
        (text ?? "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
