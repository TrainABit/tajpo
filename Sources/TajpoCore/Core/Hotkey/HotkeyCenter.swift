import Carbon
import Foundation

public enum HotkeySwapDecision: Equatable, Sendable {
    /// The new registration succeeded: activate it and unregister any
    /// previous registration for the same id.
    case activateNew
    /// The new registration failed: keep the previous registration (if any)
    /// active and surface the failure to the caller.
    case keepPrevious
}

/// Pure decision logic for transactional hotkey re-registration, extracted
/// from `HotkeyCenter` (which calls Carbon directly) so it can be unit tested.
public enum HotkeySwapPlanner {
    public static func decision(newRegistrationSucceeded: Bool) -> HotkeySwapDecision {
        newRegistrationSucceeded ? .activateNew : .keepPrevious
    }
}

public final class HotkeyCenter: @unchecked Sendable {
    public static let shared = HotkeyCenter()

    public static let rewriteID: UInt32 = 1

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let lock = NSLock()

    private init() {}

    public func register(id: UInt32, spec: HotkeySpec, handler: @escaping () -> Void) throws {
        try HotkeySpec.validate(modifiers: spec.modifiers)
        lock.lock()
        defer { lock.unlock() }
        try installHandlerIfNeeded()
        // Transactional re-registration: register the NEW hotkey BEFORE
        // dropping the old one, so a failed registration never leaves the
        // user with no hotkey at all.
        let identifier = EventHotKeyID(signature: OSType(0x544A504F), id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        switch HotkeySwapPlanner.decision(newRegistrationSucceeded: status == noErr && reference != nil) {
        case .keepPrevious:
            throw TajpoError.hotkeyUnavailable
        case .activateNew:
            guard let reference else { throw TajpoError.hotkeyUnavailable }
            // Idempotent: safe no-op when nothing is registered for this id,
            // so rapid repeated configure calls cannot leak references.
            unregisterLocked(id: id)
            references[id] = reference
            handlers[id] = handler
        }
    }

    public func unregister(id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        unregisterLocked(id: id)
    }

    private func unregisterLocked(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        handlers.removeValue(forKey: id)
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            ) == noErr else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotkeyCenter>.fromOpaque(context).takeUnretainedValue().invoke(id: identifier.id)
            return noErr
        }, 1, &type, pointer, &eventHandler)
        guard status == noErr else { throw TajpoError.hotkeyUnavailable }
    }

    private func invoke(id: UInt32) {
        lock.lock()
        let handler = handlers[id]
        lock.unlock()
        handler?()
    }
}
