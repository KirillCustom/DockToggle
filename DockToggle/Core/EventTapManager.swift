import Cocoa
import CoreGraphics

struct ClickTarget: Sendable {
    let item: DockItem
    let app: NSRunningApplication
}

protocol EventTapDelegate: AnyObject, Sendable {
    nonisolated func eventTapResolveClick(at point: CGPoint) -> ClickTarget?
    nonisolated func eventTapHandleClick(target: ClickTarget)
}

final class EventTapManager {
    weak var delegate: EventTapDelegate?

    /// Stamped on the mouse-down we re-post so the tap recognizes it and lets it through.
    private static let handOffMarker: Int64 = 0x444F_434B // "DOCK"

    /// Modifier clicks are the Dock's own gestures (context menu, reveal in Finder, hide others).
    private static let passThroughModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private var gate = DockPressGate()
    private var pendingTarget: ClickTarget?
    private var pendingEvent: CGEvent?
    private var holdTimer: Timer?

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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        #if DEBUG
        print("[EventTapManager] Event tap stopped")
        #endif
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

        // The mouse-down we handed back to the Dock — never intercept it a second time.
        if event.getIntegerValueField(.eventSourceUserData) == Self.handOffMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            if gate.move(to: event.location) == .handOff {
                handOffToDock()
            }
            return Unmanaged.passUnretained(event)
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

        return nil
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard gate.release() == .toggle, let target = pendingTarget else {
            return Unmanaged.passUnretained(event)
        }
        clearPendingPress()

        DispatchQueue.main.async { [weak delegate] in
            delegate?.eventTapHandleClick(target: target)
        }

        // The Dock never saw the matching mouse-down, so it must not see this either.
        return nil
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
    /// handling. Posted at the current pointer location to avoid warping the cursor back.
    private func handOffToDock() {
        guard let event = pendingEvent else {
            clearPendingPress()
            return
        }
        if let location = CGEvent(source: nil)?.location {
            event.location = location
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.handOffMarker)
        event.post(tap: .cghidEventTap)
        #if DEBUG
        print("[EventTapManager] Handed press back to the Dock")
        #endif
        clearPendingPress()
    }

    private func clearPendingPress() {
        gate.cancel()
        holdTimer?.invalidate()
        holdTimer = nil
        pendingTarget = nil
        pendingEvent = nil
    }
}
