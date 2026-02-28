import Testing
import Foundation
import Cocoa
@testable import DockToggle

@Suite("AppMatcher.shouldExclude", .serialized)
struct AppMatcherExcludeTests {
    init() {
        Preferences.shared.excludedBundleIds = []
    }

    // MARK: - Excluded Names

    @Test("excludes Launchpad by name")
    func excludeLaunchpad() {
        let item = DockItem(frame: .zero, title: "Launchpad", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(AppMatcher.shouldExclude(item))
    }

    @Test("excludes Trash by name")
    func excludeTrash() {
        let item = DockItem(frame: .zero, title: "Trash", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(AppMatcher.shouldExclude(item))
    }

    @Test("excludes Downloads by name")
    func excludeDownloads() {
        let item = DockItem(frame: .zero, title: "Downloads", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(AppMatcher.shouldExclude(item))
    }

    @Test("does not exclude regular app by name")
    func doesNotExcludeRegularApp() {
        let item = DockItem(frame: .zero, title: "Safari", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(!AppMatcher.shouldExclude(item))
    }

    // MARK: - Excluded Subroles

    @Test(
        "excludes items by subrole",
        arguments: ["AXSeparatorDockItem", "AXTrashDockItem", "AXStackDockItem", "AXFolderDockItem"]
    )
    func excludeBySubrole(subrole: String) {
        let item = DockItem(frame: .zero, title: "Something", bundleIdentifier: nil, url: nil, subrole: subrole)
        #expect(AppMatcher.shouldExclude(item))
    }

    @Test("does not exclude regular subrole")
    func doesNotExcludeRegularSubrole() {
        let item = DockItem(frame: .zero, title: "Safari", bundleIdentifier: nil, url: nil, subrole: "AXApplicationDockItem")
        #expect(!AppMatcher.shouldExclude(item))
    }

    @Test("handles nil subrole")
    func nilSubrole() {
        let item = DockItem(frame: .zero, title: "Safari", bundleIdentifier: "com.apple.Safari", url: nil, subrole: nil)
        #expect(!AppMatcher.shouldExclude(item))
    }

    // MARK: - Preferences Exclusions

    @Test("excludes app by bundle ID from preferences")
    func excludeByPreferences() {
        Preferences.shared.addExclusion("com.apple.Safari")
        let item = DockItem(frame: .zero, title: "Safari", bundleIdentifier: "com.apple.Safari", url: nil, subrole: nil)

        #expect(AppMatcher.shouldExclude(item))
    }

    @Test("does not exclude app not in preferences")
    func doesNotExcludeIfNotInPreferences() {
        Preferences.shared.addExclusion("com.apple.Safari")
        let item = DockItem(frame: .zero, title: "Finder", bundleIdentifier: "com.apple.finder", url: nil, subrole: nil)

        #expect(!AppMatcher.shouldExclude(item))
    }

    @Test("handles nil bundle ID with preferences exclusions")
    func nilBundleIdWithPreferences() {
        Preferences.shared.addExclusion("com.apple.Safari")
        let item = DockItem(frame: .zero, title: "SomeApp", bundleIdentifier: nil, url: nil, subrole: nil)

        #expect(!AppMatcher.shouldExclude(item))
    }

    // MARK: - Edge Cases

    @Test("empty title is not excluded")
    func emptyTitle() {
        let item = DockItem(frame: .zero, title: "", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(!AppMatcher.shouldExclude(item))
    }

    @Test("exclusion name check is case-sensitive")
    func caseSensitive() {
        let item = DockItem(frame: .zero, title: "launchpad", bundleIdentifier: nil, url: nil, subrole: nil)
        #expect(!AppMatcher.shouldExclude(item))
    }
}
