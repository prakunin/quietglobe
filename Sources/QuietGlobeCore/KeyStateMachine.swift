import Foundation

/// Pure state machine behind the Globe key and Fn+Esc retype.
///
/// It owns every piece of state the event tap used to keep (word buffer, Fn flag,
/// series counter, ...) and knows nothing about CGEvent: the tap converts events to
/// plain values, feeds them in, and acts on the returned `Output`.
///
/// Globe is a tap-or-modifier key: a clean press-and-release switches the layout
/// (on key-up); pressing another key while Fn is held does not. Fn+Esc retypes the
/// last typed word in the other layout; each further Esc while Fn is still held
/// converts one more word.
public struct KeyStateMachine {
    /// Virtual key code for the Globe/Fn key on modern Apple keyboards.
    public static let globeKeyCode: Int64 = 179
    private static let escapeKeyCode = Int64(WordBuffer.Code.escape)

    /// Side effect the caller must perform.
    public enum Action: Equatable {
        /// Globe tap: switch to the alternative layout.
        case switchLayout
        /// Fn+Esc: delete `deleteCount` characters and replay `keys` in the other layout.
        case retype(keys: [WordBuffer.Key], deleteCount: Int, switchLayout: Bool, keyboardType: Int64)
    }

    /// What to do with the incoming event.
    public struct Output: Equatable {
        /// `true` = swallow the event, `false` = let it through unchanged.
        public var consume: Bool
        public var action: Action?

        public static let pass = Output(consume: false, action: nil)
        public static let consumed = Output(consume: true, action: nil)
    }

    public private(set) var buffer = WordBuffer()
    private var lastKeyboardType: Int64 = 0
    /// Another key was pressed while Fn/Globe was held, so releasing Globe must not switch the layout.
    private var globeUsedAsModifier = false
    /// Fn is held according to the modifier flags. On built-in keyboards (macOS 27)
    /// holding Fn produces only flagsChanged (keycode 63) and no keycode-179 key-down
    /// until release, so the flag is the reliable "Fn is held" signal.
    private var fnHeld = false
    /// Words already converted in the current Fn-held series (0 = no series).
    private var seriesWords = 0
    /// The Esc key-down of Fn+Esc was consumed, so its key-up must be too.
    private var swallowEscapeUp = false

    public init() {}

    /// Forgets everything (event tap stopped).
    public mutating func reset() {
        self = KeyStateMachine()
    }

    /// Mouse click: the cursor moved, so the typed word is gone.
    public mutating func mouseDown() -> Output {
        buffer.reset()
        return .pass
    }

    /// A different frontmost app means a different text field.
    public mutating func appActivated() {
        buffer.reset()
    }

    /// Modifier flags changed; `fn` is the state of the Fn flag.
    public mutating func flagsChanged(fn fnNow: Bool) -> Output {
        if fnNow && !fnHeld {
            fnHeld = true
            seriesWords = 0
            globeUsedAsModifier = false  // a new Fn press starts clean
        } else if !fnNow {
            if fnHeld { seriesWords = 0 }
            fnHeld = false
        }
        return .pass
    }

    /// Key-up. Globe is always consumed (the layout switches here); an Esc key-up
    /// after a consumed Fn+Esc is swallowed; everything else passes.
    public mutating func keyUp(keyCode: Int64) -> Output {
        if keyCode == Self.globeKeyCode {
            var output = Output.consumed
            if !globeUsedAsModifier {
                output.action = .switchLayout
            }
            globeUsedAsModifier = false
            return output
        }
        if keyCode == Self.escapeKeyCode && swallowEscapeUp {
            swallowEscapeUp = false
            return .consumed
        }
        return .pass
    }

    /// Key-down.
    ///
    /// `retypeEnabled` is asked only on Fn+Esc (so the menu toggle takes effect at once);
    /// `secureInputEnabled` only when a retype is about to start. Under secure input macOS
    /// does not deliver keystrokes to event taps at all, so nothing is recorded there.
    public mutating func keyDown(
        keyCode: Int64,
        shift: Bool = false,
        option: Bool = false,
        command: Bool = false,
        control: Bool = false,
        isAutorepeat: Bool = false,
        keyboardType: Int64 = 0,
        retypeEnabled: () -> Bool = { true },
        secureInputEnabled: () -> Bool = { false }
    ) -> Output {
        // Globe key-down is just consumed; the layout switches on key-up.
        if keyCode == Self.globeKeyCode { return .consumed }

        if fnHeld {
            // Globe is acting as a modifier, not as a layout switch.
            globeUsedAsModifier = true
            if keyCode == Self.escapeKeyCode && retypeEnabled() {
                // Fn+Esc: the buffer must survive, it is what gets retyped.
                swallowEscapeUp = true
                var output = Output.consumed
                if !isAutorepeat {
                    output.action = startRetype(secureInputEnabled: secureInputEnabled)
                }
                return output
            }
            buffer.reset()
            return .pass
        }

        if keyboardType > 0 { lastKeyboardType = keyboardType }
        buffer.keyDown(
            keyCode: UInt16(truncatingIfNeeded: keyCode),
            shift: shift,
            option: option,
            command: command,
            control: control
        )
        return .pass
    }

    /// Converts the last `seriesWords + 1` words; the layout switches on the first one only.
    private mutating func startRetype(secureInputEnabled: () -> Bool) -> Action? {
        guard !secureInputEnabled() else { return nil }
        let n = seriesWords + 1
        guard let start = buffer.suffixStart(words: n) else { return nil }
        let keys = Array(buffer.entries[start...])
        seriesWords = n
        return .retype(keys: keys, deleteCount: keys.count, switchLayout: n == 1, keyboardType: lastKeyboardType)
    }
}
