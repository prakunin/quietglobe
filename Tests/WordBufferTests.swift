import Foundation

// Plain executable tests for WordBuffer (no XCTest). Run via scripts/test.sh.

var failures = 0
func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(name)")
    }
}

// Key codes: g=5 h=4 b=11 d=2 t=17 n=45 a=0, comma=43
func type(_ b: inout WordBuffer, _ codes: [UInt16], shift: Bool = false, option: Bool = false) {
    for c in codes { b.keyDown(keyCode: c, shift: shift, option: option, command: false, control: false) }
}
func codes(_ b: WordBuffer) -> [UInt16] { b.entries.map(\.keyCode) }

let ghbdtn: [UInt16] = [5, 4, 11, 2, 17, 45]
let vbh: [UInt16] = [9, 11, 4]
let sp: UInt16 = 49
let del = WordBuffer.Code.delete

// append + modifiers recorded
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    check(codes(b) == ghbdtn, "append plain keys")
    type(&b, [0], shift: true)
    type(&b, [0], option: true)
    check(b.entries[6] == .init(keyCode: 0, shift: true, option: false), "shift recorded")
    check(b.entries[7] == .init(keyCode: 0, shift: false, option: true), "option recorded")
}

// punctuation keys are part of the word
do {
    var b = WordBuffer()
    type(&b, [43, 47, 41, 39, 33, 30, 50])
    check(b.entries.count == 7 && b.suffixStart(words: 1) == 0, "punctuation keys are letters")
}

// history across words, spaces are entries
do {
    var b = WordBuffer()
    type(&b, ghbdtn + [sp] + vbh)
    check(codes(b) == ghbdtn + [sp] + vbh, "history survives across words")
}

// delete
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    type(&b, [del])
    check(codes(b) == Array(ghbdtn.dropLast()), "delete removes last key")
    var e = WordBuffer()
    type(&e, [del])
    check(e.isEmpty, "delete on empty is harmless")
    var c = WordBuffer()
    type(&c, ghbdtn + [sp])
    type(&c, [del])
    check(codes(c) == ghbdtn, "delete removes a space")
    type(&c, [sp] + vbh)
    type(&c, [del, del, del, del])
    check(codes(c) == Array(ghbdtn), "delete across a space back into the first word")
    type(&c, [del])
    check(codes(c) == Array(ghbdtn.dropLast()), "delete keeps eating the first word")
}

// suffixStart
do {
    var b = WordBuffer()
    check(b.suffixStart(words: 1) == nil, "empty: no words")
    type(&b, [sp, sp])
    check(b.suffixStart(words: 1) == nil, "only spaces: no words")

    var s = WordBuffer()
    type(&s, ghbdtn + [sp] + vbh)
    check(s.suffixStart(words: 1) == 7, "n=1 single space")
    check(s.suffixStart(words: 2) == 0, "n=2 single space")
    check(s.suffixStart(words: 3) == nil, "n=3 not enough words")
    check(s.suffixStart(words: 0) == nil, "n=0 is nil")

    var m = WordBuffer()
    type(&m, [0] + [sp, sp] + ghbdtn + [sp, sp, sp] + vbh) // a  ghbdtn   vbh
    let vStart = 1 + 2 + 6 + 3
    check(m.suffixStart(words: 1) == vStart, "n=1 multiple spaces")
    check(m.suffixStart(words: 2) == 3, "n=2 multiple spaces")
    check(m.suffixStart(words: 3) == 0, "n=3 multiple spaces")
    check(m.suffixStart(words: 4) == nil, "n=4 not enough words")

    var t = WordBuffer()
    type(&t, ghbdtn + [sp, sp] + vbh + [sp])
    check(t.suffixStart(words: 1) == 8, "trailing space belongs to suffix, n=1")
    check(t.suffixStart(words: 2) == 0, "trailing space, n=2")
    type(&t, [sp, sp])
    check(t.suffixStart(words: 1) == 8, "several trailing spaces")

    var l = WordBuffer()
    type(&l, [sp, sp] + ghbdtn)
    check(l.suffixStart(words: 1) == 2, "leading spaces are not a word")
    check(l.suffixStart(words: 2) == nil, "leading spaces: only one word")
}

// resets
func assertResets(_ name: String, _ f: (inout WordBuffer) -> Void) {
    var b = WordBuffer()
    type(&b, ghbdtn + [sp] + vbh)
    f(&b)
    check(b.isEmpty && b.suffixStart(words: 1) == nil, "reset on \(name)")
}
assertResets("cmd") { $0.keyDown(keyCode: 0, shift: false, option: false, command: true, control: false) }
assertResets("ctrl") { $0.keyDown(keyCode: 0, shift: false, option: false, command: false, control: true) }
assertResets("cmd+space") { $0.keyDown(keyCode: 49, shift: false, option: false, command: true, control: false) }
assertResets("return") { type(&$0, [36]) }
assertResets("tab") { type(&$0, [48]) }
assertResets("escape") { type(&$0, [53]) }
for (n, c) in [("left", 123), ("right", 124), ("down", 125), ("up", 126),
               ("home", 115), ("end", 119), ("pgup", 116), ("pgdn", 121), ("fwd-delete", 117)] {
    assertResets(n) { type(&$0, [UInt16(c)]) }
}
assertResets("mouse") { $0.reset() }

// cap: oldest entries are dropped
do {
    var b = WordBuffer()
    type(&b, [UInt16](repeating: 0, count: WordBuffer.maxKeys))
    check(b.entries.count == WordBuffer.maxKeys, "exactly cap is fine")
    type(&b, [5])
    check(b.entries.count == WordBuffer.maxKeys, "overflow keeps the cap")
    check(b.entries.last?.keyCode == 5 && b.entries.first?.keyCode == 0, "overflow drops the oldest")
    type(&b, [sp, 4])
    check(b.entries.count == WordBuffer.maxKeys && b.suffixStart(words: 2) != nil, "typing continues after overflow")
}

// re-recording after retype gives the same keys
do {
    var b = WordBuffer()
    type(&b, ghbdtn + [sp] + vbh + [sp])
    var again = WordBuffer()
    type(&again, b.entries.map(\.keyCode))
    check(again.entries == b.entries, "replay re-records identically")
}

if failures == 0 { print("All WordBuffer tests passed") }
exit(failures == 0 ? 0 : 1)
