import AppKit
import SwiftUI
import TajpoCore

private final class RewritePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Floating panel shown next to the selection. It never activates Tajpo, so
/// the source app stays frontmost; it becomes key only for its own shortcuts.
@MainActor
final class InlinePanelController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onOutsideClick: (() -> Void)?

    private var panel: NSPanel?
    private var clickMonitor: Any?

    private static let sizeKey = "panelSize"
    static let minimumSize = NSSize(width: 460, height: 340)

    func show(model: AppModel, near selection: CGRect?) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let screens = NSScreen.screens.map { ScreenFrame(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let origin = PanelPlacement.origin(selection: selection, mouse: NSEvent.mouseLocation, size: panel.frame.size, screens: screens)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitor()
    }

    /// Hides the panel so a synthetic paste reaches the source app.
    func hide() {
        panel?.orderOut(nil)
    }

    func reshow() {
        guard let panel, !panel.isVisible else { return }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        removeClickMonitor()
        panel?.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        removeClickMonitor()
        onClose?()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let size = panel?.contentView?.frame.size else { return }
        UserDefaults.standard.set(NSStringFromSize(size), forKey: Self.sizeKey)
    }

    // MARK: Private

    private func makePanel(model: AppModel) -> NSPanel {
        let saved = UserDefaults.standard.string(forKey: Self.sizeKey).map(NSSizeFromString)
        var size = saved ?? NSSize(width: 520, height: 420)
        size.width = max(size.width, Self.minimumSize.width)
        size.height = max(size.height, Self.minimumSize.height)
        let panel = RewritePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tajpo"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = Self.minimumSize
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: InlineRewriteView(model: model, session: model.session))
        return panel
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        // Global monitors only see clicks in other apps, i.e. outside the panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onOutsideClick?() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

struct InlineRewriteView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: RewriteSession
    @ObservedObject private var presets: PresetStore
    @ObservedObject private var settings: AppSettings
    @FocusState private var instructionFocused: Bool

    private static let suggestions = [
        "Translate to English",
        "Make it a bullet list",
        "Make it more formal",
        "Explain it more simply",
        "Fix the formatting"
    ]

    init(model: AppModel, session: RewriteSession) {
        self.model = model
        self.session = session
        presets = model.presets
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let capture = session.capture {
                OriginalTextView(text: capture.text)
                actionRow
                instructionRow
                presetRow
            }
            if session.isRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(session.preview.isEmpty ? "Writing…" : "Writing… \(session.preview.count.formatted()) characters")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { model.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                .font(.callout)
            }
            output
            messages
            footer
        }
        .padding(14)
        .frame(minWidth: InlinePanelController.minimumSize.width, minHeight: InlinePanelController.minimumSize.height)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            ForEach(RewriteAction.buttons.filter { $0 != .changeTone }) { action in
                Button(action.title) { model.run(action) }
                    .keyboardShortcut(KeyEquivalent(Character(String(action.shortcutNumber))), modifiers: .command)
                    .buttonStyle(.bordered)
                    .tint(session.action == action ? .accentColor : nil)
                    .help("\(action.title) (⌘\(action.shortcutNumber))")
            }
            Menu {
                ForEach(RewriteTone.allCases) { tone in
                    Button(tone.title) { model.runTone(tone) }
                }
            } label: {
                Text("Tone: \(session.tone.title)")
            } primaryAction: {
                model.run(.changeTone)
            }
            .menuStyle(.button)
            .fixedSize()
            .tint(session.action == .changeTone ? .accentColor : nil)
            .keyboardShortcut("5", modifiers: .command)
            .help("Change Tone (⌘5). Click the arrow to pick a tone.")
        }
        .disabled(!session.canRun)
        .controlSize(.regular)
    }

    private var instructionRow: some View {
        HStack(spacing: 6) {
            TextField("Or tell Tajpo what to do, e.g. “make it a bullet list”", text: $session.instruction)
                .textFieldStyle(.roundedBorder)
                .focused($instructionFocused)
                .onSubmit { model.run(.custom) }
                .accessibilityLabel("Custom instruction")
            Menu {
                let recent = settings.recentInstructions
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent, id: \.self) { item in
                            Button(item) { session.instruction = item; model.run(.custom) }
                        }
                    }
                }
                Section("Ideas") {
                    ForEach(Self.suggestions, id: \.self) { item in
                        Button(item) { session.instruction = item; model.run(.custom) }
                    }
                }
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Recent and suggested instructions")
            .accessibilityLabel("Instruction suggestions")
            Button("Go") { model.run(.custom) }
                .keyboardShortcut("6", modifiers: .command)
                .help("Run the instruction (⌘6)")
        }
        .disabled(!session.canRun)
        .onChange(of: session.focusInstruction) { _, focus in
            if focus {
                instructionFocused = true
                session.focusInstruction = false
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            Picker("Style preset", selection: Binding(get: { presets.selectedID }, set: { presets.select($0) })) {
                Text("None").tag(UUID?.none)
                ForEach(presets.presets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Text("Not used by Correct")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if session.diff != nil {
                Toggle("Show changes", isOn: $session.showChanges)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var output: some View {
        ScrollView {
            Group {
                if session.showChanges, let diff = session.diff {
                    Text(Self.attributed(diff))
                } else if !session.preview.isEmpty {
                    Text(session.preview)
                } else if session.phase == .ready {
                    Text("Choose an action, or type your own instruction. ⌘1–⌘6 work too.")
                        .foregroundStyle(.secondary)
                } else if session.phase == .capturing {
                    Text("Reading the selection…")
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(8)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }

    @ViewBuilder
    private var messages: some View {
        if let error = session.error {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error.localizedDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let recovery = error.recoveryAction {
                    Button(Self.title(for: recovery)) { model.perform(recovery) }
                }
            }
            .font(.callout)
        } else if let notice = session.notice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let capture = session.capture, !capture.canReplace, session.result != nil {
            Label(capture.replaceBlocker?.localizedDescription ?? "", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Replace") { model.replace() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!session.canReplace)
                .help("Replace the selection (⌘↩)")
            Button("Copy") { model.copyResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session.copyableText == nil || session.isRunning)
                .help("Copy the result (⇧⌘C)")
            Button("Retry") { model.retry() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.action == nil || !session.canRun)
                .help("Run the same action again (⌘R)")
            Spacer()
            Button("Close") { model.closePanel() }
                .keyboardShortcut(.cancelAction)
                .help("Close (⎋)")
        }
    }

    static func title(for recovery: RecoveryAction) -> String {
        switch recovery {
        case .openSettings: "Open Settings"
        case .openAccessibilitySettings: "Open Accessibility Settings"
        case .openBilling: "Open Billing"
        case .openAPIKeys: "Manage API Keys"
        case .retry: "Retry"
        }
    }

    static func attributed(_ diff: [DiffSegment]) -> AttributedString {
        var result = AttributedString()
        for segment in diff {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .inserted:
                part.backgroundColor = Color.green.opacity(0.25)
            case .removed:
                part.strikethroughStyle = .single
                part.foregroundColor = .secondary
                part.backgroundColor = Color.red.opacity(0.18)
            }
            result += part
        }
        return result
    }
}

private struct OriginalTextView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)
        } label: {
            Text("Original · \(text.count.formatted()) characters · \(text.prefix(60).replacingOccurrences(of: "\n", with: " "))\(text.count > 60 ? "…" : "")")
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
