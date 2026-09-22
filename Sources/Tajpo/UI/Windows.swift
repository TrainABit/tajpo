import AppKit
import SwiftUI

/// Owns one regular window hosting SwiftUI content. Windows created in code
/// must not be released on close (`isReleasedWhenClosed`), or ARC over-releases them.
@MainActor
class HostingWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?

    func present(title: String, size: NSSize, resizable: Bool = false, content: () -> AnyView) {
        if window == nil {
            var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if resizable { style.insert(.resizable) }
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            window.delegate = self
            window.contentView = NSHostingView(rootView: content())
            window.center()
            self.window = window
        }
        // Tajpo is a menu bar app; bring it forward so the window isn't hidden behind others.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        didClose()
    }

    func didClose() {}
}

@MainActor
final class OnboardingWindowController: HostingWindowController {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        present(title: "Welcome to Tajpo", size: NSSize(width: 620, height: 500)) {
            AnyView(OnboardingView(model: model))
        }
    }

    override func didClose() {
        model.shortcutProbe = nil
        model.hotkeys.resume()
    }
}
