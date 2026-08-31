import Testing
import Foundation
import CoreGraphics
@testable import DockToggle

@Suite("DockGeometry")
struct DockGeometryTests {

    // MARK: - stripContains, reserved strip present

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// A 70pt Dock reserved along the bottom, in top-left-origin coordinates.
    private let visibleWithBottomDock = CGRect(x: 0, y: 0, width: 1920, height: 1010)

    @Test("a point in the reserved bottom strip is inside")
    func bottomStripHit() {
        let point = CGPoint(x: 960, y: 1015)
        #expect(DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: visibleWithBottomDock))
    }

    @Test("a point well above the reserved strip is outside")
    func aboveStripMiss() {
        let point = CGPoint(x: 960, y: 500)
        #expect(!DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: visibleWithBottomDock))
    }

    @Test("a point off the reserved strip's short axis, on another screen, is outside")
    func offScreenMiss() {
        let point = CGPoint(x: 960, y: 1015)
        let otherScreen = CGRect(x: 2000, y: 0, width: 1920, height: 1080)
        #expect(!DockGeometry.stripContains(point, screenFrame: otherScreen, visibleFrame: visibleWithBottomDock))
    }

    @Test("a point fractionally outside the screen edge still counts")
    func edgeJitterStillHits() {
        let point = CGPoint(x: 960, y: 1082)
        #expect(DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: visibleWithBottomDock))
    }

    // MARK: - stripContains, left/right reservations

    @Test("a left-docked Dock reserves the left edge")
    func leftDockStrip() {
        let visible = CGRect(x: 70, y: 0, width: 1850, height: 1080)
        let point = CGPoint(x: 35, y: 500)
        #expect(DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: visible))
    }

    @Test("a right-docked Dock reserves the right edge")
    func rightDockStrip() {
        let visible = CGRect(x: 0, y: 0, width: 1850, height: 1080)
        let point = CGPoint(x: 1900, y: 500)
        #expect(DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: visible))
    }

    // MARK: - stripContains, no reservation (auto-hide / other display)

    @Test("without a reserved strip, the fallback edge band still catches bottom clicks")
    func fallbackBandHit() {
        let point = CGPoint(x: 960, y: 1000)
        #expect(DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: screen))
    }

    @Test("without a reserved strip, the middle of the screen is outside the fallback band")
    func fallbackBandMiss() {
        let point = CGPoint(x: 960, y: 500)
        #expect(!DockGeometry.stripContains(point, screenFrame: screen, visibleFrame: screen))
    }

    // MARK: - dockOwnsPoint

    @Test("the Dock owns a point inside its own strip")
    func dockOwnsItsStrip() {
        let dock = DockGeometry.OnScreenWindow(processID: 100, layer: 20, alpha: 1,
                                                frame: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        let owns = DockGeometry.dockOwnsPoint(CGPoint(x: 960, y: 1030), windows: [dock],
                                              dockProcessID: 100, dockLayer: 20, ownProcessID: 999)
        #expect(owns)
    }

    @Test("a window drawn over the Dock strip keeps the click")
    func windowOverDockStealsPoint() {
        let coveringWindow = DockGeometry.OnScreenWindow(processID: 200, layer: 0, alpha: 1,
                                                          frame: CGRect(x: 900, y: 900, width: 200, height: 200))
        let dock = DockGeometry.OnScreenWindow(processID: 100, layer: 20, alpha: 1,
                                               frame: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        let owns = DockGeometry.dockOwnsPoint(CGPoint(x: 960, y: 1030), windows: [coveringWindow, dock],
                                              dockProcessID: 100, dockLayer: 20, ownProcessID: 999)
        #expect(!owns)
    }

    @Test("our own invisible click-catcher window is skipped, not counted as covering the Dock")
    func ownWindowIsIgnored() {
        let ownWindow = DockGeometry.OnScreenWindow(processID: 999, layer: 0, alpha: 1,
                                                     frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let dock = DockGeometry.OnScreenWindow(processID: 100, layer: 20, alpha: 1,
                                               frame: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        let owns = DockGeometry.dockOwnsPoint(CGPoint(x: 960, y: 1030), windows: [ownWindow, dock],
                                              dockProcessID: 100, dockLayer: 20, ownProcessID: 999)
        #expect(owns)
    }

    @Test("an invisible window (zero alpha) never steals the point")
    func invisibleWindowIgnored() {
        let invisible = DockGeometry.OnScreenWindow(processID: 200, layer: 0, alpha: 0,
                                                     frame: CGRect(x: 900, y: 900, width: 200, height: 200))
        let dock = DockGeometry.OnScreenWindow(processID: 100, layer: 20, alpha: 1,
                                               frame: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        let owns = DockGeometry.dockOwnsPoint(CGPoint(x: 960, y: 1030), windows: [invisible, dock],
                                              dockProcessID: 100, dockLayer: 20, ownProcessID: 999)
        #expect(owns)
    }

    @Test("no windows at all means the Dock owns nothing")
    func noWindowsMeansNoOwnership() {
        let owns = DockGeometry.dockOwnsPoint(CGPoint(x: 960, y: 1030), windows: [],
                                              dockProcessID: 100, dockLayer: 20, ownProcessID: 999)
        #expect(!owns)
    }

    // MARK: - longAxisContains

    @Test("horizontal Dock matches by x, ignoring y drift")
    func horizontalMatchIgnoresY() {
        let itemFrame = CGRect(x: 100, y: 950, width: 60, height: 60)
        let point = CGPoint(x: 120, y: 1200) // far below the item's own y range
        #expect(DockGeometry.longAxisContains(point, itemFrame: itemFrame, horizontal: true))
    }

    @Test("horizontal Dock still rejects a point outside the item's x range")
    func horizontalMatchRejectsOutsideX() {
        let itemFrame = CGRect(x: 100, y: 950, width: 60, height: 60)
        let point = CGPoint(x: 500, y: 960)
        #expect(!DockGeometry.longAxisContains(point, itemFrame: itemFrame, horizontal: true))
    }

    @Test("vertical Dock matches by y, ignoring x drift")
    func verticalMatchIgnoresX() {
        let itemFrame = CGRect(x: 0, y: 300, width: 60, height: 60)
        let point = CGPoint(x: 400, y: 320) // far right of the item's own x range
        #expect(DockGeometry.longAxisContains(point, itemFrame: itemFrame, horizontal: false))
    }

    @Test("vertical Dock still rejects a point outside the item's y range")
    func verticalMatchRejectsOutsideY() {
        let itemFrame = CGRect(x: 0, y: 300, width: 60, height: 60)
        let point = CGPoint(x: 10, y: 900)
        #expect(!DockGeometry.longAxisContains(point, itemFrame: itemFrame, horizontal: false))
    }
}
