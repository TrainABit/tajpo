import AppKit
import Carbon
import SwiftUI

public struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let onApply: () -> Void

    @State private var listening = false
    @State private var monitor: Any?

    public init(keyCode: Binding<UInt32>, modifiers: Binding<UInt32>, onApply: @escaping () -> Void) {
        _keyCode = keyCode
        _modifiers = modifiers
        self.onApply = onApply
    }

    public var body: some View {
        HStack {
            Button(listening ? "Press a shortcut..." : HotkeySpec(keyCode: keyCode, modifiers: modifiers).label) {
                listening.toggle()
            }
            Text("Click, then hold modifiers and a key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: listening) { _, isListening in
            if isListening { start() } else { stop() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording and keeps the previously saved shortcut.
            if event.keyCode == UInt16(kVK_Escape) {
                listening = false
                return nil
            }
            let recorded = carbonModifiers(from: event.modifierFlags)
            guard recorded != 0 else { return event }
            keyCode = UInt32(event.keyCode)
            modifiers = recorded
            listening = false
            onApply()
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        HotkeySpec.carbonModifiers(
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }
}
