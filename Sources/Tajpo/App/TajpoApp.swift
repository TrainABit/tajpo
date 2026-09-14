import SwiftUI

@main
struct TajpoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Tajpo", systemImage: model.isWorking ? "sparkles" : "character.cursor.ibeam") {
            MenuBarView(model: model)
        }
        Settings { SettingsView(model: model) }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: $model.action) {
                ForEach(RewriteAction.allCases) { Text($0.title).tag($0) }
            }
            if model.action == .changeTone {
                Picker("Tone", selection: $model.tone) {
                    ForEach(RewriteTone.allCases) { Text($0.title).tag($0) }
                }
            }
            Button(model.isWorking ? "Working..." : "Rewrite selected text") {
                Task { await model.rewriteSelection() }
            }.disabled(model.isWorking)
            Button("Repeat last action") { Task { await model.repeatLastAction() } }
                .disabled(model.isWorking)
            HStack {
                if model.isWorking { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).foregroundStyle(model.isError ? .red : .secondary)
            }
            Divider()
            SettingsLink { Text("Settings...") }
            Button("Quit Tajpo") { NSApplication.shared.terminate(nil) }
        }.padding(12).frame(width: 300)
        .onAppear { model.start() }
    }
}
