import Cocoa

/// Wires DockGeometry's pure checks to the actual screen and window-server state. Cheap
/// system calls only — window-list metadata, no pixel capture and no Accessibility IPC — so
/// this is safe to call from the event tap callback before anything AX-based runs.
///
/// The event tap runs on the main run loop, so — like the rest of the tap-adjacent code —
/// this assumes single-threaded access and keeps no locks of its own. Marked `nonisolated`
/// so it can still be called from the tap callback's `nonisolated` delegate methods, even
/// though the project defaults new declarations to `@MainActor`.
nonisolated enum DockScreenGate {
    private static var dockPIDCache: pid_t?

    /// Whether the point falls inside the strip of screen the Dock could plausibly own, on
    /// any connected display.
    static func containsDockStrip(_ point: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return false }
        for screen in NSScreen.screens {
            let frame = topLeftRect(screen.frame, primaryHeight: primaryHeight)
            let visible = topLeftRect(screen.visibleFrame, primaryHeight: primaryHeight)
            if DockGeometry.stripContains(point, screenFrame: frame, visibleFrame: visible) {
                return true
            }
        }
        return false
    }

    /// Whether the Dock is actually the topmost window at the point — guards against a
    /// window or panel hovering just above the Dock's reserved strip.
    static func dockOwnsPoint(_ point: CGPoint) -> Bool {
        guard let dockPID = dockProcessID() else { return false }
        let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
        return DockGeometry.dockOwnsPoint(point, windows: onScreenWindows(), dockProcessID: dockPID,
                                          dockLayer: dockLayer, ownProcessID: getpid())
    }

    /// AppKit's screen frames grow up from the bottom-left; CGEvent locations grow down from
    /// the top-left. Everything downstream expects the latter.
    private static func topLeftRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func onScreenWindows() -> [DockGeometry.OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? CGFloat ?? 1
            return DockGeometry.OnScreenWindow(processID: pid, layer: layer, alpha: alpha, frame: frame)
        }
    }

    private static func dockProcessID() -> pid_t? {
        if let dockPIDCache, NSRunningApplication(processIdentifier: dockPIDCache)?.isTerminated == false {
            return dockPIDCache
        }
        let pid = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
        dockPIDCache = pid
        return pid
    }
}
