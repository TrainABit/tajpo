import SwiftUI

/// Tajpo's colors, taken from the app icon. Used for the setup guide, the
/// panel's selected action and main buttons, so the app reads as one product.
enum Brand {
    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.93)
    static let violet = Color(red: 0.43, green: 0.20, blue: 0.82)
    static let accent = Color(red: 0.38, green: 0.33, blue: 0.93)

    static let gradient = LinearGradient(colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}
