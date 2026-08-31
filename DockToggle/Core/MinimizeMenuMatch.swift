/// Pure matching rules for identifying an app's "Minimize All" / plain "Minimize" menu items
/// by their keyboard shortcut, kept apart from the Accessibility calls that walk the menu bar
/// so the matching itself is unit-testable.
nonisolated enum MinimizeMenuMatch {
    /// The Option-Command-M chord is not unique to Minimize All — some apps bind it to
    /// something else entirely. Only the standard menu action identifier proves that
    /// pressing it is safe.
    static func isVerifiedMinimizeAll(commandCharacter: String?,
                                      modifiers: Int?,
                                      identifier: String?) -> Bool {
        commandCharacter?.uppercased() == "M"
            && modifiers == 2 // AXMenuItemCmdModifiers: Option, in addition to the implied Command
            && identifier == "miniaturizeAll:"
    }

    /// Plain Minimize (⌘M) — apps without a Minimize All (some Java and Eclipse-based apps)
    /// still usually have this, minimizing one window per click instead of a whole batch.
    static func isPlainMinimize(commandCharacter: String?, modifiers: Int?) -> Bool {
        commandCharacter?.uppercased() == "M" && modifiers == 0
    }
}
