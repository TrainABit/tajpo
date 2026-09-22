import AppKit
import SwiftUI
import TajpoCore

/// Click to record a shortcut, then press it. ⎋ cancels, ⌫ clears.
struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let shortcut: GlobalShortcut?
    let onRecordingChanged: (Bool) -> Void
    let onRecord: (GlobalShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = shortcut
        button.setAccessibilityLabel("\(label) shortcut")
        button.setAccessibilityValue(shortcut?.displayString ?? "None")
        button.onRecordingChanged = onRecordingChanged
        button.onRecord = onRecord
        button.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var shortcut: GlobalShortcut?
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecord: ((GlobalShortcut?) -> Void)?
    private var isRecording = false {
        didSet {
            refreshTitle()
            if oldValue != isRecording { onRecordingChanged?(isRecording) }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: super.intrinsicContentSize.height) }

    func refreshTitle() {
        title = isRecording ? "Type shortcut…" : (shortcut?.displayString ?? "Click to record")
        bezelColor = isRecording ? .controlAccentColor : nil
    }

    /// Shows the modifiers being held while recording, e.g. "⌃⌥…".
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        let flags = event.modifierFlags
        let held = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        title = held.isEmpty ? "Type shortcut…" : held + "…"
    }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = UInt32(event.keyCode)
        if flags.intersection([.command, .control, .option, .shift]).isEmpty {
            if code == KeyCode.escape {
                finish(nil, record: false)
            } else if code == KeyCode.delete || code == 0x75 {
                finish(nil, record: true)
            } else {
                NSSound.beep()
            }
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= GlobalShortcut.Modifier.command }
        if flags.contains(.control) { modifiers |= GlobalShortcut.Modifier.control }
        if flags.contains(.option) { modifiers |= GlobalShortcut.Modifier.option }
        if flags.contains(.shift) { modifiers |= GlobalShortcut.Modifier.shift }
        finish(GlobalShortcut(keyCode: code, modifiers: modifiers), record: true)
    }

    private func finish(_ shortcut: GlobalShortcut?, record: Bool) {
        isRecording = false
        window?.makeFirstResponder(nil)
        if record { onRecord?(shortcut) }
    }
}

/// A recorder plus inline result for one of Tajpo's actions.
struct ShortcutSetting: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let action: HotkeyAction
    @State private var message: String?

    init(model: AppModel, action: HotkeyAction) {
        self.model = model
        settings = model.settings
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.title)
                Spacer()
                ShortcutRecorder(
                    label: action.title,
                    shortcut: settings.shortcut(for: action),
                    onRecordingChanged: { recording in
                        recording ? model.hotkeys.suspend() : model.hotkeys.resume()
                    },
                    onRecord: { shortcut in
                        model.hotkeys.resume()
                        if let error = model.applyShortcut(shortcut, for: action) {
                            message = error.localizedDescription
                        } else {
                            message = shortcut.map { "Saved. Press \($0.displayString) in any app." } ?? "Shortcut removed."
                        }
                    }
                )
                .frame(width: 150)
                if settings.shortcut(for: action) != nil {
                    Button {
                        message = model.applyShortcut(nil, for: action)?.localizedDescription ?? "Shortcut turned off."
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Turn this shortcut off")
                    .accessibilityLabel("Clear \(action.title) shortcut")
                }
                Button("Reset") {
                    let fallback = action == .rewrite ? GlobalShortcut.defaultRewrite : .defaultRepeat
                    message = model.applyShortcut(fallback, for: action)?.localizedDescription ?? "Restored \(fallback.displayString)."
                }
            }
            if let error = model.hotkeyErrors[action] {
                ErrorLabel(text: error.localizedDescription)
            } else if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
