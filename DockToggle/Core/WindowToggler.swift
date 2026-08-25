import Cocoa
import ApplicationServices

nonisolated enum WindowToggler {

    /// Returns false when there was nothing to minimize or restore — the caller then lets
    /// the Dock handle the click, so a click on an app without windows still reopens one.
    @discardableResult
    static func toggle(app: NSRunningApplication, mode: ToggleMode = Preferences.shared.toggleMode) -> Bool {
        guard app.isActive else {
            #if DEBUG
            print("[WindowToggler] App not active, skipping")
            #endif
            return false
        }

        switch mode {
        case .minimize:
            return toggleMinimize(app: app)
        case .minimizeActive:
            return toggleMinimizeActive(app: app)
        case .hide:
            return toggleHide(app: app)
        }
    }

    private static func toggleMinimize(app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getWindows(appElement)

        #if DEBUG
        print("[WindowToggler] App \(app.localizedName ?? "?") pid=\(app.processIdentifier) has \(windows.count) windows")
        for (i, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "untitled"
            print("[WindowToggler]   window[\(i)]: \"\(title)\" minimized=\(isMinimized(window))")
        }
        #endif

        let visibleWindows = windows.filter { !isMinimized($0) }

        guard !visibleWindows.isEmpty else {
            #if DEBUG
            print("[WindowToggler] No visible windows, restoring minimized")
            #endif
            return restoreLastMinimized(windows: windows, app: app)
        }

        #if DEBUG
        print("[WindowToggler] Minimizing \(visibleWindows.count) visible windows")
        #endif
        for window in visibleWindows {
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            #if DEBUG
            print("[WindowToggler]   minimize result: \(result.rawValue)")
            #endif
        }
        return true
    }

    private static func toggleMinimizeActive(app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let window = focusedWindow(of: appElement) else {
            #if DEBUG
            print("[WindowToggler] No focused window, restoring minimized")
            #endif
            return restoreLastMinimized(windows: getWindows(appElement), app: app)
        }

        guard !isMinimized(window), isStandardWindow(window) else {
            #if DEBUG
            print("[WindowToggler] Focused window already minimized or non-standard, restoring")
            #endif
            return restoreLastMinimized(windows: getWindows(appElement), app: app)
        }

        #if DEBUG
        print("[WindowToggler] Minimizing focused window")
        #endif
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        return true
    }

    private static func toggleHide(app: NSRunningApplication) -> Bool {
        let result = app.hide()
        #if DEBUG
        print("[WindowToggler] Hide result: \(result)")
        #endif
        return result
    }

    private static func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (focusedRef as! AXUIElement)
    }

    private static func restoreLastMinimized(windows: [AXUIElement], app: NSRunningApplication) -> Bool {
        let minimized = windows.filter { isMinimized($0) }
        #if DEBUG
        print("[WindowToggler] Restoring \(minimized.count) minimized windows")
        #endif

        guard !minimized.isEmpty else { return false }

        for window in minimized {
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            #if DEBUG
            print("[WindowToggler]   restore result: \(result.rawValue)")
            #endif
        }

        app.activate()
        return true
    }

    private static func getWindows(_ appElement: AXUIElement) -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            #if DEBUG
            print("[WindowToggler] Failed to get windows: \(result.rawValue)")
            #endif
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
