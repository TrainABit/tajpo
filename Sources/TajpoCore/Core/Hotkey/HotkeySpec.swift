import Carbon
import Foundation

public struct HotkeySpec: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var label: String {
        Self.modifierSymbols(modifiers) + Self.title(forKeyCode: keyCode)
    }

    /// Bits accepted in a hotkey modifier mask. Anything outside these is
    /// garbage left over from raw event flags or a corrupt preference.
    public static let allowedModifierBits: UInt32 = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    public static func validate(modifiers: UInt32) throws {
        guard modifiers != 0, modifiers & ~allowedModifierBits == 0 else {
            throw TajpoError.hotkeyNeedsModifier
        }
        // Shift-only shortcuts collide with regular typing (e.g. Shift+T).
        let primary = modifiers & UInt32(cmdKey | optionKey | controlKey)
        guard primary != 0 else { throw TajpoError.hotkeyNeedsModifier }
    }

    public static func title(forKeyCode code: UInt32) -> String {
        namedKeys[code] ?? "Key \(code)"
    }

    public static func modifierSymbols(_ modifiers: UInt32) -> String {
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "")
            + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
            + (modifiers & UInt32(controlKey) != 0 ? "⌃" : "")
            + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "")
    }

    public static func carbonModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt32 {
        var value: UInt32 = 0
        if command { value |= UInt32(cmdKey) }
        if option { value |= UInt32(optionKey) }
        if control { value |= UInt32(controlKey) }
        if shift { value |= UInt32(shiftKey) }
        return value
    }

    public static func contains(_ modifiers: UInt32, flag: Int) -> Bool {
        modifiers & UInt32(flag) != 0
    }

    public static let namedKeys: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6"
    ]
}
