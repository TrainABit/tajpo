import AppKit
import SwiftUI
import TajpoCore

@main
struct TajpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, presets: model.presets, settings: model.settings)
        } label: {
            Image(systemName: model.isWorking ? "sparkles" : (model.needsSetup ? "exclamationmark.triangle" : "character.cursor.ibeam"))
                .accessibilityLabel("Tajpo")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App bundles set LSUIElement; `swift run` / Xcode builds need this instead.
        if Bundle.main.object(forInfoDictionaryKey: "LSUIElement") == nil {
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.async {
            EditMenu.installIfMissing()
            AppModel.shared.start()
        }
    }
}

/// Menu bar menu. Kept to controls that render natively in an NSMenu.
struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Text(model.status)

        if !model.accessibilityTrusted {
            Button("⚠︎ Allow Accessibility Access…") {
                model.requestAccessibility()
                model.openAccessibilitySettings()
            }
        }
        if model.needsAPIKey {
            Button("⚠︎ Add Your OpenAI API Key…") { model.showSettings(tab: .ai) }
        }
        ForEach(HotkeyAction.allCases.filter { model.hotkeyErrors[$0] != nil }) { action in
            Button("⚠︎ Shortcut for “\(action.title)” isn't working…") { model.showSettings(tab: .general) }
        }
        if model.secureInputActive {
            Text("Shortcuts paused: another app has secure input on")
        }

        Divider()

        Button(title("Rewrite Selection", settings.rewriteShortcut)) { model.openPanel() }
        Button(title(model.lastActionTitle.map { "Repeat \($0)" } ?? "Repeat Last Action", settings.repeatShortcut)) {
            model.repeatLastAction()
        }
        .disabled(model.lastAction == nil)

        Picker("Style Preset", selection: Binding(get: { presets.selectedID }, set: { presets.select($0) })) {
            Text("None").tag(UUID?.none)
            ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLoginEnabled },
            set: { _ = model.setLaunchAtLogin($0) }
        ))
        .disabled(!LaunchAtLogin.isAvailable)
        Button("Setup Guide…") { model.showOnboarding() }
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("About Tajpo") { model.showAbout() }

        Divider()

        Button("Quit Tajpo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(_ text: String, _ shortcut: GlobalShortcut?) -> String {
        shortcut.map { "\(text)   \($0.displayString)" } ?? text
    }
}

/// Accessory apps still route ⌘C/⌘V/⌘A through the main menu. Make sure an
/// Edit menu exists so text fields (e.g. pasting the API key) work.
enum EditMenu {
    @MainActor
    static func installIfMissing() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        let hasPaste = mainMenu.items.contains { item in
            item.submenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } ?? false
        }
        guard !hasPaste else { return }
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        mainMenu.addItem(item)
        NSApp.mainMenu = mainMenu
    }
}
