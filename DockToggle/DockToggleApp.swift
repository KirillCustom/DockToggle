import SwiftUI
import Cocoa
import Sparkle

@main
struct DockToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isEnabled") private var isEnabled = true
    @AppStorage("accessibilityGranted") private var accessibilityGranted = false

    private var isActive: Bool {
        isEnabled && accessibilityGranted
    }

    var body: some Scene {
        MenuBarExtra("DockToggle", image: isActive ? "MenuBarIcon" : "MenuBarIconDisabled") {
            MenuBarMenu(appDelegate: appDelegate)
        }
    }
}

struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    @AppStorage("isEnabled") private var isEnabled = true
    @AppStorage("accessibilityGranted") private var accessibilityGranted = false

    var body: some View {
        if !accessibilityGranted {
            Button("Grant Accessibility Access") {
                AccessibilityHelper.requestAccessibility()
            }
            Divider()
        }
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
        Button("Check for Updates…") {
            appDelegate.updaterController.checkForUpdates(nil)
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
    let updaterController: SPUStandardUpdaterController
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var accessibilityTimer: Timer?

    override init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        eventTapManager.delegate = self
        updateAccessibilityStatus()
        startAccessibilityMonitor()

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompletedOnboarding {
            showOnboarding()
        } else {
            if !AccessibilityHelper.checkAccessibility() {
                showAccessibilityLostAlert()
            }
            if Preferences.shared.isEnabled {
                startToggling()
            }
        }
    }

    private func updateAccessibilityStatus() {
        UserDefaults.standard.set(AccessibilityHelper.checkAccessibility(), forKey: "accessibilityGranted")
    }

    private func startAccessibilityMonitor() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateAccessibilityStatus()
        }
    }

    private func showAccessibilityLostAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Accessibility Permission Required", comment: "")
        alert.informativeText = NSLocalizedString("DockToggle needs Accessibility access to work. After an update, macOS may require you to re-grant this permission.\n\nPlease remove the old DockToggle entry from System Settings → Privacy & Security → Accessibility, then add the new one.", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Open Settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityHelper.openAccessibilitySettings()
        }

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If settings or onboarding window is open, just close it instead of quitting
        if let window = settingsWindow, window.isVisible {
            window.close()
            return .terminateCancel
        }
        if let window = onboardingWindow, window.isVisible {
            window.close()
            return .terminateCancel
        }
        return .terminateNow
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

        let hostingController = NSHostingController(rootView: SettingsView(updater: updaterController.updater))
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

    /// Fast check — only rect matching and process lookup, no AX IPC.
    /// Runs inside the event tap callback and must return quickly.
    nonisolated func eventTapResolveClick(at point: CGPoint) -> ClickTarget? {
        let items = DockWatcher.shared.dockItems
        guard Preferences.shared.isEnabled else { return nil }

        for item in items {
            guard item.frame.contains(point) else { continue }
            guard !AppMatcher.shouldExclude(item) else { return nil }
            guard let app = AppMatcher.findRunningApp(for: item) else { return nil }
            guard app.isActive else { return nil }
            return ClickTarget(item: item, app: app)
        }

        return nil
    }

    /// Heavy work — AXUIElement IPC calls. Runs async on main queue, outside the event tap callback.
    nonisolated func eventTapHandleClick(target: ClickTarget) {
        let app = target.app
        let item = target.item

        print("[EventTap] Hit dock item: \"\(item.title)\" bundle=\(item.bundleIdentifier ?? "nil")")
        print("[EventTap] App: \(app.localizedName ?? "?") active=\(app.isActive) hidden=\(app.isHidden)")

        if WindowToggler.isFullscreen(app: app) {
            print("[EventTap] Fullscreen, skipping")
            return
        }

        if app.isActive {
            print("[EventTap] Toggling \(app.localizedName ?? "?")")
            WindowToggler.toggle(app: app)
            return
        }

        if WindowToggler.hasMinimizedWindows(app: app) {
            print("[EventTap] Restoring minimized windows for \(app.localizedName ?? "?")")
            WindowToggler.restoreAndActivate(app: app)
            return
        }
    }
}
