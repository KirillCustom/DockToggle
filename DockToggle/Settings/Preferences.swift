import Foundation
import ServiceManagement

nonisolated enum ToggleMode: String, CaseIterable, Identifiable, Sendable {
    case minimize
    case hide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimize: return "Minimize"
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

    func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item error: \(error)")
        }
    }
}
