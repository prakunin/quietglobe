/// Short menu bar label for a keyboard layout, in the spirit of the system
/// input menu: "A" for ABC, otherwise the language code ("RU", "PL", …).
public enum LayoutLabel {
    /// Layouts with a fixed label (Latin layouts that share the "en" language).
    private static let specialIDs: [String: String] = [
        "com.apple.keylayout.ABC": "A",
        "com.apple.keylayout.US": "US",
        "com.apple.keylayout.British": "GB",
        "com.apple.keylayout.Australian": "AU",
        "com.apple.keylayout.Canadian": "CA"
    ]

    /// - Parameters:
    ///   - id: input source id, e.g. `com.apple.keylayout.RussianWin`.
    ///   - language: primary language of the layout (`kTISPropertyInputSourceLanguages[0]`).
    public static func short(id: String, language: String?) -> String {
        if let special = specialIDs[id] { return special }
        if let language, !language.isEmpty {
            let base = String(language.split(whereSeparator: { $0 == "_" || $0 == "-" }).first ?? "")
            if !base.isEmpty { return String(base.prefix(3)).uppercased() }
        }
        // No language: use the tail of the id, e.g. "...keylayout.Dvorak" -> "DV".
        let tail = id.split(separator: ".").last.map(String.init) ?? id
        let letters = tail.filter { $0.isLetter }
        return letters.isEmpty ? "?" : String(letters.prefix(2)).uppercased()
    }
}
