import Carbon
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var hotkeyKeyCode: UInt32 { didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") } }
    @Published var hotkeyModifiers: UInt32 { didSet { UserDefaults.standard.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers") } }

    init() {
        model = UserDefaults.standard.string(forKey: "model") ?? "gpt-4o-mini"
        hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_T)
        hotkeyModifiers = UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? (optionKey | cmdKey))
    }

    var hotkeyLabel: String { (hotkeyModifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + (hotkeyModifiers & UInt32(optionKey) != 0 ? "⌥" : "") + (hotkeyModifiers & UInt32(controlKey) != 0 ? "⌃" : "") + Self.keys.first(where: { $0.code == hotkeyKeyCode })!.title }
    static let keys: [(title: String, code: UInt32)] = [("T", UInt32(kVK_ANSI_T)), ("R", UInt32(kVK_ANSI_R)), ("E", UInt32(kVK_ANSI_E)), ("G", UInt32(kVK_ANSI_G)), ("J", UInt32(kVK_ANSI_J)), ("K", UInt32(kVK_ANSI_K))]
}
