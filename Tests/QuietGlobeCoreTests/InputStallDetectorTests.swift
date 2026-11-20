import Testing
@testable import QuietGlobeCore

/// `#expect` cannot call a mutating method directly.
private func step(_ d: inout InputStallDetector, now: Double, hardwareIdle: Double, sessionIdle: Double) -> Bool {
    d.update(now: now, hardwareIdle: hardwareIdle, sessionIdle: sessionIdle)
}

@Suite struct InputStallDetectorTests {
    @Test func normalInputIsNotAStall() {
        var d = InputStallDetector()
        for t in stride(from: 0.0, through: 5.0, by: 0.25) {
            #expect(!step(&d, now: t, hardwareIdle: 0.1, sessionIdle: 0.1))
        }
    }

    @Test func idleUserIsNotAStall() {
        var d = InputStallDetector()
        #expect(!step(&d, now: 0, hardwareIdle: 30, sessionIdle: 30))
        #expect(!step(&d, now: 1, hardwareIdle: 31, sessionIdle: 31))
    }

    @Test func continuousStuckInputTriggersAfterConfirmation() {
        var d = InputStallDetector()
        #expect(!step(&d, now: 0, hardwareIdle: 0.05, sessionIdle: 2.0))
        #expect(!step(&d, now: 0.25, hardwareIdle: 0.1, sessionIdle: 2.25))
        #expect(step(&d, now: 0.5, hardwareIdle: 0.05, sessionIdle: 2.5))
    }

    /// One click during a freeze, then nothing: the gap stays open while
    /// both idle times grow, so the stall is still detected.
    @Test func singleClickDuringFreezeIsDetected() {
        var d = InputStallDetector()
        // Session froze at t=0; one click at t=2.0; sampled every 0.25 s.
        var fired = false
        for t in stride(from: 2.1, through: 4.0, by: 0.25) {
            fired = fired || step(&d, now: t, hardwareIdle: t - 2.0, sessionIdle: t)
        }
        #expect(fired)
    }

    /// Sparse clicks, about one per second, whatever the timer phase.
    @Test func sparseClicksAreDetectedForAnyTimerPhase() {
        for phase in stride(from: 0.0, to: 0.25, by: 0.05) {
            var d = InputStallDetector()
            var fired = false
            var t = 2.0 + phase
            while t < 6.0 {
                let lastClick = t.rounded(.down)  // clicks at 1, 2, 3, ... s; session frozen since 0
                fired = fired || step(&d, now: t, hardwareIdle: t - lastClick, sessionIdle: t)
                t += 0.25
            }
            #expect(fired, "phase \(phase)")
        }
    }

    @Test func shortLagIsTolerated() {
        var d = InputStallDetector()
        #expect(!step(&d, now: 0, hardwareIdle: 0.05, sessionIdle: 1.0))
        #expect(!step(&d, now: 1, hardwareIdle: 0.05, sessionIdle: 1.2))
    }

    @Test func recoveryResetsTheTimer() {
        var d = InputStallDetector()
        #expect(!step(&d, now: 0, hardwareIdle: 0.05, sessionIdle: 2.0))
        #expect(!step(&d, now: 0.25, hardwareIdle: 0.05, sessionIdle: 0.05))
        #expect(!step(&d, now: 0.5, hardwareIdle: 0.05, sessionIdle: 2.0))
        #expect(step(&d, now: 1.0, hardwareIdle: 0.05, sessionIdle: 2.5))
    }

    @Test func unknownHardwareIdleIsIgnored() {
        var d = InputStallDetector()
        #expect(!step(&d, now: 0, hardwareIdle: -1, sessionIdle: 10))
        #expect(!step(&d, now: 1, hardwareIdle: -1, sessionIdle: 11))
    }
}
