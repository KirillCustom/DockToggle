import CoreGraphics

/// Pure window-restore sequencing, kept apart from the Accessibility calls that gather window
/// IDs and the z-order capture so the ordering rule itself is unit-testable.
nonisolated enum RestoreSequence {

    /// The order a restore should walk a batch of minimized windows: indices into `ids`,
    /// first restored to last, with duplicate windows dropped.
    ///
    /// `frontToBack` is the app's real window order captured from the window server while
    /// the windows were still up, so the window that was frontmost — the one the user was
    /// working in — comes LAST. Restoring it last lets it animate in over the others and
    /// land on top on its own: raising it afterward to fix the stacking would be exactly the
    /// visible flick this ordering exists to avoid. The AX windows array order is
    /// deliberately not used to decide this — it does not reliably report the focused window
    /// first.
    ///
    /// `preferredFront` covers batches with no captured order (the app was minimized by
    /// other means): the caller's best guess at the front window is moved to the end and
    /// everything else keeps its given order.
    static func order(ids: [CGWindowID?],
                      frontToBack: [CGWindowID],
                      preferredFront: CGWindowID? = nil) -> [Int] {
        var seen = Set<CGWindowID>()
        var candidates: [Int] = []
        for (index, id) in ids.enumerated() {
            if let id {
                guard !seen.contains(id) else { continue }
                seen.insert(id)
            }
            candidates.append(index)
        }

        guard !frontToBack.isEmpty else {
            guard let preferredFront,
                  let frontSlot = candidates.firstIndex(where: { ids[$0] == preferredFront })
            else { return candidates }
            candidates.append(candidates.remove(at: frontSlot))
            return candidates
        }

        // Windows missing from the captured order count as rearmost, so the captured
        // stacking always decides the top of the pile.
        func depth(_ index: Int) -> Int {
            guard let id = ids[index], let depth = frontToBack.firstIndex(of: id)
            else { return frontToBack.count }
            return depth
        }
        return candidates.sorted { first, second in
            let firstDepth = depth(first), secondDepth = depth(second)
            if firstDepth != secondDepth { return firstDepth > secondDepth }
            return first < second
        }
    }

    /// Whether a captured minimize still speaks for the app's current state.
    ///
    /// The capture is written when this feature minimizes an app and consumed when it
    /// restores one, so anything that brings those windows back some other way (the App
    /// Switcher, the window menu, the app itself) leaves it behind. Acting on a leftover
    /// later would claim a minimize this feature never performed. The capture holds only
    /// while at least one window it named is still down.
    static func capturedMinimizeStillHolds(captured: [CGWindowID], stillMinimized: Set<CGWindowID>) -> Bool {
        captured.contains { stillMinimized.contains($0) }
    }
}
