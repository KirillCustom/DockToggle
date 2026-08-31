import Foundation
import ServiceManagement

nonisolated enum ToggleMode: String, CaseIterable, Identifiable, Sendable {
    case minimize
    case minimizeActive
    case hide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimize: return "Minimize"
        case .minimizeActive: return "Minimize Active Window"
        case .hide: return "Hide"
        }
    }
}

nonisolated final class Preferences: Sendable {
    static let shared = Preferences()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isEnabled") }
    }

    var toggleMode: ToggleMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "toggleMode") ?? ToggleMode.minimize.rawValue
            return ToggleMode(rawValue: raw) ?? .minimize
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "toggleMode") }
    }

    var excludedBundleIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedBundleIds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "excludedBundleIds") }
    }

    /// When the frontmost app already has more than one visible window, a click cycles
    /// focus through them (like ⌘`) instead of running the selected toggle mode. Independent
    /// of `toggleMode`: it only pre-empts a click that would otherwise minimize or hide an
    /// app that still has other windows to show first.
    var cycleWindowsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "cycleWindowsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "cycleWindowsEnabled") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "isEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "isEnabled")
        }
    }

    func addExclusion(_ bundleId: String) {
        var current = excludedBundleIds
        guard !current.contains(bundleId) else { return }
        current.append(bundleId)
        excludedBundleIds = current
    }

    func removeExclusion(_ bundleId: String) {
        excludedBundleIds = excludedBundleIds.filter { $0 != bundleId }
    }

    /// The real state, straight from the system — the user can also flip this in
    /// System Settings, and our own copy in UserDefaults then lies about it.
    var isLoginItemRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var loginItemNeedsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Throws so the caller can show the failure instead of leaving a switch that claims
    /// the app will start at login when it will not.
    func updateLoginItem(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        UserDefaults.standard.set(isLoginItemRegistered, forKey: "launchAtLogin")
    }

    /// Brings the stored flag back in line with the system.
    func syncLoginItemFlag() {
        UserDefaults.standard.set(isLoginItemRegistered, forKey: "launchAtLogin")
    }
}
