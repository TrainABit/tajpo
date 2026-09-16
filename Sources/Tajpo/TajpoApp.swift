import SwiftUI
import TajpoCore

@main
struct TajpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(startAutomatically: true)

    var body: some Scene {
        TajpoScenes(model: model)
    }
}
