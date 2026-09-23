import AppKit
import ServiceManagement
import TajpoCore

@MainActor
enum LaunchAtLogin {
    /// Login items need a real app bundle in a permanent location.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && !AppLocation.isTemporary
    }

    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }

    /// Turns the login item on or off. Returns a message when the user has to
    /// finish the change in System Settings (e.g. the item was disabled there).
    static func setEnabled(_ enabled: Bool) throws -> String? {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return "Turn Tajpo on in System Settings ▸ General ▸ Login Items."
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
        return nil
    }
}

/// Detects running from a mounted disk image or a Gatekeeper-translocated
/// copy, where permissions and login items don't stick.
@MainActor
enum AppLocation {
    static var isTemporary: Bool {
        InstallPathPolicy.isTemporaryBundlePath(Bundle.main.bundlePath)
    }

    /// Hands installation back to Finder instead of copying or weakening
    /// Gatekeeper from inside the running app. Finder preserves the normal
    /// macOS install and quarantine workflow, including confirmation when an
    /// existing copy is replaced.
    static func offerFinderHandoffIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app", isTemporary else { return }
        let alert = NSAlert()
        alert.messageText = "Install Tajpo from Finder"
        alert.informativeText = "Tajpo is running from a temporary location. In Finder, drag Tajpo into Applications, then quit this copy and open the installed one. Tajpo will not replace or modify an existing app for you."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Open both locations so the user can perform the familiar drag-and-
        // drop handoff. Selecting the source last leaves it easy to identify.
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        _ = NSWorkspace.shared.open(applications)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
