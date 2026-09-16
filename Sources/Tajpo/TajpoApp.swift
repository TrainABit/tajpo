import SwiftUI
import TajpoCore

@main
struct TajpoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        _model = StateObject(wrappedValue: AppModel(
            settings: settings,
            presets: PresetStore(),
            history: HistoryStore(enabled: settings.historyEnabled),
            selection: TextSelectionService(),
            keyStore: KeychainAPIKeyStore(),
            startAutomatically: true,
            makeClient: { endpoint, key in
                OpenAICompatibleClient(endpoint: endpoint, apiKey: key)
            }
        ))
    }

    var body: some Scene {
        TajpoScenes(model: model)
    }
}
