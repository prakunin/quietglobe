import Testing
@testable import QuietGlobeCore

@Suite struct LayoutLabelTests {
    @Test func abcIsLetterA() {
        #expect(LayoutLabel.short(id: "com.apple.keylayout.ABC", language: "en") == "A")
    }

    @Test func russianIsRU() {
        #expect(LayoutLabel.short(id: "com.apple.keylayout.RussianWin", language: "ru") == "RU")
        #expect(LayoutLabel.short(id: "com.apple.keylayout.Russian", language: "ru") == "RU")
    }

    @Test func ukrainianIsUK() {
        #expect(LayoutLabel.short(id: "com.apple.keylayout.Ukrainian-PC", language: "uk") == "UK")
    }

    @Test func otherLanguagesUseUppercasedCode() {
        #expect(LayoutLabel.short(id: "com.apple.keylayout.PolishPro", language: "pl") == "PL")
        #expect(LayoutLabel.short(id: "com.apple.keylayout.German", language: "de") == "DE")
    }

    @Test func regionSuffixIsDropped() {
        #expect(LayoutLabel.short(id: "x.layout", language: "sr_Cyrl") == "SR")
        #expect(LayoutLabel.short(id: "x.layout", language: "pt-BR") == "PT")
    }

    @Test func noLanguageFallsBackToIDTail() {
        #expect(LayoutLabel.short(id: "com.apple.keylayout.Dvorak", language: nil) == "DV")
        #expect(LayoutLabel.short(id: "com.apple.keylayout.Dvorak", language: "") == "DV")
    }
}
