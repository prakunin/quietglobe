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
func codes(_ b: WordBuffer) -> [UInt16] { b.word.map(\.keyCode) }

let ghbdtn: [UInt16] = [5, 4, 11, 2, 17, 45]

// append + modifiers recorded
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    check(codes(b) == ghbdtn, "append plain keys")
    type(&b, [0], shift: true)
    type(&b, [0], option: true)
    check(b.word[6] == .init(keyCode: 0, shift: true, option: false), "shift recorded")
    check(b.word[7] == .init(keyCode: 0, shift: false, option: true), "option recorded")
}

// punctuation keys are part of the word
do {
    var b = WordBuffer()
    type(&b, [43, 47, 41, 39, 33, 30, 50])
    check(b.word.count == 7, "punctuation keys are letters")
}

// delete
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    type(&b, [WordBuffer.Code.delete])
    check(codes(b) == Array(ghbdtn.dropLast()), "delete removes last key")
    var e = WordBuffer()
    type(&e, [WordBuffer.Code.delete])
    check(e.isEmpty, "delete on empty is harmless")
}

// tail spaces
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    type(&b, [49, 49])
    check(codes(b) == ghbdtn && b.tailSpaces == 2, "tail spaces counted")
    type(&b, [WordBuffer.Code.delete])
    check(b.tailSpaces == 1 && codes(b) == ghbdtn, "delete eats a tail space first")
    var s = WordBuffer()
    type(&s, [49, 49])
    check(s.isEmpty && s.tailSpaces == 0, "leading spaces ignored")
}

// new word after tail
do {
    var b = WordBuffer()
    type(&b, ghbdtn)
    type(&b, [49])
    type(&b, [0])
    check(codes(b) == [0] && b.tailSpaces == 0, "new word replaces previous word+tail")
}

// resets
func assertResets(_ name: String, _ f: (inout WordBuffer) -> Void) {
    var b = WordBuffer()
    type(&b, ghbdtn)
    type(&b, [49])
    f(&b)
    check(b.isEmpty && b.tailSpaces == 0, "reset on \(name)")
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

// cap
do {
    var b = WordBuffer()
    type(&b, [UInt16](repeating: 0, count: WordBuffer.maxKeys))
    check(b.word.count == WordBuffer.maxKeys && !b.overflowed, "exactly cap is fine")
    type(&b, [0])
    check(b.isEmpty && b.overflowed, "overflow invalidates the word")
    type(&b, [0, 0])
    check(b.isEmpty, "overflowed word stays ignored")
    type(&b, [49, 5])
    check(codes(b) == [5] && !b.overflowed, "new word after overflow works")
}

// re-recording after retype gives the same keys
do {
    var b = WordBuffer()
    type(&b, ghbdtn); type(&b, [49])
    let before = (b.word, b.tailSpaces)
    var again = WordBuffer()
    type(&again, before.0.map(\.keyCode))
    type(&again, [UInt16](repeating: 49, count: before.1))
    check(again.word == before.0 && again.tailSpaces == before.1, "replay re-records identically")
}

if failures == 0 { print("All WordBuffer tests passed") }
exit(failures == 0 ? 0 : 1)
