import Testing
import CoreGraphics
@testable import DockToggle

@Suite("RestoreSequence.order")
struct RestoreSequenceOrderTests {

    @Test("with a captured order, the frontmost window comes last")
    func frontmostRestoredLast() {
        // Front-to-back: 1 was frontmost, 3 was rearmost.
        let order = RestoreSequence.order(ids: [1, 2, 3], frontToBack: [1, 2, 3])
        #expect(order == [2, 1, 0]) // rearmost (3) first, frontmost (1) last
    }

    @Test("a single window has nothing to reorder")
    func singleWindow() {
        let order = RestoreSequence.order(ids: [1], frontToBack: [1])
        #expect(order == [0])
    }

    @Test("windows missing from the captured order sort as rearmost")
    func uncapturedWindowIsRearmost() {
        // id 9 was never captured (minimized some other way) — it should sort before (i.e.
        // restore ahead of) every window the capture does know about.
        let order = RestoreSequence.order(ids: [1, 9, 2], frontToBack: [1, 2])
        #expect(order.last == 0) // id 1, the captured frontmost, is still restored last
        #expect(order.firstIndex(of: 1)! < order.firstIndex(of: 0)!) // id 9 (index 1) before id 1 (index 0)
    }

    @Test("duplicate window IDs are dropped, first occurrence kept")
    func duplicatesDropped() {
        let order = RestoreSequence.order(ids: [1, 1, 2], frontToBack: [1, 2])
        #expect(order.filter { $0 == 0 }.count == 1) // only one slot for id 1 survives
        #expect(!order.contains(1)) // the duplicate's index never appears
    }

    @Test("nil window IDs are never treated as duplicates of each other")
    func nilIDsAreNotDuplicates() {
        let order = RestoreSequence.order(ids: [nil, nil, 5], frontToBack: [5])
        #expect(order.count == 3)
    }

    // MARK: - No captured order (minimized by other means)

    @Test("without a captured order, the preferred front window is moved last")
    func preferredFrontMovesLast() {
        let order = RestoreSequence.order(ids: [1, 2, 3], frontToBack: [], preferredFront: 2)
        #expect(order == [0, 2, 1])
    }

    @Test("without a captured order and no preferred front, the given order is kept as-is")
    func noPreferenceKeepsGivenOrder() {
        let order = RestoreSequence.order(ids: [3, 1, 2], frontToBack: [])
        #expect(order == [0, 1, 2])
    }

    @Test("a preferred front that isn't in the batch is ignored")
    func unknownPreferredFrontIgnored() {
        let order = RestoreSequence.order(ids: [1, 2], frontToBack: [], preferredFront: 99)
        #expect(order == [0, 1])
    }

    @Test("an empty batch returns an empty order")
    func emptyBatch() {
        let order = RestoreSequence.order(ids: [], frontToBack: [1, 2])
        #expect(order.isEmpty)
    }
}

@Suite("RestoreSequence.capturedMinimizeStillHolds")
struct CapturedMinimizeStillHoldsTests {
    @Test("holds when at least one captured window is still minimized")
    func stillHolds() {
        #expect(RestoreSequence.capturedMinimizeStillHolds(captured: [1, 2], stillMinimized: [2, 3]))
    }

    @Test("does not hold when none of the captured windows are still minimized")
    func doesNotHold() {
        #expect(!RestoreSequence.capturedMinimizeStillHolds(captured: [1, 2], stillMinimized: [3, 4]))
    }

    @Test("an empty capture never holds")
    func emptyCaptureNeverHolds() {
        #expect(!RestoreSequence.capturedMinimizeStillHolds(captured: [], stillMinimized: [1]))
    }
}
