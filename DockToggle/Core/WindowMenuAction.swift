import ApplicationServices

/// Presses an app's own "Minimize All" (⌥⌘M) menu item so multi-window apps animate their
/// minimize as one batch instead of window-by-window. Falls back to the plain Minimize
/// (⌘M) item for apps that only bind that one (some Java and Eclipse-based apps have no
/// standard Window menu). AX-only — the caller decides what to do if neither exists.
nonisolated enum WindowMenuAction {
    enum Outcome {
        /// A menu action ran; the app is animating its own batch.
        case performed
        /// The only matching item was disabled, or its shortcut conflicts with another item —
        /// do not synthesize it, only a direct per-window set may proceed.
        case unsafe
        /// No usable menu item was found.
        case unavailable
    }

    /// Scans the app's menu bar two levels deep for the Minimize All / plain Minimize items —
    /// the item lives directly in the Window menu, so submenus are never entered. Matching by
    /// command character + modifiers instead of the localized title works in every language
    /// the target app ships.
    ///
    /// This is AX IPC against an app that may be busy or hung; callers should run it off the
    /// main queue and expect it to occasionally take close to a second.
    static func pressMinimizeAll(pid: pid_t) -> Outcome {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let menuBar = elementAttribute(app, kAXMenuBarAttribute as String),
              let topLevel = elementArray(menuBar, kAXChildrenAttribute as String)
        else { return .unavailable }

        var plainMinimize: AXUIElement?
        var minimizeAll: AXUIElement?
        var hasConflictingOptionM = false

        // The Window menu sits near the end of the menu bar.
        for barItem in topLevel.reversed() {
            guard let menus = elementArray(barItem, kAXChildrenAttribute as String) else { continue }
            for menu in menus {
                guard let items = elementArray(menu, kAXChildrenAttribute as String) else { continue }
                for item in items {
                    let commandCharacter = stringAttribute(item, "AXMenuItemCmdChar")
                    let modifiers = intAttribute(item, "AXMenuItemCmdModifiers")

                    if minimizeAll == nil, MinimizeMenuMatch.isVerifiedMinimizeAll(
                        commandCharacter: commandCharacter, modifiers: modifiers,
                        identifier: stringAttribute(item, kAXIdentifierAttribute as String)
                    ) {
                        minimizeAll = item
                    } else if commandCharacter?.uppercased() == "M", modifiers == 2 {
                        hasConflictingOptionM = true
                    }

                    if plainMinimize == nil, MinimizeMenuMatch.isPlainMinimize(
                        commandCharacter: commandCharacter, modifiers: modifiers
                    ) {
                        plainMinimize = item
                    }
                }
            }
        }

        if let minimizeAll {
            guard boolAttribute(minimizeAll, kAXEnabledAttribute as String) != false else { return .unsafe }
            if AXUIElementPerformAction(minimizeAll, kAXPressAction as CFString) == .success { return .performed }
        }
        if let plainMinimize, boolAttribute(plainMinimize, kAXEnabledAttribute as String) != false {
            if AXUIElementPerformAction(plainMinimize, kAXPressAction as CFString) == .success { return .performed }
        }
        return hasConflictingOptionM ? .unsafe : .unavailable
    }

    // MARK: - AX helpers

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return nil }
        return array
    }

    static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
