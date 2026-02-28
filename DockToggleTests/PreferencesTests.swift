import Testing
import Foundation
@testable import DockToggle

@Suite("Preferences", .serialized)
struct PreferencesTests {
    private let prefs = Preferences.shared

    init() {
        // Clean slate for each test
        prefs.excludedBundleIds = []
    }

    // MARK: - Exclusion Management

    @Test("addExclusion adds bundle ID to list")
    func addExclusion() {
        prefs.addExclusion("com.apple.Safari")

        #expect(prefs.excludedBundleIds == ["com.apple.Safari"])
    }

    @Test("addExclusion does not duplicate existing bundle ID")
    func addExclusionNoDuplicate() {
        prefs.addExclusion("com.apple.Safari")
        prefs.addExclusion("com.apple.Safari")

        #expect(prefs.excludedBundleIds == ["com.apple.Safari"])
    }

    @Test("addExclusion supports multiple bundle IDs")
    func addMultipleExclusions() {
        prefs.addExclusion("com.apple.Safari")
        prefs.addExclusion("com.apple.finder")

        #expect(prefs.excludedBundleIds.count == 2)
        #expect(prefs.excludedBundleIds.contains("com.apple.Safari"))
        #expect(prefs.excludedBundleIds.contains("com.apple.finder"))
    }

    @Test("removeExclusion removes bundle ID from list")
    func removeExclusion() {
        prefs.addExclusion("com.apple.Safari")
        prefs.addExclusion("com.apple.finder")
        prefs.removeExclusion("com.apple.Safari")

        #expect(prefs.excludedBundleIds == ["com.apple.finder"])
    }

    @Test("removeExclusion is no-op for non-existent bundle ID")
    func removeNonExistent() {
        prefs.addExclusion("com.apple.Safari")
        prefs.removeExclusion("com.example.nonexistent")

        #expect(prefs.excludedBundleIds == ["com.apple.Safari"])
    }

    @Test("removeExclusion from empty list is no-op")
    func removeFromEmpty() {
        prefs.removeExclusion("com.apple.Safari")

        #expect(prefs.excludedBundleIds.isEmpty)
    }

    // MARK: - Toggle Mode

    @Test("toggleMode defaults to minimize")
    func toggleModeDefault() {
        UserDefaults.standard.removeObject(forKey: "toggleMode")

        #expect(prefs.toggleMode == .minimize)
    }

    @Test("toggleMode persists value")
    func toggleModePersistence() {
        prefs.toggleMode = .hide
        #expect(prefs.toggleMode == .hide)

        prefs.toggleMode = .minimize
        #expect(prefs.toggleMode == .minimize)
    }

    @Test("toggleMode handles invalid raw value gracefully")
    func toggleModeInvalidRaw() {
        UserDefaults.standard.set("invalid_mode", forKey: "toggleMode")

        #expect(prefs.toggleMode == .minimize)
    }

    // MARK: - isEnabled

    @Test("isEnabled persists value")
    func isEnabledPersistence() {
        prefs.isEnabled = false
        #expect(!prefs.isEnabled)

        prefs.isEnabled = true
        #expect(prefs.isEnabled)
    }
}

// MARK: - ToggleMode

@Suite("ToggleMode")
struct ToggleModeTests {
    @Test("all cases are minimize and hide")
    func allCases() {
        #expect(ToggleMode.allCases == [.minimize, .hide])
    }

    @Test("rawValue matches case name")
    func rawValues() {
        #expect(ToggleMode.minimize.rawValue == "minimize")
        #expect(ToggleMode.hide.rawValue == "hide")
    }

    @Test("id equals rawValue")
    func identifiable() {
        for mode in ToggleMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("label returns human-readable string")
    func labels() {
        #expect(ToggleMode.minimize.label == "Minimize")
        #expect(ToggleMode.hide.label == "Hide")
    }
}
