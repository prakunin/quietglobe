import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit
import QuietGlobeCore

/// Owns the global event tap that intercepts the Globe key.
///
/// macOS reports the Globe key as key code 179. The tap consumes that key
/// before the system can show the input source indicator (the ABC/Russian HUD),
/// then asks `InputSourceSwitcher` to change the layout.
///
/// Globe is a tap-or-modifier key: a clean press-and-release switches the
/// layout (on key-up); pressing another key while Globe is held does not.
/// Fn+Esc retypes the last typed word in the other layout (`Retyper`). All events
/// except Globe and the Fn+Esc pair are passed through unchanged.
///
/// This class is a thin adapter: it converts CGEvents to plain values, feeds them
/// to `KeyStateMachine` (which holds all the state and logic, and is unit-tested),
/// and performs the resulting action.
final class EventTapController {
    private let switcher: InputSourceSwitcher
    private let retyper: Retyper
    /// Asked on every Fn+Esc, so the menu toggle takes effect immediately.
    private let isRetypeEnabled: () -> Bool
    private let isGlobeEnabled: () -> Bool
    private var machine = KeyStateMachine()
    private var appObserver: NSObjectProtocol?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Watches the tap's health while it is installed (see `checkHealth`).
    private var healthTimer: Timer?
    private var stallDetector = InputStallDetector()
    /// Health ticks since the last probe tap (see `probeTapAllowed`).
    private var ticksSinceProbe = 0
    /// Probe every this many health ticks (4 × 0.25 s = 1 s).
    private static let probeEvery = 4
    /// Sleep, display sleep, screen lock, fast user switching: input does not
    /// reach the session then, and that is not a dead tap.
    private var systemAsleep = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var systemObservers: [NSObjectProtocol] = []
    /// Seconds after wake or unlock before the stall check runs again.
    private static let wakeGrace: Double = 10

    enum Failure {
        /// `AXIsProcessTrusted()` says the permission is gone.
        case permissionRevoked
        /// Input stopped reaching the session (permission removed while the
        /// trust check still says yes, or a false positive such as a wake-up key).
        case inputStalled
        /// A probe tap could not be created: the window server no longer lets
        /// this process tap events, although `AXIsProcessTrusted()` may still say yes.
        case tapDenied
    }

    /// Called on the main thread after the tap was torn down because it stopped working.
    var onTapFailed: ((Failure) -> Void)?
    /// Called on the main thread when the Mac wakes, the screen is unlocked
    /// or the user session becomes active again.
    var onSystemResumed: (() -> Void)?

    init(switcher: InputSourceSwitcher, isRetypeEnabled: @escaping () -> Bool = { true },
         isGlobeEnabled: @escaping () -> Bool = { true }) {
        self.switcher = switcher
        self.retyper = Retyper(switcher: switcher)
        self.isRetypeEnabled = isRetypeEnabled
        self.isGlobeEnabled = isGlobeEnabled
        observeSystemState()
    }

