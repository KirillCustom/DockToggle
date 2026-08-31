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
    private var defaultsObserver: NSObjectProtocol?
    private var isTogglingRequested = false

    override init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        eventTapManager.delegate = self
        updateAccessibilityStatus()
        startAccessibilityMonitor()
        observeEnabledFlag()

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

    /// Follows the master switch wherever it is flipped. The menu bar item exists only
    /// while the menu is open, so its onChange cannot be the only place this happens —
    /// the switch in Settings writes the same key and nothing else.
    private func observeEnabledFlag() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.syncTogglingState()
        }
    }

    private func syncTogglingState() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        let shouldRun = Preferences.shared.isEnabled
        guard shouldRun != isTogglingRequested else { return }

        if shouldRun {
            startToggling()
        } else {
            stopToggling()
        }
    }

    private func updateAccessibilityStatus() {
        let granted = AccessibilityHelper.checkAccessibility()
        guard granted != UserDefaults.standard.bool(forKey: "accessibilityGranted") else { return }
        UserDefaults.standard.set(granted, forKey: "accessibilityGranted")
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
        NSApp.activate()

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityHelper.openAccessibilitySettings()
        }

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q with a window in front means "close the window". Everything else — the Quit
        // menu item, logout, restart, shutdown — must go through, or macOS reports that
        // DockToggle refused to quit.
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return .terminateNow }

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
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        accessibilityTimer?.invalidate()
        stopToggling()
    }

    func startToggling() {
        isTogglingRequested = true
        dockWatcher.start()
        eventTapManager.start()
    }

    func stopToggling() {
        isTogglingRequested = false
        eventTapManager.stop()
        dockWatcher.stop()
        MinimizeCoordinator.shared.reset()
    }

    // MARK: - Windows

    private func showOnboarding() {
        let onboardingView = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
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
        NSApp.activate()
        onboardingWindow = window
    }

    /// Runs whether the wizard was finished or just closed with the red button — otherwise
    /// the app sits in the menu bar doing nothing and reopens the wizard on every launch.
    private func finishOnboarding() {
        guard !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        if Preferences.shared.isEnabled {
            startToggling()
        }
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()
        settingsWindow = window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let isOnboarding = window === onboardingWindow
        guard isOnboarding || window === settingsWindow else { return }

        if isOnboarding {
            finishOnboarding()
            onboardingWindow = nil
        }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - EventTapDelegate

    /// Fast check — no Accessibility IPC, only cheap system calls and a cached list. Runs
    /// inside the event tap callback and must return quickly.
    ///
    /// The window-server gates run first: they reject the vast majority of clicks (anywhere
    /// not near the Dock) before touching the cached item list, and they catch the case a
    /// frame check alone would miss — a window or panel drawn over the Dock's strip.
    nonisolated func eventTapResolveClick(at point: CGPoint) -> ClickTarget? {
        guard Preferences.shared.isEnabled,
              DockScreenGate.containsDockStrip(point),
              DockScreenGate.dockOwnsPoint(point) else { return nil }

        let horizontal = DockWatcher.shared.orientation == .horizontal
        for item in DockWatcher.shared.dockItems
        where DockGeometry.longAxisContains(point, itemFrame: item.frame, horizontal: horizontal) {
            return clickTarget(for: item)
        }

        return nil
    }

    /// Precise check against the live Dock — the cached frames are wrong while the Dock
    /// magnifies or rearranges. AX IPC, so it runs on the main queue, not in the callback.
    nonisolated func eventTapRefineClick(at point: CGPoint) -> ClickTarget? {
        guard Preferences.shared.isEnabled, let item = DockWatcher.itemAt(point: point) else { return nil }
        return clickTarget(for: item)
    }

    private nonisolated func clickTarget(for item: DockItem) -> ClickTarget? {
        guard let app = AppMatcher.findRunningApp(for: item), app.isActive else { return nil }
        return ClickTarget(item: item, app: app)
    }

    /// Heavy work — AXUIElement IPC calls. Runs on the main queue, outside the event tap
    /// callback. Returns false when we leave the click alone, so the tap can replay it for
    /// the Dock instead of swallowing it.
    nonisolated func eventTapHandleClick(target: ClickTarget) -> Bool {
        let app = target.app

        #if DEBUG
        print("[EventTap] Hit dock item: \"\(target.item.title)\" bundle=\(target.item.bundleIdentifier ?? "nil")")
        print("[EventTap] App: \(app.localizedName ?? "?") active=\(app.isActive) hidden=\(app.isHidden)")
        #endif

        guard app.isActive else { return false }

        if WindowToggler.isFullscreen(app: app) {
            #if DEBUG
            print("[EventTap] Fullscreen, leaving the click to the Dock")
            #endif
            return false
        }

        guard !DockClickDebounce.shared.shouldSwallow(pid: app.processIdentifier) else {
            #if DEBUG
            print("[EventTap] Within the double-click gap, swallowing without toggling again")
            #endif
            return true
        }

        #if DEBUG
        print("[EventTap] Toggling \(app.localizedName ?? "?")")
        #endif
        return WindowToggler.toggle(app: app)
    }
}
