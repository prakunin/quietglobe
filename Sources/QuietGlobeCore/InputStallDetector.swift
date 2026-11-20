/// Detects a dead event tap: the hardware produced input that never reached
/// the window server session.
///
/// This happens when the app's Accessibility permission is removed while its
/// active event tap is installed: macOS keeps the tap in the event chain but
/// stops feeding it, so keyboard and mouse input freezes system-wide.
/// `AXIsProcessTrusted()` may keep returning true in that state, so the
/// detector relies on the input itself.
///
/// Signal: the last hardware event is newer than the last session event by
/// more than `lag`. Normally the session sees every hardware event within
/// milliseconds, so the two idle times move together. During a freeze the gap
/// stays open even for a single click, because both idle times then grow at
/// the same rate (a lone click must not age out of the check).
public struct InputStallDetector {
    /// How much newer the hardware input must be than the session's.
    public var lag: Double
    /// The gap must persist this long before we react.
    public var confirm: Double

    private var stallStart: Double?

    public init(lag: Double = 1.5, confirm: Double = 0.5) {
        self.lag = lag
        self.confirm = confirm
    }

    /// - Parameters:
    ///   - now: monotonic time, seconds.
    ///   - hardwareIdle: seconds since the last HID event (IOHIDSystem HIDIdleTime), -1 if unknown.
    ///   - sessionIdle: seconds since the last event the session received.
    /// - Returns: true when input is stuck and the tap must be removed.
    public mutating func update(now: Double, hardwareIdle: Double, sessionIdle: Double) -> Bool {
        let stalled = hardwareIdle >= 0 && sessionIdle - hardwareIdle > lag
        guard stalled else {
            stallStart = nil
            return false
        }
        if stallStart == nil { stallStart = now }
        return now - (stallStart ?? now) >= confirm
    }

    public mutating func reset() {
        stallStart = nil
    }
}