    /// Tracks sleep, display sleep, lock and session switches, so a key that
    /// never reached the session in those states is not taken for a dead tap.
    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name, (EventTapController) -> Void, Bool)] = [
            (workspace, NSWorkspace.willSleepNotification, { $0.systemAsleep = true }, false),
            (workspace, NSWorkspace.didWakeNotification, { $0.systemAsleep = false }, true),
            (workspace, NSWorkspace.screensDidSleepNotification, { $0.screensAsleep = true }, false),
            (workspace, NSWorkspace.screensDidWakeNotification, { $0.screensAsleep = false }, true),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, { $0.sessionInactive = true }, false),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionInactive = false }, true),
            (distributed, Notification.Name("com.apple.screenIsLocked"), { _ in }, false),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), { _ in }, true),
        ]
        for (center, name, apply, resumed) in events {
            systemObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                apply(self)
                log("system: \(name.rawValue)")
                self.stallDetector.pause(until: ProcessInfo.processInfo.systemUptime + Self.wakeGrace)
                if resumed { self.onSystemResumed?() }
            })
        }
    }

    /// Input legitimately does not reach the session right now.
    private var inputIsAway: Bool {
        systemAsleep || screensAsleep || sessionInactive || Self.screenIsLocked()
    }

    /// The lock screen (or another user's session) is in front.
    private static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        if let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool, !onConsole { return true }
        return false
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
            self?.machine.appActivated()
        }

        // An active tap whose process lost Accessibility trust freezes all
        // keyboard and mouse input system-wide. Watch for it and tear the tap down.
        stallDetector.reset()
        ticksSinceProbe = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
        log("event tap started")
        return true
    }

    /// Removes and invalidates the event tap.
    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
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
        machine.reset()
        log("event tap stopped")
    }

    /// Tears the tap down when the permission is gone or input got stuck.
    ///
    /// Removing the app from the Accessibility list does not always make
    /// `AXIsProcessTrusted()` return false, so the input itself is checked
    /// too: the hardware sees keys and mouse, but the session gets nothing.
    private func checkHealth() {
        guard isRunning else { return }
        if !AXIsProcessTrusted() {
            fail(.permissionRevoked, "Accessibility permission revoked")
            return
        }
        ticksSinceProbe += 1
        if ticksSinceProbe >= Self.probeEvery {
            ticksSinceProbe = 0
            // Not at the lock screen or while asleep: there a refusal may mean nothing.
            if !inputIsAway, !Self.probeTapAllowed() {
                fail(.tapDenied, "a probe tap was refused")
                return
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let sessionIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        let hardwareIdle = Self.hardwareIdleSeconds()
        // Asked only when the gap is open: the lock check is an IPC call.
        if stallDetector.gapIsOpen(hardwareIdle: hardwareIdle, sessionIdle: sessionIdle), inputIsAway {
            stallDetector.pause(until: now + Self.wakeGrace)
            return
        }
        if stallDetector.update(now: now, hardwareIdle: hardwareIdle, sessionIdle: sessionIdle) {
            fail(.inputStalled, "input stalled (session idle \(String(format: "%.1f", sessionIdle)) s)")
        }
    }

    /// Creates a second, throw-away active tap and removes it at once.
    ///
    /// After QuietGlobe is removed from the Accessibility list with "−",
    /// `AXIsProcessTrusted()` keeps saying yes, but the window server stops
    /// granting new active taps. Catching that early removes our tap before
    /// it can freeze input (the stall detector stays as the backstop).
    /// The probe is never added to a run loop and is disabled before it is
    /// invalidated, so it never holds up an event.
    private static func probeTapAllowed() -> Bool {
        guard let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)
        return true
    }

    private func fail(_ failure: Failure, _ reason: String) {
        guard isRunning else { return }
        log("event tap failed: \(reason); removing it")
        stop()
        onTapFailed?(failure)
    }

    /// Seconds since the last keyboard/mouse event at the HID level, or -1.
    private static func hardwareIdleSeconds() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return -1
        }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return -1 }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return -1 }
        return value.doubleValue / 1_000_000_000
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that take too long or when the user interrupts
        // them. Re-enable the tap and pass the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Never re-enable a tap without Accessibility trust: that is what
            // freezes input system-wide. Drop it instead.
            guard AXIsProcessTrusted() else {
                log("event tap disabled and Accessibility revoked: removing the tap")
                DispatchQueue.main.async { [weak self] in self?.fail(.permissionRevoked, "tap disabled without Accessibility permission") }
                return Unmanaged.passUnretained(event)
            }
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

        let output: KeyStateMachine.Output
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            output = machine.mouseDown()
        case .flagsChanged:
            output = machine.flagsChanged(fn: event.flags.contains(.maskSecondaryFn))
        case .keyDown:
            let flags = event.flags
            output = machine.keyDown(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                shift: flags.contains(.maskShift),
                option: flags.contains(.maskAlternate),
                command: flags.contains(.maskCommand),
                control: flags.contains(.maskControl),
                isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType),
                retypeEnabled: isRetypeEnabled,
                globeEnabled: isGlobeEnabled,
                secureInputEnabled: { IsSecureEventInputEnabled() }
            )
        case .keyUp:
            output = machine.keyUp(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                globeEnabled: isGlobeEnabled
            )
        default:
            return Unmanaged.passUnretained(event)
        }

        switch output.action {
        case .switchLayout:
            switcher.switchToAlternativeLayout()
        case let .retype(keys, deleteCount, switchLayout, keyboardType):
            retyper.retype(keys: keys, deleteCount: deleteCount, switchLayout: switchLayout, keyboardType: keyboardType)
        case .nothingToRetype:
            // The tap runs on the main run loop; hop explicitly to be safe.
            DispatchQueue.main.async { NSSound.beep() }
        case nil:
            break
        }
        // A consumed Globe key never reaches TextInputSwitcher, so it shows no HUD.
        return output.consume ? nil : Unmanaged.passUnretained(event)
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
