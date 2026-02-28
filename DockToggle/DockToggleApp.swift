import SwiftUI
import Cocoa

@main
struct DockToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isEnabled") private var isEnabled = true

    var body: some Scene {
        MenuBarExtra("DockToggle", image: isEnabled ? "MenuBarIcon" : "MenuBarIconDisabled") {
            MenuBarMenu(appDelegate: appDelegate)
        }
    }
}

struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    @AppStorage("isEnabled") private var isEnabled = true

    var body: some View {
        Toggle("Enabled", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                if newValue {
                    appDelegate.startToggling()
                } else {
                    appDelegate.stopToggling()
                }
            }
        Divider()
        Button("Settings…") {
            appDelegate.openSettings()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, EventTapDelegate {
    private let dockWatcher = DockWatcher.shared
    private let eventTapManager = EventTapManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        eventTapManager.delegate = self

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompletedOnboarding {
            showOnboarding()
        } else {
            if !AccessibilityHelper.checkAccessibility() {
                AccessibilityHelper.requestAccessibility()
            }
            if Preferences.shared.isEnabled {
                startToggling()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopToggling()
    }

    func startToggling() {
        dockWatcher.start()
        eventTapManager.start()
    }

    func stopToggling() {
        eventTapManager.stop()
        dockWatcher.stop()
    }

    // MARK: - Windows

    private func showOnboarding() {
        let onboardingView = OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            if Preferences.shared.isEnabled {
                self?.startToggling()
            }
        }

        NSApp.setActivationPolicy(.regular)

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to DockToggle"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 500, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("Settings", comment: "")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 620, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow || window === onboardingWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - EventTapDelegate

    nonisolated func eventTapDidReceiveClick(at point: CGPoint) -> Bool {
        let items = DockWatcher.shared.dockItems
        let prefs = Preferences.shared

        guard prefs.isEnabled else { return false }

        for item in items {
            guard item.frame.contains(point) else { continue }

            print("[EventTap] Hit dock item: \"\(item.title)\" bundle=\(item.bundleIdentifier ?? "nil")")

            guard !AppMatcher.shouldExclude(item) else {
                print("[EventTap] Excluded, passing through")
                return false
            }

            guard let app = AppMatcher.findRunningApp(for: item) else {
                print("[EventTap] No running app found for \"\(item.title)\"")
                return false
            }

            print("[EventTap] App: \(app.localizedName ?? "?") active=\(app.isActive) hidden=\(app.isHidden)")

            if WindowToggler.isFullscreen(app: app) {
                print("[EventTap] Fullscreen, passing through")
                return false
            }

            if app.isActive {
                print("[EventTap] Toggling \(app.localizedName ?? "?")")
                WindowToggler.toggle(app: app)
                return true
            }

            // App not active — check if it has minimized windows to restore
            if WindowToggler.hasMinimizedWindows(app: app) {
                print("[EventTap] Restoring minimized windows for \(app.localizedName ?? "?")")
                WindowToggler.restoreAndActivate(app: app)
                return true
            }

            return false
        }

        return false
    }
}
