import Testing
import Foundation
import CoreGraphics
@testable import DockToggle

@Suite("DockPressGate")
struct DockPressGateTests {

    // MARK: - Click

    @Test("press then release is a toggle")
    func pressReleaseToggles() {
        var gate = DockPressGate()
        #expect(gate.press(at: CGPoint(x: 100, y: 900)) == .wait)
        #expect(gate.isPending)
        #expect(gate.release() == .toggle)
        #expect(!gate.isPending)
    }

    @Test("tiny jitter still counts as a click")
    func jitterStillToggles() {
        var gate = DockPressGate(dragThreshold: 4.0)
        _ = gate.press(at: CGPoint(x: 100, y: 900))
        #expect(gate.move(to: CGPoint(x: 102, y: 901)) == .wait)
        #expect(gate.release() == .toggle)
    }

    // MARK: - Drag

    @Test("moving past the threshold hands the press to the Dock")
    func dragHandsOff() {
        var gate = DockPressGate(dragThreshold: 4.0)
        _ = gate.press(at: CGPoint(x: 100, y: 900))
        #expect(gate.move(to: CGPoint(x: 130, y: 900)) == .handOff)
        #expect(!gate.isPending)
    }

    @Test("after a hand-off nothing else fires for that press")
    func handOffIsFinal() {
        var gate = DockPressGate(dragThreshold: 4.0)
        _ = gate.press(at: CGPoint(x: 100, y: 900))
        _ = gate.move(to: CGPoint(x: 130, y: 900))
        #expect(gate.move(to: CGPoint(x: 160, y: 900)) == .ignore)
        #expect(gate.release() == .ignore)
    }

    // MARK: - Hold

    @Test("holding past the timeout hands the press to the Dock")
    func holdHandsOff() {
        var gate = DockPressGate()
        _ = gate.press(at: CGPoint(x: 100, y: 900))
        #expect(gate.expire() == .handOff)
        #expect(gate.release() == .ignore)
    }

    // MARK: - No pending press

    @Test("events without a pending press are ignored")
    func idleGateIgnoresEvents() {
        var gate = DockPressGate()
        #expect(!gate.isPending)
        #expect(gate.move(to: CGPoint(x: 100, y: 900)) == .ignore)
        #expect(gate.release() == .ignore)
        #expect(gate.expire() == .ignore)
    }

    @Test("cancel drops the press without handing it off")
    func cancelDropsPress() {
        var gate = DockPressGate()
        _ = gate.press(at: CGPoint(x: 100, y: 900))
        gate.cancel()
        #expect(!gate.isPending)
        #expect(gate.release() == .ignore)
    }
}
