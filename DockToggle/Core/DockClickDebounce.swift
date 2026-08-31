import Foundation
import os.lock

/// Swallows a Dock click that lands right after one already handled for the same app. Two
/// mouse-ups can land here for one physical double-click; acting on the second would toggle
/// right back and make the click look like it did nothing.
nonisolated final class DockClickDebounce: @unchecked Sendable {
    static let shared = DockClickDebounce()

    private static let gap: TimeInterval = 0.25

    private struct State: Sendable {
        var lastHandled: [pid_t: CFAbsoluteTime] = [:]
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private init() {}

    /// Records this click as handled and reports whether it landed inside the gap after the
    /// previous one for the same app.
    func shouldSwallow(pid: pid_t) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        return lock.withLock { state in
            state.lastHandled = state.lastHandled.filter { now - $0.value < Self.gap }
            guard state.lastHandled[pid] == nil else { return true }
            state.lastHandled[pid] = now
            return false
        }
    }
}
