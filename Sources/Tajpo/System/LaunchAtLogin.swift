import AppKit
import ServiceManagement

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
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Offers to copy Tajpo to /Applications and relaunch from there.
    static func offerMoveIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app", isTemporary else { return }
        let alert = NSAlert()
        alert.messageText = "Move Tajpo to your Applications folder?"
        alert.informativeText = "Tajpo is running from a temporary location. macOS forgets its permissions and can't start it at login from here."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let destination = URL(fileURLWithPath: "/Applications/Tajpo.app")
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: Bundle.main.bundleURL, to: destination)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            let failure = NSAlert(error: error)
            failure.informativeText = "Drag Tajpo from the disk image into your Applications folder, then open it from there."
            failure.runModal()
        }
    }
}
