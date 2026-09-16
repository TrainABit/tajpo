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
        let size = NSSize(width: 680, height: 480)
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
        panel.isOpaque = false
        panel.backgroundColor = .clear
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tajpo")
                    .font(.headline)
                StatusPill(text: model.status, isError: model.isError, isWorking: model.isWorking)
                Spacer()
                Text(model.settings.hotkeyLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RewriteAction.allCases) { action in
                        ActionChip(action: action, selected: model.action == action) {
                            model.action = action
                            Task { await model.runCurrentCapture() }
                        }
                        .keyboardShortcut(KeyEquivalent(action.shortcutDigit.first ?? "0"), modifiers: [])
                    }
                }
            }

            Picker("Length", selection: $model.length) {
                ForEach(RewriteLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.length) { _, value in
                model.settings.rewriteLength = value
                Task { await model.runCurrentCapture() }
            }

            if model.action == .changeTone {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Tone", selection: $model.tone) {
                        ForEach(RewriteTone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.tone) { _, _ in
                        Task { await model.runCurrentCapture() }
                    }
                    if let name = model.presets.selected?.name {
                        Text("Selected tone wins if it conflicts with the \(name) preset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.isWorking {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(TajpoTheme.copper)
            }

            HStack(alignment: .top, spacing: 12) {
                textColumn(title: "Original", text: model.originalText, placeholder: emptyOriginal, emphasizeError: false)
                textColumn(
                    title: "Rewrite",
                    text: displayedPreview,
                    placeholder: emptyPreview,
                    emphasizeError: model.preview.isEmpty && model.isError
                )
            }

            HStack(spacing: 8) {
                Button("Replace") {
                    Task { await model.applyPreview() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.preview.isEmpty || model.isWorking)
                .buttonStyle(.borderedProminent)
                .tint(TajpoTheme.copper)

                Button("Copy") { model.copyPreview() }
                    .disabled(model.preview.isEmpty)
                Button("Retry") {
                    Task { await model.runCurrentCapture() }
                }
                .disabled(model.isWorking)
                Button("Undo") {
                    Task { await model.undoLastReplacement() }
                }
                .disabled(!model.canUndo)
                Button("Redo") {
                    Task { await model.redoLastReplacement() }
                }
                .disabled(!model.canRedo)

                Spacer()

                if !model.usageLabel.isEmpty {
                    Text(model.usageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("⌘↩ replace  ·  esc close  ·  1–9 actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TajpoTheme.copper.opacity(0.18), lineWidth: 1)
        )
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

    private var emptyOriginal: String {
        model.originalText.isEmpty ? "Select text in another app, then press \(model.settings.hotkeyLabel)." : ""
    }

    private var emptyPreview: String {
        if model.isError { return model.status }
        if model.isWorking { return "Writing…" }
        return "Choose an action or press 1–9."
    }

    private func textColumn(title: String, text: String, placeholder: String, emphasizeError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? (emphasizeError ? TajpoTheme.terracotta : Color.secondary) : Color.primary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
