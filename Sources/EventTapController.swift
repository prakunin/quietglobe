import AppKit
import Carbon
import CoreGraphics
import Foundation

/// Owns the global event tap that intercepts the Globe key.
///
/// macOS reports the Globe key as key code 179. The tap consumes that key
/// before the system can show the input source indicator (the ABC/Russian HUD),
/// then asks `InputSourceSwitcher` to change the layout.
///
/// Globe is a tap-or-modifier key: a clean press-and-release switches the
/// layout (on key-up); pressing another key while Globe is held does not.
/// Fn+Esc retypes the last typed word in the other layout (`Retyper`); the tap
/// feeds a `WordBuffer` with the keystrokes for that. All events except Globe
/// and the Fn+Esc pair are passed through unchanged.
final class EventTapController {
    /// Virtual key code for the Globe/Fn key on modern Apple keyboards.
    static let globeKeyCode: Int64 = 179
    private static let escapeKeyCode = Int64(WordBuffer.Code.escape)

    private let switcher: InputSourceSwitcher
    private let retyper: Retyper
    /// Asked on every Fn+Esc, so the menu toggle takes effect immediately.
    private let isRetypeEnabled: () -> Bool
    private var buffer = WordBuffer()
    private var lastKeyboardType: Int64 = 0
    private var appObserver: NSObjectProtocol?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // One physical press can emit repeated key-down events. These flags make
    // sure a press produces exactly one layout switch.
    private var globeIsDown = false
    private var globeUsedAsModifier = false
    private var lastGlobeDownTime = Date.distantPast
    /// The Esc key-down of Fn+Esc was consumed, so its key-up must be too.
    private var swallowEscapeUp = false

    init(switcher: InputSourceSwitcher, isRetypeEnabled: @escaping () -> Bool = { true }) {
        self.switcher = switcher
        self.retyper = Retyper(switcher: switcher)
        self.isRetypeEnabled = isRetypeEnabled
    }

    var isRunning: Bool {
        eventTap != nil
    }

    /// Installs the event tap on the current run loop. Safe to call twice.
    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = [
            CGEventType.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ].reduce(0) { $0 | (1 << $1.rawValue) }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // A different frontmost app means a different text field: forget the word.
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.buffer.reset()
        }
        log("event tap started")
        return true
    }

    /// Removes and invalidates the event tap.
    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
        }
        appObserver = nil
        eventTap = nil
        runLoopSource = nil
        buffer.reset()
        globeIsDown = false
        globeUsedAsModifier = false
        swallowEscapeUp = false
        log("event tap stopped")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that take too long or when the user interrupts
        // them. Re-enable the tap and pass the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                log("event tap re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        // Our own synthetic events (retype): never touch state, never consume.
        if (type == .keyDown || type == .keyUp),
           event.getIntegerValueField(.eventSourceUserData) == Retyper.eventMarker {
            return Unmanaged.passUnretained(event)
        }

        let now = Date()
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buffer.reset()
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            recoverStaleGlobe(flags: event.flags, now: now)
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == Self.globeKeyCode {
            handleGlobe(type: type, event: event, now: now)
            // Consume the Globe key so TextInputSwitcher never shows the HUD.
            return nil
        }

        if type == .keyUp {
            if keyCode == Self.escapeKeyCode && swallowEscapeUp {
                swallowEscapeUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        recoverStaleGlobe(flags: event.flags, now: now)

        if globeIsDown {
            // Globe is acting as a modifier, not as a layout switch.
            globeUsedAsModifier = true
            if keyCode == Self.escapeKeyCode && isRetypeEnabled() {
                // Fn+Esc: the buffer must survive, it is what gets retyped.
                swallowEscapeUp = true
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat { startRetype() }
                return nil
            }
            buffer.reset()
            return Unmanaged.passUnretained(event)
        }

        record(keyCode: keyCode, event: event)
        return Unmanaged.passUnretained(event)
    }

    /// Globe key-down/up. The layout switches on key-up, and only if no other key was used.
    private func handleGlobe(type: CGEventType, event: CGEvent, now: Date) {
        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // A non-repeat key-down while "down" means a key-up got lost: start a fresh press.
            if !isRepeat {
                globeIsDown = true
                globeUsedAsModifier = false
                lastGlobeDownTime = now
            }
        } else if globeIsDown {
            globeIsDown = false
            if !globeUsedAsModifier {
                switcher.switchToAlternativeLayout()
            }
        }
    }

    /// If a Globe key-up got lost, stop treating Globe as held once Fn is really released.
    private func recoverStaleGlobe(flags: CGEventFlags, now: Date) {
        if globeIsDown, !flags.contains(.maskSecondaryFn),
           now.timeIntervalSince(lastGlobeDownTime) > 1.0 {
            globeIsDown = false
            log("stale Globe state cleared")
        }
    }

    /// Feeds a normal key-down into the word buffer (never records under secure input).
    private func record(keyCode: Int64, event: CGEvent) {
        if IsSecureEventInputEnabled() {
            buffer.reset()
            return
        }
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        if keyboardType > 0 { lastKeyboardType = keyboardType }

        let flags = event.flags
        buffer.keyDown(
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            shift: flags.contains(.maskShift),
            option: flags.contains(.maskAlternate),
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl)
        )
    }

    /// Hands the buffered word to the retyper; the tap callback returns immediately.
    private func startRetype() {
        guard !IsSecureEventInputEnabled() else { return }
        let word = bufferedWord
        guard !word.word.isEmpty else { return }
        retyper.retype(word: word.word, tail: word.tail, keyboardType: lastKeyboardType)
    }

    private var bufferedWord: (word: [WordBuffer.Key], tail: Int) {
        (buffer.word, buffer.tailSpaces)
    }
}

/// C callback for the event tap. The controller is passed through `userInfo`.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
