import CoreGraphics
import Foundation

/// What the event tap should do with a press on a Dock icon.
enum DockPressDecision: Equatable {
    /// No press is being held — deliver the event as usual.
    case ignore
    /// Keep holding the press; we still don't know what it will become.
    case wait
    /// A plain click — run the toggle ourselves.
    case toggle
    /// A drag or a long hold — give the mouse-down back to the Dock.
    case handOff
}

/// Decides whether a press on a Dock icon is a click (ours to handle) or the start of a
/// drag / long press (the Dock's own gesture: rearranging icons, dragging them out, the
/// press-and-hold menu).
///
/// Pure state machine — the event tap owns the actual events and the hold timer.
struct DockPressGate {
    /// How far the pointer may travel before the press counts as a drag.
    let dragThreshold: CGFloat
    /// How long a press may be held before the Dock gets it back.
    let holdTimeout: TimeInterval

    private var origin: CGPoint?

    init(dragThreshold: CGFloat = 4.0, holdTimeout: TimeInterval = 0.5) {
        self.dragThreshold = dragThreshold
        self.holdTimeout = holdTimeout
    }

    var isPending: Bool { origin != nil }

    /// The mouse went down on a dock item we want to handle.
    mutating func press(at point: CGPoint) -> DockPressDecision {
        origin = point
        return .wait
    }

    /// The pointer moved while the button is down.
    mutating func move(to point: CGPoint) -> DockPressDecision {
        guard let origin else { return .ignore }
        guard hypot(point.x - origin.x, point.y - origin.y) > dragThreshold else { return .wait }
        self.origin = nil
        return .handOff
    }

    /// The button came up.
    mutating func release() -> DockPressDecision {
        guard origin != nil else { return .ignore }
        origin = nil
        return .toggle
    }

    /// The hold timer fired — the press lasted longer than a click.
    mutating func expire() -> DockPressDecision {
        guard origin != nil else { return .ignore }
        origin = nil
        return .handOff
    }

    /// Drop the press without handing it anywhere (tap disabled, toggling turned off).
    mutating func cancel() {
        origin = nil
    }
}
