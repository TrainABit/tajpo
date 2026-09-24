import AppKit
import SwiftUI

/// Tajpo's colors, taken from the app icon. Used for the setup guide, the
/// panel's selected action and main buttons, so the app reads as one product.
enum Brand {
    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.93)

    /// Lighter in dark mode, so text and icons in the accent keep their contrast.
    static let accent = Color(nsColor: NSColor(name: "TajpoAccent") { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            NSColor(srgbRed: 0.49, green: 0.47, blue: 1.0, alpha: 1)
        } else {
            NSColor(srgbRed: 0.38, green: 0.33, blue: 0.93, alpha: 1)
        }
    })

}
