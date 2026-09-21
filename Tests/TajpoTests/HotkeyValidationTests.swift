import Carbon
import Testing
@testable import TajpoCore

@Test func hotkeySwapActivatesNewRegistrationOnSuccess() {
    #expect(HotkeySwapPlanner.decision(newRegistrationSucceeded: true) == .activateNew)
}

@Test func hotkeySwapKeepsPreviousRegistrationOnFailure() {
    // A failed re-registration must never leave the user with no hotkey.
    #expect(HotkeySwapPlanner.decision(newRegistrationSucceeded: false) == .keepPrevious)
}

@Test func hotkeySwapDecisionIsStableAcrossRepeatedConfigures() {
    // Rapid repeated configure calls must stay idempotent: each successful
    // call re-activates, each failed call keeps the previous registration.
    for _ in 0..<8 {
        #expect(HotkeySwapPlanner.decision(newRegistrationSucceeded: true) == .activateNew)
        #expect(HotkeySwapPlanner.decision(newRegistrationSucceeded: false) == .keepPrevious)
    }
}

@Test func allSinglePrimaryModifiersAreAccepted() throws {
    try HotkeySpec.validate(modifiers: HotkeySpec.carbonModifiers(command: true, option: false, control: false, shift: false))
    try HotkeySpec.validate(modifiers: HotkeySpec.carbonModifiers(command: false, option: true, control: false, shift: false))
    try HotkeySpec.validate(modifiers: HotkeySpec.carbonModifiers(command: false, option: false, control: true, shift: false))
}

@Test func everyModifierBitCombinationIsRejectedOrAcceptedCorrectly() {
    let cmd = UInt32(cmdKey)
    let opt = UInt32(optionKey)
    let ctrl = UInt32(controlKey)
    let shift = UInt32(shiftKey)
    for mask in 0..<16 {
        let modifiers = UInt32(mask & 1 != 0 ? cmd : 0) | UInt32(mask & 2 != 0 ? opt : 0)
            | UInt32(mask & 4 != 0 ? ctrl : 0) | UInt32(mask & 8 != 0 ? shift : 0)
        let hasPrimary = modifiers & UInt32(cmd | opt | ctrl) != 0
        if hasPrimary {
            #expect(throws: Never.self) { try HotkeySpec.validate(modifiers: modifiers) }
        } else {
            #expect(throws: TajpoError.hotkeyNeedsModifier) { try HotkeySpec.validate(modifiers: modifiers) }
        }
    }
}
