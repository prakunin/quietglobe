import Foundation

/// Pure in-memory record of the word the user is typing right now.
///
/// It stores physical key codes (not characters), so the same keys can be
/// replayed after the keyboard layout has changed. The buffer holds no
/// AppKit/CoreGraphics types and never logs or persists anything.
struct WordBuffer {
    /// One recorded keystroke: the physical key plus the modifiers that change its character.
    struct Key: Equatable {
        var keyCode: UInt16
        var shift: Bool
        var option: Bool
    }

    /// Key codes (macOS virtual key codes) the buffer reacts to.
    enum Code {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
    }

    /// Maximum number of keys in the word (and in the trailing spaces).
    static let maxKeys = 64

    /// Keys of the current word, oldest first.
    private(set) var word: [Key] = []
    /// Number of spaces typed after the word.
    private(set) var tailSpaces = 0
    /// Set when the word grew past `maxKeys`; the word is then unreliable and ignored.
    private(set) var overflowed = false

    var isEmpty: Bool { word.isEmpty }

    /// Main-block keys that produce text: letters, digit row, punctuation.
    /// In layouts such as Russian, punctuation keys are letters, so they belong to the word.
    static func isPrintable(_ keyCode: UInt16) -> Bool {
        guard keyCode <= 50 else { return false }
        return keyCode != Code.returnKey && keyCode != Code.tab && keyCode != Code.space
    }

    /// Forgets everything (cursor moved, app changed, secure input, ...).
    mutating func reset() {
        word.removeAll()
        tailSpaces = 0
        overflowed = false
    }

    /// Feeds one key-down event into the buffer.
    mutating func keyDown(keyCode: UInt16, shift: Bool, option: Bool, command: Bool, control: Bool) {
        // Shortcuts are not typing: anything with Cmd/Ctrl invalidates the word.
        if command || control {
            reset()
            return
        }

        if keyCode == Code.delete {
            deleteBackward()
        } else if keyCode == Code.space {
            appendSpace()
        } else if Self.isPrintable(keyCode) {
            appendKey(Key(keyCode: keyCode, shift: shift, option: option))
        } else {
            // Return, Tab, Escape, arrows, Home/End, PgUp/PgDn, forward delete, F-keys, ...
            reset()
        }
    }

    private mutating func appendKey(_ key: Key) {
        if tailSpaces > 0 {
            // A new word starts after the spaces; the previous one is out of reach.
            word.removeAll()
            tailSpaces = 0
            overflowed = false
        }
        if overflowed { return }
        if word.count >= Self.maxKeys {
            word.removeAll()
            overflowed = true
            return
        }
        word.append(key)
    }

    private mutating func appendSpace() {
        // A space ends an over-long word: the next key starts a fresh one.
        overflowed = false
        guard !word.isEmpty else { return }
        if tailSpaces >= Self.maxKeys {
            reset()
            return
        }
        tailSpaces += 1
    }

    private mutating func deleteBackward() {
        if tailSpaces > 0 {
            tailSpaces -= 1
        } else if !word.isEmpty {
            word.removeLast()
        }
    }
}
