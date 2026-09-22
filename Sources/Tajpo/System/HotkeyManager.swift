import Carbon
import TajpoCore

enum HotkeyAction: UInt32, CaseIterable, Identifiable {
    case rewrite = 1
    case repeatLast = 2

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .rewrite: "Rewrite selection"
        case .repeatLast: "Repeat last action"
        }
    }
}

/// "TJPO": identifies Tajpo's hotkeys in Carbon events.
private let hotkeySignature: OSType = 0x544A_504F

/// Registers global shortcuts with Carbon. A new shortcut is registered before
/// the old one is released, so a failed change keeps the working shortcut.
@MainActor
final class HotkeyManager {
    var onPress: ((HotkeyAction) -> Void)?

    private(set) var shortcuts: [HotkeyAction: GlobalShortcut] = [:]
    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var isSuspended = false

    func register(_ shortcut: GlobalShortcut?, for action: HotkeyAction) throws {
        if let shortcut {
            try shortcut.validate()
            if shortcuts.contains(where: { $0.key != action && $0.value == shortcut }) {
                throw TajpoError.hotkeyDuplicate
            }
            if shortcuts[action] == shortcut, references[action] != nil || isSuspended { return }
        }
        guard !isSuspended else {
            shortcuts[action] = shortcut
            return
        }
        let newReference = try shortcut.map { try makeReference($0, for: action) }
        if let old = references.removeValue(forKey: action) {
            UnregisterEventHotKey(old)
        }
        references[action] = newReference
        shortcuts[action] = shortcut
    }

    /// Temporarily releases all shortcuts (e.g. while recording a new one, so
    /// the old shortcut doesn't swallow the keystroke).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for (action, shortcut) in shortcuts {
            do {
                references[action] = try makeReference(shortcut, for: action)
            } catch {
                Log.hotkey.error("Could not re-register \(action.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func makeReference(_ shortcut: GlobalShortcut, for action: HotkeyAction) throws -> EventHotKeyRef {
        try installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: hotkeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            Log.hotkey.error("RegisterEventHotKey failed with \(status)")
            if status == OSStatus(eventHotKeyExistsErr) {
                throw TajpoError.hotkeyInUse(shortcut.displayString)
            }
            throw TajpoError.hotkeyRejectedBySystem(shortcut.displayString)
        }
        return reference
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr, identifier.signature == hotkeySignature,
                  let action = HotkeyAction(rawValue: identifier.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { manager.onPress?(action) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            throw TajpoError.hotkeyRejectedBySystem("the shortcut")
        }
    }
}
