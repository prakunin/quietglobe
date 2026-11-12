import AppKit
import ApplicationServices
import ServiceManagement

/// Menu bar agent for QuietGlobe.
///
/// Responsibilities:
/// - owns the `NSStatusItem` and its menu;
/// - owns the `EventTapController` lifecycle;
/// - handles Accessibility permission and login-item state.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = InputSourceSwitcher()
    private lazy var eventTap = EventTapController(
        switcher: switcher,
        isRetypeEnabled: { AppDelegate.retypeEnabled }
    )

    /// Fn+Esc retype toggle, persisted; on by default.
    static var retypeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "retypeEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "retypeEnabled") }
    }

    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var retypeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var accessItem: NSMenuItem!
    private var permissionTimer: Timer?
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        isEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true

        setupStatusItem()
        updateUI()

        guard isEnabled else { return }

        if AXIsProcessTrusted() {
            eventTap.start()
        } else {
            requestAccessibility()
            startPermissionPolling()
        }

        updateUI()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "QuietGlobe")
            button.image?.isTemplate = true
            button.toolTip = "QuietGlobe"
        }

        let menu = NSMenu()

        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        retypeItem = NSMenuItem(title: "Fn+Esc: retype last word", action: #selector(toggleRetype), keyEquivalent: "")
        retypeItem.target = self
        menu.addItem(retypeItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        accessItem = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About QuietGlobe", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit QuietGlobe", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateUI() {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            statusItem.button?.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "QuietGlobe needs Accessibility permission"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.alphaValue = 1.0
            statusItem.button?.toolTip = "QuietGlobe — Accessibility permission required"
            enabledItem.state = .off
            enabledItem.isEnabled = false
            accessItem.title = "Grant Accessibility…"
            accessItem.isEnabled = true
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: "QuietGlobe"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.alphaValue = isEnabled ? 1.0 : 0.45
            statusItem.button?.toolTip = isEnabled ? "QuietGlobe — On" : "QuietGlobe — Off"
            enabledItem.isEnabled = true
            enabledItem.state = isEnabled ? .on : .off
            accessItem.title = "Accessibility Settings…"
            accessItem.isEnabled = true
        }

        retypeItem.state = Self.retypeEnabled ? .on : .off
        updateLoginItem()
    }

    private func updateLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.isEnabled = true
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            startPermissionPolling()
            return
        }

        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: "enabled")

        if isEnabled {
            if !eventTap.start() {
                log("failed to start event tap")
            }
        } else {
            eventTap.stop()
        }

        updateUI()
    }

    @objc private func toggleRetype() {
        Self.retypeEnabled.toggle()
        retypeItem.state = Self.retypeEnabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }

            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            log("login item error: \(error.localizedDescription)")
            showAlert(
                title: "Launch at Login",
                message: "Could not update the login item: \(error.localizedDescription)"
            )
        }

        updateLoginItem()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "QuietGlobe"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        alert.informativeText = """
        Instant, HUD-free input source switching for macOS.
        Version \(version)

        https://github.com/prakunin/quietglobe
        Fork of github.com/Nishikinodzuki/quietglobe
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            guard AXIsProcessTrusted() else { return }

            timer.invalidate()
            self.permissionTimer = nil

            if self.isEnabled {
                self.eventTap.start()
            }
            self.updateUI()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
