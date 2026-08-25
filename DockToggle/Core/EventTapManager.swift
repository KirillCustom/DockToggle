import Cocoa
import CoreGraphics

struct ClickTarget: Sendable {
    let item: DockItem
    let app: NSRunningApplication
}

protocol EventTapDelegate: AnyObject, Sendable {
    /// Fast, cache-based hit test. Runs inside the tap callback and must return quickly.
    nonisolated func eventTapResolveClick(at point: CGPoint) -> ClickTarget?
    /// Precise hit test via the Accessibility API. Runs on the main queue while the press is held.
    nonisolated func eventTapRefineClick(at point: CGPoint) -> ClickTarget?
    /// Returns false if nothing was done — the tap then replays the click for the Dock.
    nonisolated func eventTapHandleClick(target: ClickTarget) -> Bool
}

final class EventTapManager {
    weak var delegate: EventTapDelegate?

    /// Stamped on events we post ourselves so the tap recognizes them and lets them through.
    private static let syntheticMarker: Int64 = 0x444F_434B // "DOCK"

    /// Modifier clicks are the Dock's own gestures (context menu, reveal in Finder, hide others).
    private static let passThroughModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private var gate = DockPressGate()
    private var pendingTarget: ClickTarget?
    private var pendingEvent: CGEvent?
    private var holdTimer: Timer?

    deinit {
        // The tap callback dereferences an unretained pointer to self, so the port must not
        // outlive this object even if stop() was never called.
        teardownTap()
        retryTimer?.invalidate()
        holdTimer?.invalidate()
    }

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            #if DEBUG
            print("[EventTapManager] Failed to create event tap. Will retry when permissions are granted.")
            #endif
            startRetrying()
            return
        }

        stopRetrying()
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        #if DEBUG
        print("[EventTapManager] Event tap started")
        #endif
    }

    func stop() {
        stopRetrying()
        clearPendingPress()
        teardownTap()
        #if DEBUG
        print("[EventTapManager] Event tap stopped")
        #endif
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func startRetrying() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.eventTap == nil else { return }
            if AccessibilityHelper.checkAccessibility() {
                #if DEBUG
                print("[EventTapManager] Accessibility granted, retrying...")
                #endif
                self.start()
            }
        }
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    var isRunning: Bool {
        eventTap != nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            clearPendingPress()
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Events we posted ourselves — never intercept them a second time.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            guard gate.move(to: event.location) == .handOff else {
                return Unmanaged.passUnretained(event)
            }
            handOffToDock()
            // Swallow this one drag: the Dock must see the re-posted mouse-down first,
            // and an unpaired drag can be dropped by its tracking loop.
            return nil
        case .leftMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Holds the mouse-down back instead of acting on it: at this point a press is still
    /// indistinguishable from the start of a drag. The decision is made on mouse-up
    /// (click → toggle), on movement, or when the hold timer fires (both → the Dock).
    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        clearPendingPress()

        guard event.flags.intersection(Self.passThroughModifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let point = event.location

        guard let delegate = delegate,
              let target = delegate.eventTapResolveClick(at: point),
              let copy = event.copy() else {
            return Unmanaged.passUnretained(event)
        }

        pendingTarget = target
        pendingEvent = copy
        _ = gate.press(at: point)
        startHoldTimer()

        // The cached Dock frames go stale whenever the Dock magnifies or rearranges, so
        // confirm the target against the live Dock — off the tap callback, while we hold
        // the press.
        DispatchQueue.main.async { [weak self] in
            self?.refinePendingTarget(at: point)
        }

        return nil
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard gate.release() == .toggle,
              let target = pendingTarget,
              let downEvent = pendingEvent else {
            return Unmanaged.passUnretained(event)
        }
        clearPendingPress()

        DispatchQueue.main.async { [weak self, weak delegate] in
            let handled = delegate?.eventTapHandleClick(target: target) ?? false
            // We decided not to act, and the Dock never saw the click — give it back,
            // otherwise the click disappears entirely.
            if !handled {
                self?.replayClickForDock(downEvent)
            }
        }

        // The Dock never saw the matching mouse-down, so it must not see this either.
        return nil
    }

    /// Replaces the cached target with what the Accessibility API reports under the pointer.
    /// If the live Dock disagrees (different item, excluded, not our case), the press goes back.
    private func refinePendingTarget(at point: CGPoint) {
        guard pendingTarget != nil, let delegate = delegate else { return }

        guard let refined = delegate.eventTapRefineClick(at: point) else {
            #if DEBUG
            print("[EventTapManager] Live Dock disagrees with the cache, handing the press back")
            #endif
            handOffToDock()
            return
        }

        pendingTarget = refined
    }

    private func startHoldTimer() {
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: gate.holdTimeout, repeats: false) { [weak self] _ in
            guard let self, self.gate.expire() == .handOff else { return }
            self.handOffToDock()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    /// Re-posts the swallowed mouse-down so the Dock can run its own drag and press-and-hold
    /// handling. A single drag event can jump well past the threshold, so the press is put
    /// back inside the icon it started on — otherwise the Dock would grab the wrong one.
    private func handOffToDock() {
        guard let event = pendingEvent else {
            clearPendingPress()
            return
        }
        if let frame = pendingTarget?.item.frame, let current = CGEvent(source: nil)?.location {
            event.location = DockPressGate.clamp(current, to: frame)
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
        #if DEBUG
        print("[EventTapManager] Handed press back to the Dock")
        #endif
        clearPendingPress()
    }

    /// Synthesizes the click we swallowed so the Dock performs its default action.
    private func replayClickForDock(_ downEvent: CGEvent) {
        guard let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: downEvent.location,
            mouseButton: .left
        ) else { return }

        upEvent.setIntegerValueField(
            .mouseEventClickState,
            value: downEvent.getIntegerValueField(.mouseEventClickState)
        )
        downEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        upEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)

        #if DEBUG
        print("[EventTapManager] Nothing to do, replaying the click for the Dock")
        #endif

        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
    }

    private func clearPendingPress() {
        gate.cancel()
        holdTimer?.invalidate()
        holdTimer = nil
        pendingTarget = nil
        pendingEvent = nil
    }
}
