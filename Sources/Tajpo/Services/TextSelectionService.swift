import AppKit
import ApplicationServices
import Carbon
import TajpoCore

struct TextCapture {
    enum Method { case accessibility, clipboard, local }

    let text: String
    let method: Method
    /// The focused element, when the text was read through Accessibility.
    let element: AXUIElement?
    let selectedRange: CFRange?
    let sourceApp: NSRunningApplication?
    /// Selection bounds in Cocoa screen coordinates, if the app reports them.
    let bounds: CGRect?
    /// Why Replace isn't possible (read-only text, terminals), or nil.
    let replaceBlocker: TajpoError?

    var canReplace: Bool { replaceBlocker == nil }
}

enum ReplaceOutcome {
    /// The app's text was read back and contains the replacement.
    case verified
    /// The replacement was sent but couldn't be confirmed.
    case unverified
}

/// Reads and replaces the selection in other apps: Accessibility first,
/// synthetic ⌘C/⌘V as the fallback.
@MainActor
final class TextSelectionService {
    private var isBusy = false
    private var didPromptThisLaunch = false

    init() {
        // The default 6 s timeout per call would freeze Tajpo when the target app hangs.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.75)
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

        let text = try await copySelectionWithClipboard()
        try SelectionValidator.validate(text)
        return TextCapture(
            text: text,
            method: .clipboard,
            element: nil,
            selectedRange: nil,
            sourceApp: frontmost,
            bounds: nil,
            replaceBlocker: terminalBlocker
        )
    }

    // MARK: Replace

    /// Replaces the captured selection with `text`. `hidePanel` is called
    /// before any synthetic paste so the keystroke reaches the source app.
    func replace(with text: String, capture: TextCapture, hidePanel: () -> Void) async throws -> ReplaceOutcome {
        if let blocker = capture.replaceBlocker { throw blocker }
        if let app = capture.sourceApp, app.isTerminated { throw TajpoError.targetAppChanged }

        if let element = capture.element {
            try rejectSecure(element)
            try ensureSelectionUnchanged(element, capture: capture)
            let before = fieldValue(element)
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                switch verify(element, inserted: text, original: capture.text, before: before) {
                case .inserted: return .verified
                case .unknown: return .unverified
                case .unchanged: Log.selection.info("AX set reported success but changed nothing; pasting instead")
                }
            }
        }
        return try await paste(text, capture: capture, hidePanel: hidePanel)
    }

    private func paste(_ text: String, capture: TextCapture, hidePanel: () -> Void) async throws -> ReplaceOutcome {
        hidePanel()
        if let app = capture.sourceApp {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                app.activate(from: NSRunningApplication.current, options: [])
            }
            guard await waitUntilFrontmost(app) else { throw TajpoError.targetAppChanged }
        }
        // Let key focus return from the panel to the source window.
        try? await Task.sleep(for: .milliseconds(120))
        if let element = capture.element {
            try ensureSelectionUnchanged(element, capture: capture)
        }

        let pasteboard = NSPasteboard.general
        if pasteboard.deniesProgrammaticAccess { throw TajpoError.pasteboardAccessDenied }
        let snapshot = ClipboardSnapshot(pasteboard)
        guard pasteboard.writeTransient(text) else { throw TajpoError.pasteboardUnavailable }
        let written = pasteboard.changeCount

        let valueBeforePaste = capture.element.flatMap(fieldValue)
        await Keyboard.waitForModifierRelease()
        Keyboard.postCommandShortcut("v", fallback: CGKeyCode(kVK_ANSI_V))

        var outcome = ReplaceOutcome.unverified
        if let element = capture.element {
            // Never restore sooner than this: the app may read the pasteboard late.
            try? await Task.sleep(for: .milliseconds(300))
            let deadline = ContinuousClock.now + .milliseconds(1500)
            while ContinuousClock.now < deadline {
                if case .inserted = verify(element, inserted: text, original: capture.text, before: valueBeforePaste) {
                    outcome = .verified
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        } else {
            // No way to observe the paste; give slow apps time before restoring.
            try? await Task.sleep(for: .milliseconds(900))
        }
        // Only restore if nobody (the user, another app) wrote to it meanwhile.
        if pasteboard.changeCount == written {
            snapshot.restore(to: pasteboard)
        }
        return outcome
    }

    // MARK: Clipboard capture

    private func copySelectionWithClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general
        if pasteboard.deniesProgrammaticAccess { throw TajpoError.pasteboardAccessDenied }
        await Keyboard.waitForModifierRelease()
        let snapshot = ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let cleared = pasteboard.changeCount
        Keyboard.postCommandShortcut("c", fallback: CGKeyCode(kVK_ANSI_C))

        let deadline = ContinuousClock.now + .seconds(1)
        while pasteboard.changeCount == cleared, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        var text: String?
        let observed = pasteboard.changeCount
        if observed != cleared {
            let types = pasteboard.types ?? []
            // A file copy (e.g. in Finder) also carries the file name as text.
            if !types.contains(.fileURL) {
                text = pasteboard.string(forType: .string)
            }
        }
        // Restore unless someone else wrote to the pasteboard after the copy we saw.
        if pasteboard.changeCount == observed {
            snapshot.restore(to: pasteboard)
        }
        guard let text else { throw TajpoError.noSelection }
        return text
    }

    // MARK: Accessibility helpers

    private func focusedElement(in app: NSRunningApplication?) -> AXUIElement? {
        if let element = elementAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) {
            return element
        }
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let element = elementAttribute(appElement, kAXFocusedUIElementAttribute) {
            return element
        }
        // Electron apps only expose their UI after an assistive app asks.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return elementAttribute(appElement, kAXFocusedUIElementAttribute)
    }

    private func rejectSecure(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 10 {
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
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    private func selectionBounds(of element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return PanelPlacement.cocoaRect(fromAX: rect, primaryScreenHeight: primaryHeight)
    }

    /// Throws `selectionChanged` unless the element still has the captured
    /// text selected, re-selecting the captured range if the caret moved.
    private func ensureSelectionUnchanged(_ element: AXUIElement, capture: TextCapture) throws {
        if Self.normalized(selectedText(of: element)) == Self.normalized(capture.text) { return }
        if var range = capture.selectedRange, let value = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            if Self.normalized(selectedText(of: element)) == Self.normalized(capture.text) { return }
        }
        throw TajpoError.selectionChanged
    }

    private enum Verification { case inserted, unchanged, unknown }

    /// The field's full text, if readable and not huge.
    private func fieldValue(_ element: AXUIElement) -> String? {
        guard let value = stringAttribute(element, kAXValueAttribute), value.utf16.count < 500_000 else { return nil }
        return Self.normalized(value)
    }

    /// `.inserted` only if the field's text changed and now contains the
    /// replacement; a value that already contained it (e.g. a result equal to
    /// the original) doesn't count.
    private func verify(_ element: AXUIElement, inserted text: String, original: String, before: String?) -> Verification {
        let needle = Self.normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = fieldValue(element), value != before, value.contains(needle) {
            return .inserted
        }
        // Nothing happened if the original is still what's selected.
        if Self.normalized(selectedText(of: element)) == Self.normalized(original) { return .unchanged }
        return .unknown
    }

    private func waitUntilFrontmost(_ app: NSRunningApplication) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
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
