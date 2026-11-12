import Foundation

/// Pure in-memory record of the keystrokes of the line the user is typing.
///
/// It stores physical key codes (not characters), so the same keys can be
/// replayed after the keyboard layout has changed. The buffer holds no
/// AppKit/CoreGraphics types and never logs or persists anything.
public struct WordBuffer {
    /// One recorded keystroke: the physical key plus the modifiers that change its character.
    public struct Key: Equatable {
        public var keyCode: UInt16
        public var shift: Bool
        public var option: Bool

        public init(keyCode: UInt16, shift: Bool, option: Bool) {
            self.keyCode = keyCode
            self.shift = shift
            self.option = option
        }
    }

    /// Key codes (macOS virtual key codes) the buffer reacts to.
    public enum Code {
        public static let returnKey: UInt16 = 36
        public static let tab: UInt16 = 48
        public static let space: UInt16 = 49
        public static let delete: UInt16 = 51
        public static let escape: UInt16 = 53
    }

    /// Maximum number of entries kept; on overflow the oldest are dropped.
    public static let maxKeys = 256

    /// Keystrokes of the current line since the last reset, oldest first.
    /// Spaces are entries too (key code 49).
    public private(set) var entries: [Key] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// Main-block keys that produce text: letters, digit row, punctuation.
    /// In layouts such as Russian, punctuation keys are letters, so they belong to the word.
    public static func isPrintable(_ keyCode: UInt16) -> Bool {
        guard keyCode <= 50 else { return false }
        return keyCode != Code.returnKey && keyCode != Code.tab && keyCode != Code.space
    }

    /// Forgets everything (cursor moved, app changed, secure input, ...).
    public mutating func reset() {
        entries.removeAll()
    }

    /// Index in `entries` where the n-th word from the end starts, or nil if there are fewer
    /// than `n` words. A word is a maximal run of non-space entries; spaces after the last
    /// word belong to the suffix.
    public func suffixStart(words n: Int) -> Int? {
        guard n > 0 else { return nil }
        var i = entries.count
        var start = i
        for _ in 0..<n {
            while i > 0, entries[i - 1].keyCode == Code.space { i -= 1 }
            guard i > 0 else { return nil }
            while i > 0, entries[i - 1].keyCode != Code.space { i -= 1 }
            start = i
        }
        return start
    }

    /// Feeds one key-down event into the buffer.
    public mutating func keyDown(keyCode: UInt16, shift: Bool, option: Bool, command: Bool, control: Bool) {
        // Shortcuts are not typing: anything with Cmd/Ctrl invalidates the word.
        if command || control {
            reset()
            return
        }

        if keyCode == Code.delete {
            if !entries.isEmpty { entries.removeLast() }
        } else if keyCode == Code.space {
            append(Key(keyCode: Code.space, shift: false, option: false))
        } else if Self.isPrintable(keyCode) {
            append(Key(keyCode: keyCode, shift: shift, option: option))
        } else {
            // Return, Tab, Escape, arrows, Home/End, PgUp/PgDn, forward delete, F-keys, ...
            reset()
        }
    }

    private mutating func append(_ key: Key) {
        if entries.count >= Self.maxKeys {
            entries.removeFirst(entries.count - Self.maxKeys + 1)
        }
        entries.append(key)
    }
}
