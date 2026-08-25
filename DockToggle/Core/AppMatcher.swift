import Cocoa

nonisolated enum AppMatcher {
    private static let excludedNames: Set<String> = ["Launchpad", "Trash", "Downloads"]

    static func findRunningApp(for item: DockItem) -> NSRunningApplication? {
        if shouldExclude(item) { return nil }

        // Targeted lookup first: this runs in the event tap callback, and building the full
        // list of running applications on every Dock click is what stalls it.
        if let bundleId = item.bundleIdentifier {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                return app
            }
        }

        if !item.title.isEmpty {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == item.title }) {
                return app
            }
        }

        return nil
    }

    static func shouldExclude(_ item: DockItem) -> Bool {
        if excludedNames.contains(item.title) { return true }

        if let subrole = item.subrole {
            if subrole == "AXSeparatorDockItem" || subrole == "AXTrashDockItem"
                || subrole == "AXStackDockItem" || subrole == "AXFolderDockItem" {
                return true
            }
        }

        if let bundleId = item.bundleIdentifier {
            if Preferences.shared.excludedBundleIds.contains(bundleId) { return true }
        }

        return false
    }
}
