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
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tajpo")
                        .font(.title3.weight(.semibold))
                    Text(model.settings.provider.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: model.status, isError: model.isError, isWorking: model.isWorking)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Action")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach(RewriteAction.allCases) { action in
                        ActionChip(action: action, selected: model.action == action) {
                            model.action = action
                        }
                    }
                }
                Picker("Length", selection: $model.length) {
                    ForEach(RewriteLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.length) { _, value in
                    model.settings.rewriteLength = value
                }
                if model.action == .changeTone {
                    Picker("Tone", selection: $model.tone) {
                        ForEach(RewriteTone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            VStack(spacing: 8) {
                Button {
                    Task { await model.rewriteSelection() }
                } label: {
                    Label(model.isWorking ? "Working…" : "Open rewrite panel", systemImage: "rectangle.and.pencil.and.ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TajpoTheme.copper)
                .disabled(model.isWorking)
                .keyboardShortcut("t", modifiers: [.command, .option])

                HStack {
                    Button("Repeat") { Task { await model.repeatLastAction() } }
                        .disabled(model.isWorking)
                    Button("Undo") { Task { await model.undoLastReplacement() } }
                        .disabled(!model.canUndo)
                    Button("Redo") { Task { await model.redoLastReplacement() } }
                        .disabled(!model.canRedo)
                }
                .controlSize(.small)
            }

            if !model.usageLabel.isEmpty {
                Text(model.usageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Label(
                    model.isAccessibilityTrusted ? "Accessibility on" : "Accessibility needed",
                    systemImage: model.isAccessibilityTrusted ? "checkmark.shield" : "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(model.isAccessibilityTrusted ? TajpoTheme.sage : TajpoTheme.terracotta)
                Spacer()
            }

            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .font(.callout)

            if !model.updateMessage.isEmpty {
                Text(model.updateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if model.updateURL != nil {
                    Button("Open latest release") { model.openUpdatePage() }
                }
                Button("Check updates") {
                    Task { await model.checkForUpdates(quiet: false) }
                }
                Spacer()
                Button {
                    model.openOnboarding()
                } label: {
                    Label("Setup Guide", systemImage: "sparkles")
                }
                SettingsLink {
                    Text("Settings")
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .onAppear { model.refreshSystemState() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchesAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}
