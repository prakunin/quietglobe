import AppKit
import Carbon
import CoreGraphics
import Foundation
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

    init(switcher: InputSourceSwitcher, isRetypeEnabled: @escaping () -> Bool = { true },
         isGlobeEnabled: @escaping () -> Bool = { true }) {
        self.switcher = switcher
        self.retyper = Retyper(switcher: switcher)
        self.isRetypeEnabled = isRetypeEnabled
        self.isGlobeEnabled = isGlobeEnabled
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
        machine.reset()
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
