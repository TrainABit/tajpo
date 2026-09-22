import Foundation
import OSLog

/// Diagnostics only. Never log selected or generated text.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.trainabit.tajpo"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let selection = Logger(subsystem: subsystem, category: "selection")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
