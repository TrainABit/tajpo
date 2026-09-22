import AppKit
import SwiftUI
import TajpoCore

@main
struct TajpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, presets: model.presets, settings: model.settings, updates: model.updates)
        } label: {
            Label(menuBarTitle, systemImage: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        if model.isWorking || model.celebrating { return "sparkles" }
        return model.needsSetup ? "exclamationmark.circle" : "character.cursor.ibeam"
    }

    /// Menu bar extras show only the icon; the title is what VoiceOver reads.
    private var menuBarTitle: String {
        if model.isWorking { return "Tajpo, working" }
        return model.needsSetup ? "Tajpo, needs setup" : "Tajpo"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App bundles set LSUIElement; `swift run` / Xcode builds need this instead.
        if Bundle.main.object(forInfoDictionaryKey: "LSUIElement") == nil {
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.async {
            AppLocation.offerMoveIfNeeded()
            EditMenu.installIfMissing()
            EditMenu.installWindowMenuIfMissing()
            AppModel.shared.start()
        }
    }
}

/// Menu bar menu. Kept to controls that render natively in an NSMenu.
struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        if let release = updates.available {
            Button { updates.openAvailable() } label: {
                Label("Update Available: Tajpo \(release.version?.description ?? release.tag_name)…", systemImage: "arrow.down.circle")
            }
        }
        if model.needsAPIKey {
            Button { model.showOnboarding(at: OnboardingStep.connect.rawValue) } label: {
                Label("Finish Setup: Add Your OpenAI Key…", systemImage: "key")
            }
        }
        if !model.accessibilityTrusted {
            Button { model.showOnboarding(at: OnboardingStep.everywhere.rawValue) } label: {
                Label("Finish Setup: Allow Tajpo in Other Apps…", systemImage: "hand.raised")
            }
        }
        ForEach(HotkeyAction.allCases.filter { model.hotkeyErrors[$0] != nil }) { action in
            Button("Fix the Shortcut for “\(action.title)”…") { model.showSettings(tab: .general) }
        }
        if model.secureInputActive {
            Text("Shortcuts paused: another app has secure input on")
        }
        if let shortcut = settings.rewriteShortcut {
            Text("Select text, then press \(shortcut.displayString)")
        }
        if model.status != "Ready" {
            Text(String(model.status.prefix(60)))
        }

        Divider()

        Button { model.openPanel() } label: { Label("Rewrite Selection", systemImage: "wand.and.stars") }
            .keyboardShortcut(settings.rewriteShortcut?.menuShortcut)
        Button { model.repeatLastAction() } label: {
            Label(model.lastActionTitle.map { "Repeat \($0)" } ?? "Repeat Last Action", systemImage: "arrow.clockwise")
        }
            .keyboardShortcut(settings.repeatShortcut?.menuShortcut)
            .disabled(model.lastAction == nil)

        Picker("Style Preset", selection: Binding(get: { presets.selectedID }, set: { presets.select($0) })) {
            Text("None").tag(UUID?.none)
            ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
        }

        if settings.usesThisWeek > 0 {
            Text("\(settings.usesThisWeek) \(settings.usesThisWeek == 1 ? "edit" : "edits") this week")
        }

        Divider()

        Button { model.showSettings() } label: { Label("Settings…", systemImage: "gearshape") }
            .keyboardShortcut(",")
        Button { model.showOnboarding() } label: { Label("Setup Guide…", systemImage: "list.bullet.rectangle") }
        Button { Task { await updates.check(userInitiated: true) } } label: {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
            .disabled(updates.isChecking)
        Button { model.reportProblem() } label: { Label("Report a Problem…", systemImage: "exclamationmark.bubble") }
        Button { model.showAbout() } label: { Label("About Tajpo", systemImage: "info.circle") }

        Divider()

        Button("Quit Tajpo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension GlobalShortcut {
    /// The same shortcut as a menu key equivalent (letters and digits only),
    /// so the menu shows it right-aligned like any other shortcut.
    var menuShortcut: SwiftUI.KeyboardShortcut? {
        let name = KeyCode.name(for: keyCode)
        guard name.count == 1, let character = name.lowercased().first, character.isLetter || character.isNumber else { return nil }
        var modifiers: EventModifiers = []
        if hasCommand { modifiers.insert(.command) }
        if hasControl { modifiers.insert(.control) }
        if hasOption { modifiers.insert(.option) }
        if hasShift { modifiers.insert(.shift) }
        return SwiftUI.KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
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

    /// ⌘W / ⌘M for Settings and the setup guide.
    @MainActor
    static func installWindowMenuIfMissing() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        let hasClose = mainMenu.items.contains { item in
            item.submenu?.items.contains { $0.action == #selector(NSWindow.performClose(_:)) } ?? false
        }
        guard !hasClose else { return }
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.submenu = window
        mainMenu.addItem(item)
        NSApp.mainMenu = mainMenu
    }
}
