import Carbon
import Foundation

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
        unregisterLocked(id: id)
        var identifier = EventHotKeyID(signature: OSType(0x544A504F), id: id)
        var reference: EventHotKeyRef?
        guard RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        ) == noErr, let reference else {
            throw TajpoError.hotkeyUnavailable
        }
        references[id] = reference
        handlers[id] = handler
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
