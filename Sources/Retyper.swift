import CoreGraphics
import Foundation

/// Retypes the last word in the other keyboard layout (Fn+Esc).
///
/// The user is physically holding Fn while this runs, so synthetic events must
/// not inherit it (Fn+Backspace would be forward delete). Every posted event
/// therefore comes from a `.privateState` source and carries explicitly set flags.
///
/// Posting goes to `.cgSessionEventTap`: it injects events after the HID layer,
/// where the physical Fn/modifier state lives, so the held Fn cannot leak into
/// them. Our own tap sits on the same session tap, so every event is marked
/// with `eventMarker` and the tap lets marked events through untouched.
///
/// All timing-sensitive work happens on a private serial queue; TIS calls are
/// hopped to the main thread, which the Text Input Sources API requires.
final class Retyper {
    /// Value written to `.eventSourceUserData` of every synthetic event ("QGLB").
    static let eventMarker: Int64 = 0x51474C42

    /// Pause between posted events, microseconds.
    static let postGap: useconds_t = 1_500
    /// How often to check that the layout switch has happened, microseconds.
    static let pollInterval: useconds_t = 5_000
    /// Give up waiting for the layout switch after this long, seconds.
    static let pollTimeout: TimeInterval = 0.3
    /// Extra wait after the switch is reported, so the first letters use the new layout.
    static let settleDelay: useconds_t = 40_000

    private static let backspaceKeyCode: UInt16 = 51

    private let switcher: InputSourceSwitcher
    private let queue = DispatchQueue(label: "quietglobe.retyper", qos: .userInteractive)

    init(switcher: InputSourceSwitcher) {
        self.switcher = switcher
    }

    /// Queues a retype: delete `deleteCount` characters, optionally switch layout, replay `keys`.
    /// Returns immediately; jobs run in order on a serial queue, so a quick second Esc is not dropped.
    func retype(keys: [WordBuffer.Key], deleteCount: Int, switchLayout: Bool, keyboardType: Int64) {
        guard !keys.isEmpty else { return }
        log("retype queued: \(keys.count) keys, delete \(deleteCount), switch \(switchLayout)")
        queue.async { [self] in
            run(keys: keys, deleteCount: deleteCount, switchLayout: switchLayout, keyboardType: keyboardType)
        }
    }

    private func run(keys: [WordBuffer.Key], deleteCount: Int, switchLayout: Bool, keyboardType: Int64) {
        var targetID: String?
        if switchLayout {
            // Check there is somewhere to switch BEFORE deleting anything.
            guard let id = onMain({ switcher.alternativeLayoutID() }) else {
                log("retype aborted: no alternative layout")
                return
            }
            targetID = id
        }
        guard let source = CGEventSource(stateID: .privateState) else {
            log("retype aborted: no event source")
            return
        }

        for _ in 0..<deleteCount {
            post(keyCode: Self.backspaceKeyCode, shift: false, option: false, source: source, keyboardType: keyboardType)
        }

        if let targetID {
            _ = onMain { switcher.switchToAlternativeLayoutReportingTarget() }
            if waitForLayout(targetID) {
                usleep(Self.settleDelay)
            } else {
                log("layout switch not confirmed within timeout, typing anyway")
            }
        }

        for key in keys {
            post(keyCode: key.keyCode, shift: key.shift, option: key.option, source: source, keyboardType: keyboardType)
        }
        log("retype finished")
    }

    /// Polls the current layout id until it equals `id` or the timeout passes.
    private func waitForLayout(_ id: String) -> Bool {
        let deadline = Date().addingTimeInterval(Self.pollTimeout)
        while Date() < deadline {
            if onMain({ switcher.currentInputSourceID() }) == id { return true }
            usleep(Self.pollInterval)
        }
        return false
    }

    /// Posts a marked key-down + key-up with exactly the given modifier flags.
    private func post(keyCode: UInt16, shift: Bool, option: Bool, source: CGEventSource, keyboardType: Int64) {
        var flags = CGEventFlags()
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown) else { continue }
            event.flags = flags  // explicit, even when empty: never inherit Fn
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            if keyboardType > 0 {
                event.setIntegerValueField(.keyboardEventKeyboardType, value: keyboardType)
            }
            event.post(tap: .cgSessionEventTap)
        }
        usleep(Self.postGap)
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
