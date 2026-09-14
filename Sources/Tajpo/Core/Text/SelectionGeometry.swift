import AppKit
import ApplicationServices

enum SelectionGeometry {
    static func frame(for element: AXUIElement?) -> CGRect? {
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

    static func cocoaFrame(fromAX rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let maxY = primary?.frame.maxY ?? 0
        return CGRect(x: rect.origin.x, y: maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func panelOrigin(anchor: CGPoint, size: CGSize, on screen: NSScreen?) -> CGPoint {
        let visible = screen?.visibleFrame ?? .zero
        return CGPoint(
            x: min(max(anchor.x - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12),
            y: min(max(anchor.y - size.height - 8, visible.minY + 12), visible.maxY - size.height - 12)
        )
    }
}
