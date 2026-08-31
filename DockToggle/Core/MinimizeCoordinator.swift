import Cocoa
// AXUIElement/CFBoolean are safe to hand across queues by design — the AX API is meant to be
// called from any thread — but neither module has picked up Sendable annotations yet.
@preconcurrency import ApplicationServices
@preconcurrency import CoreFoundation

/// Owns the parts of minimize/restore that outlive a single click: the settling sweep that
/// catches windows an app's own batch animation left behind, and the front-to-back order
/// captured before minimizing so a later restore can bring the previously-frontmost window
/// back on top instead of wherever AX happens to leave it.
///
/// Confined to the main queue, like the rest of the event-tap-adjacent state in this app.
/// `dispatchPrecondition` documents that rather than a lock enforcing it, matching
/// `DockWatcher.start()/stop()`. The actual Accessibility work each method kicks off still
/// runs on a background queue — some of these calls (menu walks, per-window read-back
/// retries) can take the better part of a second against a busy app, and that must never
/// block the main thread.
///
/// Marked `nonisolated` — like `DockWatcher` — so it can be called from `WindowToggler`'s
/// `nonisolated` static functions; `dispatchPrecondition` is what actually enforces the
/// main-queue assumption, not the type checker.
nonisolated final class MinimizeCoordinator: @unchecked Sendable {
    static let shared = MinimizeCoordinator()

    /// Each app's on-screen windows, front-to-back, captured the instant before this feature
    /// minimizes them. A restore cannot recover this later — minimized windows are off
    /// screen and carry no z-order.
    private var zOrder: [pid_t: [CGWindowID]] = [:]
    private var pendingSweeps: [pid_t: DispatchWorkItem] = [:]

    private static let minimizeSweepDelay: TimeInterval = 0.9
    private static let minimizeMenuVerifyDelay: TimeInterval = 0.35
    private static let restoreSweepDelay: TimeInterval = 0.6

    private init() {}

    /// Drops all in-flight sweeps and captured ordering. Called when the tap stops — a stale
    /// sweep firing on its own timer after that would just be wasted work.
    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        for (_, sweep) in pendingSweeps { sweep.cancel() }
        pendingSweeps = [:]
        zOrder = [:]
    }

    /// Minimizes a batch of windows, preferring the app's own Minimize All menu item so
    /// multiple windows animate together instead of one at a time. `windows` must already be
    /// confirmed visible — this does not re-check.
    func minimizeAll(pid: pid_t, windows: [AXUIElement]) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelSweep(pid: pid)

        // Captured now, synchronously, while the windows are still up — this is the last
        // moment their stacking exists anywhere.
        zOrder[pid] = OnScreenWindows.ids(forPID: pid)
        pruneZOrderIfNeeded()

        guard windows.count > 1 else {
            // A single window doesn't need the app's own batch action.
            DispatchQueue.global(qos: .userInteractive).async {
                Self.setMinimized(true, windows: windows)
            }
            return
        }

        DispatchQueue.global(qos: .userInteractive).async {
            switch WindowMenuAction.pressMinimizeAll(pid: pid) {
            case .performed:
                // The menu action's own animation needs a moment; anything it silently left
                // up (an untruthful or plain-Minimize action) gets the per-window set after.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.minimizeMenuVerifyDelay) {
                    DispatchQueue.global(qos: .userInteractive).async {
                        for window in windows where Self.isMinimized(window) != true {
                            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                        }
                    }
                }
            case .unsafe, .unavailable:
                Self.setMinimized(true, windows: windows)
            }
        }

        scheduleSweep(pid: pid, targets: windows, minimized: true, delay: Self.minimizeSweepDelay)
    }

    /// Restores a batch of previously-minimized windows, rearmost first, so the window that
    /// was frontmost when they went down animates in over the others last and lands on top
    /// by itself. `windows` must already be confirmed minimized.
    func restore(pid: pid_t, windows: [AXUIElement], app: NSRunningApplication) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelSweep(pid: pid)
        let frontToBack = zOrder.removeValue(forKey: pid) ?? []

        guard !windows.isEmpty else {
            app.activate()
            return
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.35)
            let ids = windows.map(AXWindowResolver.windowID(for:))
            // Without a captured order (the app was minimized by other means) the app's own
            // main window is the best guess at where the user left off.
            let preferredFront = frontToBack.isEmpty
                ? WindowMenuAction.elementAttribute(axApp, kAXMainWindowAttribute as String)
                    .flatMap(AXWindowResolver.windowID(for:))
                : nil
            let sequence = RestoreSequence.order(ids: ids, frontToBack: frontToBack, preferredFront: preferredFront)
            let ordered = sequence.map { windows[$0] }

            guard let frontSlot = sequence.last else {
                DispatchQueue.main.async { app.activate() }
                return
            }
            let front = windows[frontSlot]
            // Which window belongs on top, when it can be named: the frontmost captured
            // window still in this batch, else the app's own main one. With neither, the
            // batch order is a guess, and forcing focus onto a guess is worse than leaving
            // it to activation.
            let knownFront = frontToBack.first { id in ids.contains { $0 == id } } ?? preferredFront
            let pinnedFront: AXUIElement? = knownFront != nil && ids[frontSlot] == knownFront ? front : nil

            for window in ordered.dropLast() {
                Self.restoreOne(window)
            }
            DispatchQueue.main.async { app.activate() }
            Self.restoreOne(front)
            if let pinnedFront {
                AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, pinnedFront)
                AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, pinnedFront)
            }

            DispatchQueue.main.async {
                self?.scheduleSweep(pid: pid, targets: ordered, minimized: false,
                                    delay: Self.restoreSweepDelay, refocus: pinnedFront)
            }
        }
    }

    // MARK: - Settling sweep

    /// Re-asserts the action once the animation settles: windows the batched Minimize All
    /// left behind get minimized individually, and a restore that clicked in while minimizes
    /// were still in flight re-opens the stragglers. Only the windows captured at click time
    /// are swept, and each new action for the app cancels the previous sweep so exactly one
    /// direction wins.
    private func scheduleSweep(pid: pid_t, targets: [AXUIElement], minimized: Bool,
                               delay: TimeInterval, refocus: AXUIElement? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelSweep(pid: pid)
        let appIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSweeps.removeValue(forKey: pid)
            let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
            DispatchQueue.global(qos: .userInteractive).async {
                var sweptRestoreStraggler = false
                for window in targets where Self.isMinimized(window) != minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
                    sweptRestoreStraggler = !minimized
                }
                // A straggler the sweep re-opened animates in on top of the window the
                // restore pinned focus to, splitting stacking and focus again — re-pin, but
                // only while the app is still frontmost, so a user who moved elsewhere
                // during the settle delay is never yanked back.
                guard sweptRestoreStraggler, appIsFrontmost,
                      let front = refocus, Self.isMinimized(front) == false else { return }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.35)
                AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, front)
                AXUIElementPerformAction(front, kAXRaiseAction as CFString)
            }
        }
        pendingSweeps[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSweep(pid: pid_t) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingSweeps.removeValue(forKey: pid)?.cancel()
    }

    /// Bounds the map: entries normally leave when their restore consumes them; this clears
    /// ones left behind by windows minimized from the Dock and restored some other way.
    private func pruneZOrderIfNeeded() {
        guard zOrder.count > 32 else { return }
        zOrder = zOrder.filter { NSRunningApplication(processIdentifier: $0.key) != nil }
    }

    // MARK: - Window state

    private static func setMinimized(_ minimized: Bool, windows: [AXUIElement]) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        for window in windows {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
        }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    /// Unminimizes one window and confirms it took, retrying once. Blocking on the read keeps
    /// the batch in step: the next window must not start its animation until this one has
    /// actually begun its own.
    private static func restoreOne(_ window: AXUIElement) {
        guard isMinimized(window) != false else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard isMinimized(window) == true else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
}
