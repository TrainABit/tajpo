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
        let size = NSSize(width: 620, height: 440)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
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
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Tone", selection: $model.tone) {
                        ForEach(RewriteTone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if model.presets.selected != nil {
                        Text("The selected tone wins if it conflicts with the \(model.presets.selected?.name ?? "preset") preset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if model.isWorking {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
            }
            HStack(alignment: .top, spacing: 12) {
                textColumn(title: "Original", text: model.originalText, placeholder: "No selection captured.")
                textColumn(
                    title: "Rewrite",
                    text: displayedPreview,
                    placeholder: model.status,
                    emphasizeError: model.preview.isEmpty && model.isError
                )
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
                Button("Undo last") {
                    Task { await model.undoLastReplacement() }
                }
                Spacer()
                if !model.usageLabel.isEmpty {
                    Text(model.usageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("⌘↩ replace  ·  esc close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
        .onExitCommand(perform: close)
    }

    private var displayedPreview: String {
        if model.preview.isEmpty { return "" }
        return model.isWorking ? model.preview + "▍" : model.preview
    }

    private var progressValue: Double {
        let total = max(model.originalText.count, 1)
        return min(Double(model.preview.count) / Double(total), 1)
    }

    private func textColumn(title: String, text: String, placeholder: String, emphasizeError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(text.isEmpty ? (emphasizeError ? .red : .secondary) : .primary)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
