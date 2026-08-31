import CoreGraphics

/// Pure geometry checks that gate a Dock click before any Accessibility call runs. Kept apart
/// from the AppKit/CoreGraphics calls that gather screen and window-list data so the matching
/// rules themselves are unit-testable.
nonisolated enum DockGeometry {

    /// One on-screen window, as reported by the window server — just enough to tell whether
    /// something is drawn over the Dock at a given point.
    struct OnScreenWindow: Sendable {
        let processID: pid_t
        let layer: Int
        let alpha: CGFloat
        let frame: CGRect
    }

    /// Cheap geometric gate that runs before any Accessibility hit-test, in the event's
    /// top-left-origin coordinates. When the Dock reserves screen space (`visibleFrame` is
    /// inset on the bottom, left or right), the click must land inside that reserved strip —
    /// this keeps clicks on windows or panels hovering just above the Dock out, which matters
    /// because the AX item matching that follows can only trust the Dock's long axis. Without
    /// a reserved strip (auto-hide, or the Dock lives on another display) it falls back to a
    /// generous edge band.
    static func stripContains(_ point: CGPoint,
                               screenFrame: CGRect,
                               visibleFrame: CGRect,
                               fallbackMargin: CGFloat = 120) -> Bool {
        // Small negative inset: the pointer clamps to the screen, but event coordinates on
        // the very edge can land fractionally outside.
        guard screenFrame.insetBy(dx: -8, dy: -8).contains(point) else { return false }

        let bottomGap = screenFrame.maxY - visibleFrame.maxY
        let leftGap = visibleFrame.minX - screenFrame.minX
        let rightGap = screenFrame.maxX - visibleFrame.maxX
        let reserved: CGFloat = 8

        if bottomGap > reserved || leftGap > reserved || rightGap > reserved {
            if bottomGap > reserved, point.y >= visibleFrame.maxY - 2 { return true }
            if leftGap > reserved, point.x <= visibleFrame.minX + 2 { return true }
            if rightGap > reserved, point.x >= visibleFrame.maxX - 2 { return true }
            return false
        }

        return point.y >= screenFrame.maxY - fallbackMargin
            || point.x <= screenFrame.minX + fallbackMargin
            || point.x >= screenFrame.maxX - fallbackMargin
    }

    /// Whether the Dock is the first visible window that could receive the click. Its layer
    /// can cover a whole display even when something else is drawn above it, so bounds alone
    /// are not ownership — a panel or window hovering over the Dock's reserved strip must
    /// keep its click.
    static func dockOwnsPoint(_ point: CGPoint,
                               windows: [OnScreenWindow],
                               dockProcessID: pid_t,
                               dockLayer: Int,
                               ownProcessID: pid_t) -> Bool {
        for window in windows where window.alpha > 0 {
            let isDockStrip = window.processID == dockProcessID && window.layer == dockLayer
            let contains = isDockStrip
                ? window.frame.insetBy(dx: -8, dy: -8).contains(point)
                : window.frame.contains(point)
            guard contains else { continue }
            if window.processID == ownProcessID { continue }
            return isDockStrip
        }
        return false
    }

    /// Whether a Dock icon's long axis — the only axis its AX frame reliably reports — spans
    /// the point. The Dock strip check already bounded the short axis, and trusting the AX
    /// frame there too has been observed to misfire: the Dock can report item frames shifted
    /// tens of points off the strip's actual position on that axis.
    static func longAxisContains(_ point: CGPoint, itemFrame: CGRect, horizontal: Bool) -> Bool {
        horizontal
            ? (point.x >= itemFrame.minX && point.x <= itemFrame.maxX)
            : (point.y >= itemFrame.minY && point.y <= itemFrame.maxY)
    }
}
