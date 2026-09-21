import CoreGraphics
import Testing
@testable import TajpoCore

@Test func panelStaysInsidePrimaryVisibleFrame() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 420, height: 220)
    let origin = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 720, y: 400),
        size: size,
        visibleFrame: visible
    )
    #expect(origin.x >= visible.minX + 12)
    #expect(origin.y >= visible.minY + 12)
    #expect(origin.x + size.width <= visible.maxX - 12)
    #expect(origin.y + size.height <= visible.maxY - 12)
}

@Test func panelClampsOnSecondaryDisplayWithNonZeroOrigin() {
    let visible = CGRect(x: 1440, y: 100, width: 1920, height: 1055)
    let size = CGSize(width: 420, height: 220)
    let nearRightEdge = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 3350, y: 1100),
        size: size,
        visibleFrame: visible
    )
    #expect(nearRightEdge.x == visible.maxX - size.width - 12)
    #expect(nearRightEdge.y >= visible.minY + 12)

    let nearLeftEdge = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 1441, y: 101),
        size: size,
        visibleFrame: visible
    )
    #expect(nearLeftEdge.x == visible.minX + 12)
    #expect(nearLeftEdge.y == visible.minY + 12)
}

@Test func oversizedPanelIsNotPushedOffScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let oversized = CGSize(width: 2000, height: 1200)
    let origin = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 720, y: 400),
        size: oversized,
        visibleFrame: visible
    )
    // Larger than the visible frame: the leading edge stays at the margin
    // rather than being pushed past the top/left edge of the screen.
    #expect(origin.x == visible.minX + 12)
    #expect(origin.y == visible.minY + 12)
}

@Test func oversizedPanelClampsOnSecondaryDisplay() {
    let visible = CGRect(x: 1440, y: -80, width: 1600, height: 900)
    let oversized = CGSize(width: 1600, height: 900)
    let origin = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 2240, y: 370),
        size: oversized,
        visibleFrame: visible
    )
    #expect(origin.x == visible.minX + 12)
    #expect(origin.y == visible.minY + 12)
}

@Test func panelCentersHorizontallyOnAnchorWhenThereIsRoom() {
    let visible = CGRect(x: 1440, y: 100, width: 1920, height: 1055)
    let size = CGSize(width: 400, height: 200)
    let origin = SelectionGeometry.panelOrigin(
        anchor: CGPoint(x: 2400, y: 600),
        size: size,
        visibleFrame: visible
    )
    #expect(origin.x == 2400 - size.width / 2)
    #expect(origin.y == 600 - size.height - 8)
}
