import Carbon
import Foundation

/// Switches between enabled keyboard layouts using the public Text Input Sources API.
///
/// The switcher prefers the previously used layout (stored in `UserDefaults`)
/// and falls back to the next enabled layout. This mirrors the "switch to the
/// previous input source" behavior most macOS users expect.
final class InputSourceSwitcher {
    private let defaults: UserDefaults
    private var lastSwitchTime = Date.distantPast
    private let debounceInterval: TimeInterval = 0.15

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Switches to the remembered layout, or to the first alternative layout.
    ///
    /// The debounce prevents duplicate events when the Globe key sends several
    /// key-down events for one physical press.
    func switchToAlternativeLayout() {
        let now = Date()
        guard now.timeIntervalSince(lastSwitchTime) >= debounceInterval else { return }
        lastSwitchTime = now

        guard let target = alternativeLayout() else { return }
        select(target)
    }

    /// Switches to the alternative layout without debounce and returns its id
    /// (nil if there is none). Used by the retyper, which needs the target id
    /// to wait until the switch has really happened. Main thread only (TIS API).
    func switchToAlternativeLayoutReportingTarget() -> String? {
        guard let target = alternativeLayout() else { return nil }
        guard select(target) else { return nil }
        return inputSourceID(target)
    }

    /// Id of the layout the next switch would select, without switching. Main thread only.
    func alternativeLayoutID() -> String? {
        alternativeLayout().flatMap { inputSourceID($0) }
    }

    /// Id of the currently active keyboard layout. Main thread only.
    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return inputSourceID(source)
    }

    /// Picks the remembered layout, else the first enabled layout that is not the current one.
    private func alternativeLayout() -> TISInputSource? {
        let layouts = enabledKeyboardLayouts()
        guard !layouts.isEmpty else {
            log("no enabled keyboard layouts")
            return nil
        }

        let currentID = currentInputSourceID()
        let rememberedID = defaults.string(forKey: "lastInputSourceID")

        let target: TISInputSource?
        if let rememberedID, rememberedID != currentID,
           let remembered = layouts.first(where: { inputSourceID($0) == rememberedID }) {
            target = remembered
        } else {
            target = layouts.first(where: { inputSourceID($0) != currentID })
        }

        if target == nil { log("no alternative layout") }
        return target
    }

    @discardableResult
    private func select(_ target: TISInputSource) -> Bool {
        let currentID = currentInputSourceID()
        let status = TISSelectInputSource(target)
        if status == noErr {
            defaults.set(currentID, forKey: "lastInputSourceID")
            log("switched \(currentID ?? "?") -> \(inputSourceID(target) ?? "?")")
            return true
        }
        log("switch failed with status \(status)")
        return false
    }

    /// Returns enabled keyboard layouts only (no input methods, emoji, etc.).
    private func enabledKeyboardLayouts() -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        guard let result = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }
        return result as? [TISInputSource] ?? []
    }

    private func inputSourceID(_ source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}
