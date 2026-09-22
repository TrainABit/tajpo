import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    /// Login items need a real app bundle (see scripts/build-app.sh).
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
