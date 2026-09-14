import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

public struct TajpoScenes: Scene {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label("Tajpo", systemImage: model.isWorking ? "sparkles" : "character.cursor.ibeam")
                .onAppear { model.start() }
        }
        Settings {
            SettingsView(model: model)
        }
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
            Button(model.isWorking ? "Working..." : "Open rewrite panel") {
                Task { await model.rewriteSelection() }
            }
            .disabled(model.isWorking)
            Button("Repeat last action") {
                Task { await model.repeatLastAction() }
            }
            .disabled(model.isWorking)
            Button("Undo last replace") {
                Task { await model.undoLastReplacement() }
            }
            HStack {
                if model.isWorking { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(model.isError ? Color.red : Color.secondary)
            }
            Text(model.isAccessibilityTrusted ? "Accessibility: granted" : "Accessibility: missing")
                .font(.caption)
                .foregroundStyle(model.isAccessibilityTrusted ? Color.secondary : Color.red)
            if !model.usageLabel.isEmpty {
                Text(model.usageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            if !model.updateMessage.isEmpty {
                Text(model.updateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.updateURL != nil {
                Button("Open latest release") { model.openUpdatePage() }
            }
            Button("Check for updates") {
                Task { await model.checkForUpdates(quiet: false) }
            }
            SettingsLink { Text("Settings...") }
            Button("Quit Tajpo") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { model.refreshSystemState() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchesAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}
