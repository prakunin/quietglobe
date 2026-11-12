import Testing
@testable import QuietGlobeCore

// Key codes: g=5 h=4 b=11 d=2 t=17 n=45 a=0, comma=43
private func type(_ b: inout WordBuffer, _ codes: [UInt16], shift: Bool = false, option: Bool = false) {
    for c in codes { b.keyDown(keyCode: c, shift: shift, option: option, command: false, control: false) }
}
private func codes(_ b: WordBuffer) -> [UInt16] { b.entries.map(\.keyCode) }

private let ghbdtn: [UInt16] = [5, 4, 11, 2, 17, 45]
private let vbh: [UInt16] = [9, 11, 4]
private let sp: UInt16 = 49
private let del = WordBuffer.Code.delete

@Suite struct WordBufferTests {
    @Test func appendPlainKeysAndModifiers() {
        var b = WordBuffer()
        type(&b, ghbdtn)
        #expect(codes(b) == ghbdtn)
        type(&b, [0], shift: true)
        type(&b, [0], option: true)
        #expect(b.entries[6] == .init(keyCode: 0, shift: true, option: false))
        #expect(b.entries[7] == .init(keyCode: 0, shift: false, option: true))
    }

    @Test func punctuationKeysArePartOfTheWord() {
        var b = WordBuffer()
        type(&b, [43, 47, 41, 39, 33, 30, 50])
        #expect(b.entries.count == 7)
        #expect(b.suffixStart(words: 1) == 0)
    }

    @Test func historySurvivesAcrossWords() {
        var b = WordBuffer()
        type(&b, ghbdtn + [sp] + vbh)
        #expect(codes(b) == ghbdtn + [sp] + vbh)
    }

    @Test func deleteBehaviour() {
        var b = WordBuffer()
        type(&b, ghbdtn)
        type(&b, [del])
        #expect(codes(b) == Array(ghbdtn.dropLast()))

        var e = WordBuffer()
        type(&e, [del])
        #expect(e.isEmpty)

        var c = WordBuffer()
        type(&c, ghbdtn + [sp])
        type(&c, [del])
        #expect(codes(c) == ghbdtn)
        type(&c, [sp] + vbh)
        type(&c, [del, del, del, del])
        #expect(codes(c) == ghbdtn)
        type(&c, [del])
        #expect(codes(c) == Array(ghbdtn.dropLast()))
    }

    @Test func suffixStartEmptyAndSpaces() {
        var b = WordBuffer()
        #expect(b.suffixStart(words: 1) == nil)
        type(&b, [sp, sp])
        #expect(b.suffixStart(words: 1) == nil)
    }

    @Test func suffixStartSingleSpace() {
        var s = WordBuffer()
        type(&s, ghbdtn + [sp] + vbh)
        #expect(s.suffixStart(words: 1) == 7)
        #expect(s.suffixStart(words: 2) == 0)
        #expect(s.suffixStart(words: 3) == nil)
        #expect(s.suffixStart(words: 0) == nil)
    }

    @Test func suffixStartMultipleSpaces() {
        var m = WordBuffer()
        type(&m, [0] + [sp, sp] + ghbdtn + [sp, sp, sp] + vbh) // a  ghbdtn   vbh
        #expect(m.suffixStart(words: 1) == 1 + 2 + 6 + 3)
        #expect(m.suffixStart(words: 2) == 3)
        #expect(m.suffixStart(words: 3) == 0)
        #expect(m.suffixStart(words: 4) == nil)
    }

    @Test func suffixStartTrailingAndLeadingSpaces() {
        var t = WordBuffer()
        type(&t, ghbdtn + [sp, sp] + vbh + [sp])
        #expect(t.suffixStart(words: 1) == 8)
        #expect(t.suffixStart(words: 2) == 0)
        type(&t, [sp, sp])
        #expect(t.suffixStart(words: 1) == 8)

        var l = WordBuffer()
        type(&l, [sp, sp] + ghbdtn)
        #expect(l.suffixStart(words: 1) == 2)
        #expect(l.suffixStart(words: 2) == nil)
    }

    private func assertResets(_ name: String, _ f: (inout WordBuffer) -> Void) {
        var b = WordBuffer()
        type(&b, ghbdtn + [sp] + vbh)
        f(&b)
        #expect(b.isEmpty && b.suffixStart(words: 1) == nil, "reset on \(name)")
    }

    @Test func resets() {
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
    }

    @Test func capDropsOldestEntries() {
        var b = WordBuffer()
        type(&b, [UInt16](repeating: 0, count: WordBuffer.maxKeys))
        #expect(b.entries.count == WordBuffer.maxKeys)
        type(&b, [5])
        #expect(b.entries.count == WordBuffer.maxKeys)
        #expect(b.entries.last?.keyCode == 5)
        #expect(b.entries.first?.keyCode == 0)
        type(&b, [sp, 4])
        #expect(b.entries.count == WordBuffer.maxKeys)
        #expect(b.suffixStart(words: 2) != nil)
    }

    @Test func replayRerecordsIdentically() {
        var b = WordBuffer()
        type(&b, ghbdtn + [sp] + vbh + [sp])
        var again = WordBuffer()
        type(&again, b.entries.map(\.keyCode))
        #expect(again.entries == b.entries)
    }
}
