import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ScreenFrame: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum PanelPlacement {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 12

    /// Converts an Accessibility rectangle (origin at the top-left of the
    /// primary screen, y down) to Cocoa screen coordinates (y up).
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether an AX bounds rectangle is plausible. Some apps report zero or
    /// off-screen rectangles, which would put the panel in a corner.
    public static func isUsable(_ rect: CGRect?, screens: [ScreenFrame]) -> Bool {
        guard let rect, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height > 0, !(rect.origin == .zero && rect.width == 0) else { return false }
        return screens.contains { $0.frame.intersects(rect) }
    }

    /// Where to put a panel of `size` near `selection` (Cocoa coordinates):
    /// below the selection if it fits, otherwise above, otherwise clamped
    /// onto the screen. Falls back to the mouse position.
    public static func origin(selection: CGRect?, mouse: CGPoint, size: CGSize, screens: [ScreenFrame]) -> CGPoint {
        let target = isUsable(selection, screens: screens) ? selection! : CGRect(origin: mouse, size: .zero)
        let center = CGPoint(x: target.midX, y: target.midY)
        guard let screen = screens.first(where: { $0.frame.contains(center) })
            ?? screens.min(by: { distance($0.frame, center) < distance($1.frame, center) }) else {
            return CGPoint(x: target.midX - size.width / 2, y: target.minY - size.height - gap)
        }
        let visible = screen.visibleFrame
        let x = clamp(target.midX - size.width / 2, visible.minX + margin, visible.maxX - size.width - margin)
        let below = target.minY - gap - size.height
        let above = target.maxY + gap
        let y: CGFloat
        if below >= visible.minY + margin {
            y = below
        } else if above + size.height <= visible.maxY - margin {
            y = above
        } else {
            y = clamp(below, visible.minY + margin, visible.maxY - size.height - margin)
        }
        return CGPoint(x: x, y: y)
    }

    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        upper < lower ? lower : min(max(value, lower), upper)
    }

    static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

public enum AppPolicy {
    /// Terminal apps: pasting multi-line text at a prompt can run commands,
    /// so Replace is disabled there.
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty", "co.zeit.hyper", "com.github.wez.wezterm"
    ]

    public static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminalBundleIDs.contains(bundleID)
    }
}
