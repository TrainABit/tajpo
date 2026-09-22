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
    static let minimumSize = NSSize(width: 440, height: 240)

    func show(model: AppModel, near selection: CGRect?, sourceName: String? = nil) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        panel.title = sourceName.map { "Tajpo — \($0)" } ?? "Tajpo"
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
        var size = saved ?? NSSize(width: 500, height: 380)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        Group {
            if let capture = session.capture {
                content(capture)
            } else if let error = session.error {
                errorState(error)
            } else {
                ProgressView("Reading the selection…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(minWidth: InlinePanelController.minimumSize.width, minHeight: InlinePanelController.minimumSize.height)
        .onChange(of: session.phase) { _, phase in announce(phase) }
    }

    // MARK: States

    private func errorState(_ error: TajpoError) -> some View {
        ContentUnavailableView {
            Label(Self.errorTitle(error), systemImage: Self.errorSymbol(error))
        } description: {
            Text(error.localizedDescription)
        } actions: {
            HStack {
                if let recovery = error.recoveryAction {
                    Button(Self.title(for: recovery)) { model.perform(recovery) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Close") { model.closePanel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func content(_ capture: TextCapture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OriginalTextView(text: capture.text)
            if let blocker = capture.replaceBlocker {
                Label(blocker == .replaceNotSupported
                      ? "This text can't be edited here, so Tajpo will offer Copy instead of Replace."
                      : blocker.localizedDescription,
                      systemImage: "doc.on.clipboard")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            actionRow
            instructionRow
            output
            messages
            footer(capture)
        }
    }

    // MARK: Controls

    private var actionRow: some View {
        HStack(spacing: 6) {
            ForEach(RewriteAction.buttons.filter { $0 != .changeTone }) { action in
                Button { model.run(action) } label: {
                    actionLabel(action.title, selected: session.action == action)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(action.shortcutNumber))), modifiers: .command)
                .help("\(action.title) (⌘\(action.shortcutNumber))")
                .accessibilityAddTraits(session.action == action ? .isSelected : [])
            }
            Menu {
                ForEach(RewriteTone.allCases) { tone in
                    Button(tone.title) { model.runTone(tone) }
                }
            } label: {
                actionLabel("Tone: \(session.tone.title)", selected: session.action == .changeTone)
            } primaryAction: {
                model.run(.changeTone)
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Change Tone (⌘5). Click the arrow to pick a tone.")
            .accessibilityAddTraits(session.action == .changeTone ? .isSelected : [])
            // Menus don't honor keyboard shortcuts reliably, so ⌘5 lives on a hidden button.
            Button("") { model.run(.changeTone) }
                .keyboardShortcut("5", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            presetMenu
        }
        .buttonStyle(.bordered)
        .disabled(!session.canRun)
    }

    private func actionLabel(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 3) {
            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            Text(title)
        }
    }

    private var presetMenu: some View {
        Menu {
            Picker("Style preset", selection: Binding(get: { presets.selectedID }, set: { presets.select($0) })) {
                Text("No preset").tag(UUID?.none)
                ForEach(presets.presets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Edit Presets…") { model.showSettings(tab: .presets) }
        } label: {
            Label(presets.selected?.name ?? "No preset", systemImage: "text.badge.star")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Style preset: extra instructions for Improve, Rewrite, Shorten, Tone, and your own instructions. Correct never uses it.")
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
            Button { model.run(.custom) } label: {
                ShortcutLabel(title: "Go", keys: "⌘6")
            }
            .keyboardShortcut("6", modifiers: .command)
        }
        .disabled(!session.canRun)
        .onChange(of: session.focusInstruction) { _, focus in
            if focus {
                instructionFocused = true
                session.focusInstruction = false
            }
        }
    }

    // MARK: Output

    private var output: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if session.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Writing…").foregroundStyle(.secondary)
                    Text(session.preview.isEmpty ? "" : "\(session.preview.count / 50 * 50)+ characters")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                } else {
                    Text(outputTitle).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Show changes", isOn: $session.showChanges)
                    .toggleStyle(.checkbox)
                    .disabled(session.diff == nil)
                if session.isRunning {
                    Button("Stop") { model.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                        .controlSize(.small)
                }
            }
            .font(.callout)
            .frame(height: 24)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        outputText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(8)
                }
                .onChange(of: session.preview) { _, _ in
                    guard session.isRunning else { return }
                    if reduceMotion {
                        proxy.scrollTo("end", anchor: .bottom)
                    } else {
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }

    @ViewBuilder
    private var outputText: some View {
        if session.showChanges, let diff = session.diff {
            Text(Self.attributed(diff))
                .accessibilityLabel(Text(session.result ?? ""))
                .accessibilityValue("\(diff.filter { $0.kind != .same }.count) changes")
        } else if !session.preview.isEmpty {
            Text(session.preview)
        } else if session.isRunning, let capture = session.capture {
            // Skeleton until the first words arrive.
            Text(capture.text.prefix(400))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else {
            Text(session.phase == .ready
                 ? "Pick an action above, or type your own instruction. The result appears here before anything changes."
                 : " ")
                .foregroundStyle(.secondary)
        }
    }

    private var outputTitle: String {
        guard let action = session.action, session.result != nil else { return "Result" }
        var parts = [action == .custom ? "Custom" : action.title]
        if action == .changeTone { parts[0] = "Tone: \(session.tone.title)" }
        if action != .correct, let preset = presets.selected { parts.append(preset.name) }
        return parts.joined(separator: " · ")
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
                .foregroundStyle(.green)
        } else if let tip = session.tip {
            Label(tip, systemImage: "lightbulb")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func footer(_ capture: TextCapture) -> some View {
        HStack {
            if capture.canReplace {
                Button { model.replace() } label: { ShortcutLabel(title: "Replace", keys: "⌘↩") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canReplace)
                Button { model.copyResult() } label: { ShortcutLabel(title: "Copy", keys: "⇧⌘C") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(session.copyableText == nil || session.isRunning)
            } else {
                Button { model.copyResult(closeAfter: true) } label: { ShortcutLabel(title: "Copy", keys: "⌘↩") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.copyableText == nil || session.isRunning)
            }
            Button { model.retry() } label: { ShortcutLabel(title: "Retry", keys: "⌘R") }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.action == nil || !session.canRun)
            Spacer()
            // Esc stops a running request first; a second Esc closes.
            Button(session.isRunning ? "Stop" : "Close") {
                if session.isRunning { model.stop() } else { model.closePanel() }
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private func announce(_ phase: RewriteSession.Phase) {
        let message: String? = switch phase {
        case .running: "Writing"
        case .finished: "Result ready. Press Command-Return to use it."
        case .failed: session.error?.localizedDescription
        default: nil
        }
        if let message {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    // MARK: Helpers

    static func title(for recovery: RecoveryAction) -> String {
        switch recovery {
        case .openSettings: "Open Settings"
        case .openAccessibilitySettings: "Allow Access"
        case .openBilling: "Add Credit"
        case .openAPIKeys: "Manage API Keys"
        case .retry: "Try Again"
        }
    }

    static func errorTitle(_ error: TajpoError) -> String {
        switch error {
        case .noSelection, .selectionInTajpo: "Nothing selected"
        case .accessibilityPermissionRequired: "Allow Tajpo to read selected text"
        case .secureField: "Password field"
        case .textTooLarge, .textTooLargeForModel: "Selection too long"
        case .missingAPIKey: "Add your API key"
        case .nothingToRepeat: "Nothing to repeat yet"
        default: "Something went wrong"
        }
    }

    static func errorSymbol(_ error: TajpoError) -> String {
        switch error {
        case .noSelection, .selectionInTajpo: "text.cursor"
        case .accessibilityPermissionRequired: "hand.raised"
        case .secureField: "lock"
        case .missingAPIKey: "key"
        default: "exclamationmark.triangle"
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
                // Underline too, so changes don't rely on color alone.
                part.underlineStyle = .single
                part.backgroundColor = Color(nsColor: .systemGreen).opacity(0.3)
            case .removed:
                part.strikethroughStyle = .single
                part.foregroundColor = .secondary
                part.backgroundColor = Color(nsColor: .systemRed).opacity(0.18)
            }
            result += part
        }
        return result
    }
}

/// Button title with its keyboard shortcut shown inline.
private struct ShortcutLabel: View {
    let title: String
    let keys: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text(keys)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct OriginalTextView: View {
    let text: String
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .default) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("Original").fontWeight(.medium)
                    Text("\(text.count.formatted()) characters")
                        .foregroundStyle(.secondary)
                    if !expanded {
                        Text(text.prefix(80).replacingOccurrences(of: "\n", with: " "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)
            .accessibilityLabel("Original text, \(text.count) characters")
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 100)
            }
        }
    }
}
