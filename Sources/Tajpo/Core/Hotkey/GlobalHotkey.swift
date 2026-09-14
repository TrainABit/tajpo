import Carbon

final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        guard modifiers != 0 else { throw TajpoError.hotkeyNeedsModifier }
        self.action = action
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &type, pointer, &eventHandler)
        guard handlerStatus == noErr else { throw TajpoError.hotkeyUnavailable }

        var identifier = EventHotKeyID(signature: OSType(0x544A504F), id: 1)
        guard RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference) == noErr else {
            tearDown()
            throw TajpoError.hotkeyUnavailable
        }
    }

    deinit {
        tearDown()
    }

    private func tearDown() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
