import AppKit
import SwiftUI

@MainActor
final class InlinePanelController {
    private var panel: NSPanel?

    func show(model: AppModel, near selectionFrame: CGRect?) {
        close()
        let content = InlineRewriteView(model: model, close: { [weak self] in
            model.cancelWork()
            self?.close()
        })
        let size = NSSize(width: 440, height: 320)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)

        let fallback = NSEvent.mouseLocation
        let anchor = selectionFrame.map { CGPoint(x: $0.midX, y: $0.minY) } ?? fallback
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) }) ?? NSScreen.main
        panel.setFrameOrigin(SelectionGeometry.panelOrigin(anchor: anchor, size: size, on: screen))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct InlineRewriteView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(RewriteAction.allCases) { action in
                    Button(action.title) {
                        model.action = action
                        Task { await model.runCurrentCapture() }
                    }
                    .buttonStyle(.bordered)
                    .tint(model.action == action ? .accentColor : nil)
                }
            }
            if model.action == .changeTone {
                Picker("Tone", selection: $model.tone) {
                    ForEach(RewriteTone.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if model.isWorking {
                ProgressView().progressViewStyle(.linear)
            }
            ScrollView {
                Text(model.preview.isEmpty ? model.status : model.preview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.preview.isEmpty && model.isError ? .red : .primary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Replace") {
                    Task { await model.applyPreview() }
                }
                .disabled(model.preview.isEmpty || model.isWorking)
                .keyboardShortcut(.return, modifiers: .command)
                Button("Copy") { model.copyPreview() }
                    .disabled(model.preview.isEmpty)
                Button("Retry") {
                    Task { await model.runCurrentCapture() }
                }
                .disabled(model.isWorking)
                Spacer()
                Text("⌘↩ replace  ·  esc close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 320)
        .onExitCommand(perform: close)
    }
}
