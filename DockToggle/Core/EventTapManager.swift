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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue

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
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .leftMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        let point = event.location

        if let delegate = delegate, let target = delegate.eventTapResolveClick(at: point) {
            DispatchQueue.main.async { [weak delegate] in
                delegate?.eventTapHandleClick(target: target)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
