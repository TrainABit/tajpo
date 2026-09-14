import AppKit
import SwiftUI

@MainActor
final class InlinePanelController {
    private var panel: NSPanel?

    func show(model: AppModel, near selectionFrame: CGRect?) {
        let content = InlineRewriteView(model: model, close: { [weak self] in self?.close() })
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        let fallback = NSEvent.mouseLocation
        let anchor = selectionFrame.map { CGPoint(x: $0.midX, y: NSScreen.screens.map(\.frame.maxY).max()! - $0.maxY) } ?? fallback
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: min(max(anchor.x - 220, visible.minX + 12), visible.maxX - 452), y: min(max(anchor.y - 316, visible.minY + 12), visible.maxY - 312))
        panel.setFrameOrigin(origin); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); self.panel = panel
    }

    func close() { panel?.orderOut(nil); panel = nil }
}

private struct InlineRewriteView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { ForEach(RewriteAction.allCases) { action in Button(action.title) { model.action = action; Task { await model.runCurrentCapture() } }.buttonStyle(.bordered).tint(model.action == action ? .accentColor : nil) } }
            if model.isWorking { ProgressView().progressViewStyle(.linear) }
            ScrollView { Text(model.preview.isEmpty ? model.status : model.preview).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            HStack {
                Button("Replace") { Task { await model.applyPreview() } }.disabled(model.preview.isEmpty || model.isWorking)
                Button("Copy") { model.copyPreview() }.disabled(model.preview.isEmpty)
                Button("Retry") { Task { await model.runCurrentCapture() } }.disabled(model.isWorking)
                Spacer(); Text("⌘↩ replace  ·  esc close").font(.caption).foregroundStyle(.secondary); Button("Close", action: close)
            }
        }.padding(16).frame(width: 440, height: 300)
    }
}
