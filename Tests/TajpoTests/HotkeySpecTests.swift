import Carbon
import Testing
@testable import TajpoCore

@Test func unknownHotkeyTitleDoesNotCrash() {
    #expect(HotkeySpec.title(forKeyCode: 999) == "Key 999")
    #expect(HotkeySpec.title(forKeyCode: UInt32(kVK_ANSI_T)) == "T")
}

@Test func hotkeyLabelIncludesModifiers() {
    let spec = HotkeySpec(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: HotkeySpec.carbonModifiers(command: true, option: true, control: false, shift: false)
    )
    #expect(spec.label == "⌘⌥T")
}

@Test func bareKeyIsRejected() {
    #expect(throws: TajpoError.hotkeyNeedsModifier) {
        try HotkeySpec.validate(modifiers: 0)
    }
}

@Test func modifierCombinationIsAccepted() throws {
    try HotkeySpec.validate(modifiers: HotkeySpec.carbonModifiers(command: true, option: false, control: false, shift: true))
}
