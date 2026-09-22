import AppKit
import SwiftUI
import TajpoCore

private final class RewritePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Floating panel shown next to the selection. It never activates Tajpo, so
/// the source app stays frontmost; it becomes key only for its own shortcuts.
///
/// The panel's height follows its content (a one-line fix gets a small panel,
/// a long text a tall one with scrolling); the user chooses the width.
@MainActor
final class InlinePanelController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onOutsideClick: (() -> Void)?

    private var panel: NSPanel?
    private var clickMonitor: Any?
    /// Where the panel was asked to appear; it re-anchors there while it grows,
    /// until the user moves it.
    private var anchor: CGRect?
    private var mouseAtShow: CGPoint = .zero
    private var userMoved = false
    private var isPlacing = false

    private static let widthKey = "panelWidth"
    static let minimumWidth: CGFloat = 520
    static let defaultWidth: CGFloat = 580

    func show(model: AppModel, near selection: CGRect?, sourceName: String? = nil, sourceIcon: NSImage? = nil) {
        model.session.sourceName = sourceName
        model.session.sourceIcon = sourceIcon
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        panel.title = sourceName.map { "Tajpo — \($0)" } ?? "Tajpo"
        anchor = selection
        mouseAtShow = NSEvent.mouseLocation
        userMoved = false
        place(panel, size: panel.frame.size)
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

    /// Resizes the panel to the height its content needs.
    func fit(contentHeight: CGFloat) {
        guard let panel, contentHeight > 0 else { return }
        let height = ceil(contentHeight)
        guard abs(panel.frame.height - height) >= 1 else { return }
        let size = NSSize(width: panel.frame.width, height: height)
        if userMoved || !panel.isVisible {
            // Keep the top edge where the user put it, and stay on screen.
            var frame = panel.frame
            frame.origin.y = frame.maxY - height
            frame.size = size
            if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - height)
            }
            setFrame(frame, on: panel)
        } else {
            place(panel, size: size)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        removeClickMonitor()
        onClose?()
    }

    /// Only the width is user-resizable; the height follows the content.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minimumWidth), height: sender.frame.height)
    }

    func windowDidMove(_ notification: Notification) {
        if !isPlacing { userMoved = true }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let width = panel?.frame.width else { return }
        UserDefaults.standard.set(Double(width), forKey: Self.widthKey)
    }

    // MARK: Private

    private func place(_ panel: NSPanel, size: NSSize) {
        let screens = NSScreen.screens.map { ScreenFrame(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let origin = PanelPlacement.origin(selection: anchor, mouse: mouseAtShow, size: size, screens: screens)
        setFrame(NSRect(origin: origin, size: size), on: panel)
    }

    private func setFrame(_ frame: NSRect, on panel: NSPanel) {
        isPlacing = true
        panel.setFrame(frame, display: true)
        // Keep the content in step with the frame, which matters most when the panel shrinks.
        if let content = panel.contentView {
            content.frame = NSRect(origin: .zero, size: frame.size)
            content.layoutSubtreeIfNeeded()
        }
        isPlacing = false
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let saved = UserDefaults.standard.double(forKey: Self.widthKey)
        let width = max(saved > 0 ? saved : Self.defaultWidth, Self.minimumWidth)
        let panel = RewritePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tajpo"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: Self.minimumWidth, height: 100)
        panel.delegate = self

        // A translucent background like other floating Mac panels.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        let hosting = NSHostingView(rootView: InlineRewriteView(model: model, session: model.session) { [weak self] height in
            self?.fit(contentHeight: height)
        })
        // The controller sizes the window from the measured content instead.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background
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
    let onHeightChange: (CGFloat) -> Void
    @FocusState private var instructionFocused: Bool
    @State private var resultHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let suggestions = [
        "Translate to English",
        "Make it a bullet list",
        "Make it more formal",
        "Explain it more simply",
        "Fix the formatting"
    ]

    /// Result area limits; longer results scroll.
    private static let resultMinHeight: CGFloat = 44
    private static var resultMaxHeight: CGFloat {
        min(420, (NSScreen.main?.visibleFrame.height ?? 800) * 0.5)
    }

    init(model: AppModel, session: RewriteSession, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.model = model
        self.session = session
        self.onHeightChange = onHeightChange
        presets = model.presets
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Group {
                if let capture = session.capture {
                    content(capture)
                } else if let error = session.error {
                    errorState(error)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the selection…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 5)
        .padding(.bottom, 14)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            onHeightChange(height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .tint(Brand.accent)
        .onChange(of: session.phase) { _, phase in announce(phase) }
    }

    // MARK: Header

    /// Sits in the transparent title bar, next to the close button.
    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: session.sourceIcon ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(session.sourceName ?? "Tajpo")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if session.capture != nil {
                presetMenu
                    .disabled(session.isRunning)
            }
        }
        .padding(.leading, 20)
        .frame(height: 18)
    }

    // MARK: States

    private func errorState(_ error: TajpoError) -> some View {
        VStack(spacing: 10) {
            Image(systemName: Self.errorSymbol(error))
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(Self.errorTitle(error))
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack {
                Button("Close") { model.closePanel() }
                    .keyboardShortcut(.cancelAction)
                if let recovery = error.recoveryAction {
                    Button(Self.title(for: recovery)) { model.perform(recovery) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func content(_ capture: TextCapture) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OriginalTextView(text: capture.text)
            if let blocker = capture.replaceBlocker {
                Callout(symbol: "doc.on.clipboard", tint: .secondary,
                        text: blocker == .replaceNotSupported
                            ? "This text can't be edited here, so Tajpo will offer Copy instead of Replace."
                            : blocker.localizedDescription)
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
                actionButton(action)
            }
            Menu {
                ForEach(RewriteTone.allCases) { tone in
                    Button { model.runTone(tone) } label: {
                        if tone == session.tone { Label(tone.title, systemImage: "checkmark") } else { Text(tone.title) }
                    }
                }
            } label: {
                Label("Tone", systemImage: Self.symbol(for: .changeTone))
            } primaryAction: {
                model.run(.changeTone)
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Change Tone to \(session.tone.title) (⌘5). Click the arrow to pick another tone.")
            .accessibilityAddTraits(session.action == .changeTone ? .isSelected : [])
            // Menus don't honor keyboard shortcuts reliably, so ⌘5 lives on a hidden button.
            Button("") { model.run(.changeTone) }
                .keyboardShortcut("5", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .disabled(!session.canRun)
    }

    @ViewBuilder
    private func actionButton(_ action: RewriteAction) -> some View {
        let button = Button { model.run(action) } label: {
            Label(action.title, systemImage: Self.symbol(for: action))
        }
        .keyboardShortcut(KeyEquivalent(Character(String(action.shortcutNumber))), modifiers: .command)
        .fixedSize()
        .help("\(action.title) (⌘\(action.shortcutNumber))")
        .accessibilityAddTraits(session.action == action ? .isSelected : [])
        if session.action == action {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    static func symbol(for action: RewriteAction) -> String {
        switch action {
        case .correct: "checkmark.circle"
        case .improve: "wand.and.stars"
        case .rewrite: "arrow.triangle.2.circlepath"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .changeTone: "theatermasks"
        case .custom: "text.bubble"
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
            Label(presets.selected.map { "Style: \($0.name)" } ?? "No style preset", systemImage: "text.badge.star")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Style preset: extra instructions for Improve, Rewrite, Shorten, Tone, and your own instructions. Correct never uses it.")
    }

    private var instructionRow: some View {
        HStack(spacing: 6) {
            TextField("Or tell Tajpo what to do, e.g. “make it a bullet list”", text: $session.instruction)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
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
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Recent and suggested instructions")
            .accessibilityLabel("Instruction suggestions")
            Button { model.run(.custom) } label: {
                ShortcutLabel(title: "Go", keys: "⌘6")
            }
            .controlSize(.large)
            .keyboardShortcut("6", modifiers: .command)
            .buttonStyle(.bordered)
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
                    Text(runningTitle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { model.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                        .controlSize(.small)
                } else {
                    Text(outputTitle)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    if let stats = resultStats {
                        Text(stats)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    Spacer()
                    if session.diff != nil {
                        Toggle("Show changes", isOn: $session.showChanges)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .font(.callout)
            .frame(height: 22)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider().opacity(0.6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        outputText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        resultHeight = height
                    }
                }
                .scrollIndicators(resultHeight > Self.resultMaxHeight ? .automatic : .never)
                .frame(height: min(max(resultHeight, Self.resultMinHeight), Self.resultMaxHeight))
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
    }

    @ViewBuilder
    private var outputText: some View {
        if session.showChanges, let diff = session.diff {
            Text(Self.attributed(diff))
                .lineSpacing(2)
                .accessibilityLabel(Text(session.result ?? ""))
                .accessibilityValue("\(diff.filter { $0.kind != .same }.count) changes")
        } else if !session.preview.isEmpty {
            Text(session.preview)
                .lineSpacing(2)
        } else if session.isRunning, let capture = session.capture {
            // Skeleton until the first words arrive.
            Text(capture.text.prefix(300))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else {
            Text(session.phase == .ready
                 ? "Choose an action or type an instruction. Nothing changes in your text until you press Replace."
                 : " ")
                .foregroundStyle(.secondary)
        }
    }

    private var runningTitle: String {
        let verb = switch session.action {
        case .correct: "Correcting"
        case .improve: "Improving"
        case .rewrite: "Rewriting"
        case .shorten: "Shortening"
        case .changeTone: "Changing the tone"
        default: "Writing"
        }
        let count = session.preview.count
        return count < 50 ? "\(verb)…" : "\(verb)… \(count / 50 * 50)+ characters"
    }

    private var outputTitle: String {
        guard let action = session.action, session.result != nil else { return "Result" }
        var parts = [action == .custom ? "Custom" : action.title]
        if action == .changeTone { parts[0] = "Tone: \(session.tone.title)" }
        if action != .correct, let preset = presets.selected { parts.append(preset.name) }
        return parts.joined(separator: " · ")
    }

    /// A short summary of what changed, e.g. "3 fixes" or "84 → 61 words".
    private var resultStats: String? {
        guard let result = session.result, let capture = session.capture else { return nil }
        if session.action == .correct {
            let fixes = session.diff?.filter { $0.kind == .inserted }.count ?? 0
            return fixes == 0 ? "No mistakes found" : "\(fixes) \(fixes == 1 ? "fix" : "fixes")"
        }
        let before = Self.wordCount(capture.text)
        let after = Self.wordCount(result)
        return before == after ? "\(after) words" : "\(before) → \(after) words"
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    @ViewBuilder
    private var messages: some View {
        if let error = session.error {
            Callout(symbol: "exclamationmark.triangle.fill", tint: .orange, text: error.localizedDescription) {
                if let recovery = error.recoveryAction {
                    Button(Self.title(for: recovery)) { model.perform(recovery) }
                        .controlSize(.small)
                }
            }
        } else if let notice = session.notice {
            Callout(symbol: "checkmark.circle.fill", tint: .green, text: notice)
        } else if let tip = session.tip {
            Callout(symbol: "lightbulb", tint: .yellow, text: tip)
        }
    }

    private func footer(_ capture: TextCapture) -> some View {
        HStack(spacing: 8) {
            Button { model.retry() } label: { ShortcutLabel(title: "Retry", keys: "⌘R") }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.action == nil || !session.canRun)
            Spacer()
            // Esc stops a running request first; a second Esc closes.
            Button(session.isRunning ? "Stop" : "Close") {
                if session.isRunning { model.stop() } else { model.closePanel() }
            }
            .keyboardShortcut(.cancelAction)
            if capture.canReplace {
                Button { model.copyResult() } label: { ShortcutLabel(title: "Copy", keys: "⇧⌘C") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(session.copyableText == nil || session.isRunning)
                Button { model.replace() } label: { ShortcutLabel(title: "Replace", keys: "⌘↩", prominent: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canReplace)
            } else {
                Button { model.copyResult(closeAfter: true) } label: { ShortcutLabel(title: "Copy", keys: "⌘↩", prominent: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.copyableText == nil || session.isRunning)
            }
        }
        .controlSize(.large)
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
        for (index, segment) in diff.enumerated() {
            // Keep a removed word and its replacement visually apart.
            if segment.kind == .inserted, index > 0, diff[index - 1].kind == .removed {
                result += AttributedString("\u{2009}")
            }
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
    var prominent = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text(keys)
                .font(.caption.monospaced())
                .foregroundStyle(prominent ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        }
    }
}

/// A tinted message box used for errors, confirmations, and tips.
private struct Callout<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.12)))
    }
}

extension Callout where Accessory == EmptyView {
    init(symbol: String, tint: Color, text: String) {
        self.init(symbol: symbol, tint: tint, text: text) { EmptyView() }
    }
}

private struct OriginalTextView: View {
    let text: String
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text("Original").fontWeight(.medium)
                    if !expanded {
                        Text(text.prefix(120).replacingOccurrences(of: "\n", with: " "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Text("\(InlineRewriteView.wordCount(text).formatted()) words")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)
            .accessibilityLabel("Original text, \(InlineRewriteView.wordCount(text)) words")
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: 110)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
