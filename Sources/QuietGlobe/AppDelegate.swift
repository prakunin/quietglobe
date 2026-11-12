import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle

/// Menu bar agent for QuietGlobe.
///
/// Responsibilities:
/// - owns the `NSStatusItem` and its menu;
/// - owns the `EventTapController` lifecycle;
/// - handles Accessibility permission and login-item state.
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private let switcher = InputSourceSwitcher()
    private lazy var eventTap = EventTapController(
        switcher: switcher,
        isRetypeEnabled: { AppDelegate.retypeEnabled },
        isGlobeEnabled: { AppDelegate.globeEnabled }
    )

    /// Globe layout switching toggle, persisted; on by default.
    static var globeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "globeEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "globeEnabled") }
    }

    /// Migrates the old master switch `enabled` into the two feature toggles.
    private static func migrateSettings() {
        let d = UserDefaults.standard
        guard let old = d.object(forKey: "enabled") as? Bool else { return }
        if d.object(forKey: "globeEnabled") == nil { d.set(old, forKey: "globeEnabled") }
        if !old, d.object(forKey: "retypeEnabled") == nil { d.set(false, forKey: "retypeEnabled") }
        d.removeObject(forKey: "enabled")
    }

    /// The event tap is needed while at least one feature is on.
    private var anyFeatureEnabled: Bool { Self.globeEnabled || Self.retypeEnabled }

    /// Fn+Esc retype toggle, persisted; on by default.
    static var retypeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "retypeEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "retypeEnabled") }
    }

    /// Sparkle updater: checks daily (Info.plist) and on "Check for Updates…".
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    private var statusItem: NSStatusItem!
    private var globeItem: NSMenuItem!
    private var retypeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var accessItem: NSMenuItem!
    private var autoUpdateItem: NSMenuItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = updaterController // start Sparkle
        Self.migrateSettings()

        setupStatusItem()
        updateUI()

        guard anyFeatureEnabled else { return }

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

        globeItem = NSMenuItem(title: "🌐 Switch layout without popup", action: #selector(toggleGlobe), keyEquivalent: "")
        globeItem.target = self
        menu.addItem(globeItem)

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

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        autoUpdateItem = NSMenuItem(
            title: "Check for Updates Automatically",
            action: #selector(toggleAutoUpdate),
            keyEquivalent: ""
        )
        autoUpdateItem.target = self
        menu.addItem(autoUpdateItem)

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
            globeItem.isEnabled = false
            retypeItem.isEnabled = false
            accessItem.title = "Grant Accessibility…"
            accessItem.isEnabled = true
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: "QuietGlobe"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.alphaValue = anyFeatureEnabled ? 1.0 : 0.45
            statusItem.button?.toolTip = anyFeatureEnabled ? "QuietGlobe — On" : "QuietGlobe — Off"
            globeItem.isEnabled = true
            retypeItem.isEnabled = true
            accessItem.title = "Accessibility Settings…"
            accessItem.isEnabled = true
        }

        globeItem.state = Self.globeEnabled ? .on : .off
        retypeItem.state = Self.retypeEnabled ? .on : .off
        autoUpdateItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        updateLoginItem()
    }

    private func updateLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.isEnabled = true
    }

    // MARK: - Actions

    @objc private func toggleAutoUpdate() {
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates.toggle()
        autoUpdateItem.state = updater.automaticallyChecksForUpdates ? .on : .off
    }

    @objc private func toggleGlobe() {
        toggleFeature { Self.globeEnabled.toggle() }
    }

    @objc private func toggleRetype() {
        toggleFeature { Self.retypeEnabled.toggle() }
    }

    /// Flips one feature, then starts or stops the event tap to match.
    private func toggleFeature(_ flip: () -> Void) {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            startPermissionPolling()
            return
        }

        flip()
        syncEventTap()
        updateUI()
    }

    private func syncEventTap() {
        if anyFeatureEnabled {
            if !eventTap.isRunning, !eventTap.start() {
                log("failed to start event tap")
            }
        } else {
            eventTap.stop()
        }
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

    // MARK: - SPUStandardUserDriverDelegate

    /// Background (LSUIElement) app: tell Sparkle we handle scheduled reminders
    /// (we just let it show the alert immediately), so it does not warn.
    var supportsGentleScheduledUpdateReminders: Bool { true }

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

            self.syncEventTap()
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
