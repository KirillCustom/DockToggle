import Cocoa
import ApplicationServices

nonisolated enum WindowToggler {

    static func toggle(app: NSRunningApplication, mode: ToggleMode = Preferences.shared.toggleMode) {
        guard app.isActive else {
            print("[WindowToggler] App not active, skipping")
            return
        }

        switch mode {
        case .minimize:
            toggleMinimize(app: app)
        case .hide:
            toggleHide(app: app)
        }
    }

    private static func toggleMinimize(app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement)

        print("[WindowToggler] App \(app.localizedName ?? "?") pid=\(app.processIdentifier) has \(windows.count) windows")

        for (i, window) in windows.enumerated() {
            let minimized = isMinimized(window)
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "untitled"
            print("[WindowToggler]   window[\(i)]: \"\(title)\" minimized=\(minimized)")
        }

        let visibleWindows = windows.filter { !isMinimized($0) }

        if visibleWindows.isEmpty {
            print("[WindowToggler] No visible windows, restoring minimized")
            restoreLastMinimized(windows: windows, app: app)
        } else {
            print("[WindowToggler] Minimizing \(visibleWindows.count) visible windows")
            for window in visibleWindows {
                let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                print("[WindowToggler]   minimize result: \(result.rawValue)")
            }
        }
    }

    private static func toggleHide(app: NSRunningApplication) {
        let result = app.hide()
        print("[WindowToggler] Hide result: \(result)")
    }

    private static func restoreLastMinimized(windows: [AXUIElement], app: NSRunningApplication) {
        let minimized = windows.filter { isMinimized($0) }
        print("[WindowToggler] Restoring \(minimized.count) minimized windows")

        for window in minimized {
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            print("[WindowToggler]   restore result: \(result.rawValue)")
        }

        app.activate()
    }

    private static func getWindows(_ appElement: AXUIElement) -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            print("[WindowToggler] Failed to get windows: \(result.rawValue)")
            return []
        }
        return windows.filter { isStandardWindow($0) }
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else {
            return false
        }
        return subrole == "AXStandardWindow" || subrole == "AXDialog"
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
              let isMin = minimizedRef as? Bool else {
            return false
        }
        return isMin
    }

    static func hasMinimizedWindows(app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement)
        return windows.contains { isMinimized($0) }
    }

    static func restoreAndActivate(app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement)
        let minimized = windows.filter { isMinimized($0) }
        print("[WindowToggler] Restoring \(minimized.count) minimized windows")
        for window in minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
        app.activate()
    }

    static func isFullscreen(app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement)

        for window in windows {
            var fullscreenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenRef) == .success,
               let isFS = fullscreenRef as? Bool, isFS {
                return true
            }
        }
        return false
    }
}
