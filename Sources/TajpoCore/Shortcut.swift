import Foundation

/// A global keyboard shortcut as Carbon understands it: a virtual key code
/// plus Carbon modifier flags.
public struct GlobalShortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey in Events.h).
    public enum Modifier {
        public static let command: UInt32 = 1 << 8
        public static let shift: UInt32 = 1 << 9
        public static let option: UInt32 = 1 << 11
        public static let control: UInt32 = 1 << 12
        public static let all: UInt32 = command | shift | option | control
    }

    // ⌃⌥T and ⌃⌥R: ⌥⌘T is Show/Hide Toolbar in most AppKit apps.
    public static let defaultRewrite = GlobalShortcut(keyCode: KeyCode.t, modifiers: Modifier.control | Modifier.option)
    public static let defaultRepeat = GlobalShortcut(keyCode: KeyCode.r, modifiers: Modifier.control | Modifier.option)

    public var hasCommand: Bool { modifiers & Modifier.command != 0 }
    public var hasControl: Bool { modifiers & Modifier.control != 0 }
    public var hasOption: Bool { modifiers & Modifier.option != 0 }
    public var hasShift: Bool { modifiers & Modifier.shift != 0 }

    /// Symbols in the macOS order ⌃⌥⇧⌘, followed by the key.
    public var displayString: String {
        (hasControl ? "⌃" : "") + (hasOption ? "⌥" : "") + (hasShift ? "⇧" : "") + (hasCommand ? "⌘" : "")
            + KeyCode.name(for: keyCode)
    }

    /// Rejects shortcuts that would block typing or that macOS reserves.
    /// ⇧- and ⌥-only shortcuts swallow characters (⌥E is the accent key), and
    /// macOS 15+ refuses ⌥/⌥⇧-only hotkeys anyway.
    public func validate() throws {
        guard hasCommand || hasControl else { throw TajpoError.hotkeyNeedsCommandOrControl }
        let commandOnly = modifiers & Modifier.all == Modifier.command
        let commandShiftOnly = modifiers & Modifier.all == Modifier.command | Modifier.shift
        if commandOnly && KeyCode.reservedWithCommand.contains(keyCode) {
            throw TajpoError.hotkeyReserved(displayString)
        }
        if commandShiftOnly && KeyCode.reservedWithCommandShift.contains(keyCode) {
            throw TajpoError.hotkeyReserved(displayString)
        }
        // ⌃Space switches input sources; ⌥⌘Space opens Finder search.
        let exact = modifiers & Modifier.all
        if keyCode == KeyCode.space && (exact == Modifier.control || exact == Modifier.command | Modifier.option) {
            throw TajpoError.hotkeyReserved(displayString)
        }
        if hasCommand && keyCode == KeyCode.tab {
            throw TajpoError.hotkeyReserved(displayString)
        }
    }
}

/// US-ANSI virtual key codes (kVK_* in Carbon's Events.h).
public enum KeyCode {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, o: UInt32 = 0x1F, u: UInt32 = 0x20, i: UInt32 = 0x22
    public static let p: UInt32 = 0x23, l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E
    public static let space: UInt32 = 0x31, tab: UInt32 = 0x30, returnKey: UInt32 = 0x24
    public static let escape: UInt32 = 0x35, delete: UInt32 = 0x33

    static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟"
    ]

    public static func name(for code: UInt32) -> String {
        names[code] ?? "Key \(code)"
    }

    public static func isKnown(_ code: UInt32) -> Bool { names[code] != nil }

    /// ⌘+key combinations every Mac app relies on.
    static let reservedWithCommand: Set<UInt32> = [q, w, c, v, x, z, a, s, n, o, p, f, h, m, t, tab, space]
    static let reservedWithCommandShift: Set<UInt32> = [z, 0x14, 0x15, 0x17]
}
