import AppKit
@preconcurrency import ApplicationServices

public enum SelectionGeometry {
    public static func frame(for element: AXUIElement?) -> CGRect? {
        guard let element else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue else { return nil }
        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.width.isFinite,
              rect.height.isFinite else { return nil }
        return cocoaFrame(fromAX: rect)
    }

    public static func cocoaFrame(fromAX rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let maxY = primary?.frame.maxY ?? 0
        return CGRect(x: rect.origin.x, y: maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func panelOrigin(anchor: CGPoint, size: CGSize, on screen: NSScreen?) -> CGPoint {
        let visible = screen?.visibleFrame ?? .zero
        return panelOrigin(anchor: anchor, size: size, visibleFrame: visible)
    }

    /// Pure placement math, separated from NSScreen so it can be unit tested
    /// for multi-display edge cases (non-zero origins, oversized panels).
    public static func panelOrigin(anchor: CGPoint, size: CGSize, visibleFrame visible: CGRect) -> CGPoint {
        // Clamp so the panel stays fully on screen whenever it fits. If the
        // panel is larger than the visible frame on an axis, keep its
        // leading/top edge at the margin instead of pushing it off screen.
        let maxX = max(visible.maxX - size.width - 12, visible.minX + 12)
        let maxY = max(visible.maxY - size.height - 12, visible.minY + 12)
        return CGPoint(
            x: min(max(anchor.x - size.width / 2, visible.minX + 12), maxX),
            y: min(max(anchor.y - size.height - 8, visible.minY + 12), maxY)
        )
    }
}
