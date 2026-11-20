import Foundation

/// The system input menu (the layout icon of TextInputMenuAgent) in the menu bar.
///
/// Same setting as System Settings → Keyboard → Text Input → Edit… →
/// "Show Input menu in menu bar": `com.apple.TextInputMenu` / `visible`.
/// TextInputMenuAgent watches this preference and shows or hides its icon
/// right away, no restart needed. Not a documented API: if a future macOS
/// ignores it, the toggle simply has no effect.
enum SystemInputMenu {
    private static let domain = "com.apple.TextInputMenu" as CFString
    private static let key = "visible" as CFString

    static var isVisible: Bool {
        get {
            CFPreferencesAppSynchronize(domain)
            // Missing value: the system default, which is "shown".
            return CFPreferencesCopyAppValue(key, domain) as? Bool ?? true
        }
        set {
            CFPreferencesSetAppValue(key, newValue as CFBoolean, domain)
            CFPreferencesAppSynchronize(domain)
            log("system input menu \(newValue ? "shown" : "hidden")")
        }
    }
}
