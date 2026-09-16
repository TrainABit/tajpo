import SwiftUI
import TajpoCore

@main
struct TajpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        TajpoScenes(model: model)
    }
}
