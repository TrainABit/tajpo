import Carbon
import Foundation

protocol GlobalHotkeyRegistering: AnyObject {
    func registerDefault(handler: @escaping @Sendable () -> Void) throws
}

final class CarbonGlobalHotkey: GlobalHotkeyRegistering, @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (@Sendable () -> Void)?

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func registerDefault(handler: @escaping @Sendable () -> Void) throws {
        self.handler = handler
        let signature = OSType(0x544A504F) // TJPO
        var id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(optionKey | cmdKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw HotkeyError.registrationFailed(status) }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<CarbonGlobalHotkey>.fromOpaque(context).takeUnretainedValue().handler?()
            return noErr
        }, 1, &eventType, pointer, &eventHandler)
    }
}

enum HotkeyError: LocalizedError {
    case registrationFailed(OSStatus)
    var errorDescription: String? { "Could not register the global hotkey." }
}
