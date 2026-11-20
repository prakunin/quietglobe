import AppKit
import ApplicationServices
import Carbon
import QuietGlobeCore
import ServiceManagement
import Sparkle

/// Menu bar agent for QuietGlobe.
///
/// Responsibilities:
/// - owns the `NSStatusItem` and its menu;
/// - owns the `EventTapController` lifecycle;
/// - handles Accessibility permission and login-item state.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
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

    /// Menu bar shows the current layout (like the system input menu) instead
    /// of the globe; persisted; on by default.
    static var showLayout: Bool {
        get { UserDefaults.standard.object(forKey: "showLayout") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showLayout") }
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
    private var showLayoutItem: NSMenuItem!
    private var hideSystemMenuItem: NSMenuItem!
    /// Enabled layouts at the top of the menu, rebuilt each time the menu opens.
    private var layoutItems: [NSMenuItem] = []
    private var permissionTimer: Timer?
    /// Set when the event tap failed (permission removed, input stalled).
    /// The tap comes back only after the permission was seen missing and
    /// granted again, or after a deliberate user action in the menu.
    private var tapSuspended = false
    /// When the tap was last reinstalled after an input stall (systemUptime).
    private var lastStallRetry: TimeInterval?
    private static let requestAccessibilityArgument = "--request-accessibility"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = updaterController // start Sparkle
        Self.migrateSettings()

        eventTap.onTapFailed = { [weak self] failure in
            self?.handleTapFailure(failure)
        }

        setupStatusItem()
        observeLayoutChanges()
        updateUI()

        // Relaunched by "Grant Accessibility…": ask even if both features are off,
        // otherwise the entry never comes back to the list.
        if CommandLine.arguments.contains(Self.requestAccessibilityArgument), !AXIsProcessTrusted() {
            requestAccessibility()
            startPermissionPolling()
        }

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

    /// Name under which macOS remembers the status item's place in the menu bar.
    private static let statusItemName = "QuietGlobe"

    private func setupStatusItem() {
        // First launch: stand next to the clock, where the system input menu
        // usually is (macOS appends new items on the far left). The value is the
        // distance from the right screen edge; after the user ⌘-drags the icon,
        // macOS stores the new place under the same key and we keep it.
        let positionKey = "NSStatusItem Preferred Position \(Self.statusItemName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            // 300 lands next to Bluetooth / Control Center; a smaller value
            // (200) made macOS hide the item behind the system ones.
            UserDefaults.standard.set(300, forKey: positionKey)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.statusItemName

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "QuietGlobe")
            button.image?.isTemplate = true
            button.toolTip = "QuietGlobe"
        }

        let menu = NSMenu()
        menu.delegate = self
        // Honour isEnabled set in updateUI (feature toggles are off without permission).
        menu.autoenablesItems = false

        globeItem = NSMenuItem(title: "🌐 Switch layout without popup", action: #selector(toggleGlobe), keyEquivalent: "")
        globeItem.target = self
        menu.addItem(globeItem)

        retypeItem = NSMenuItem(title: "Fn+Esc: retype last word", action: #selector(toggleRetype), keyEquivalent: "")
        retypeItem.target = self
        menu.addItem(retypeItem)

        menu.addItem(.separator())

        showLayoutItem = NSMenuItem(title: "Show Current Layout in Menu Bar", action: #selector(toggleShowLayout), keyEquivalent: "")
        showLayoutItem.target = self
        menu.addItem(showLayoutItem)

        hideSystemMenuItem = NSMenuItem(title: "Hide System Input Menu", action: #selector(toggleSystemInputMenu), keyEquivalent: "")
        hideSystemMenuItem.target = self
        menu.addItem(hideSystemMenuItem)

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
        let trusted = AXIsProcessTrusted() && !tapSuspended

        if !trusted {
            statusItem.button?.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "QuietGlobe needs Accessibility permission"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.alphaValue = 1.0
            statusItem.button?.toolTip = tapSuspended
                ? "QuietGlobe — paused: Accessibility permission was removed"
                : "QuietGlobe — Accessibility permission required"
            globeItem.isEnabled = false
            retypeItem.isEnabled = false
            accessItem.title = "Grant Accessibility…"
            accessItem.isEnabled = true
        } else {
            updateStatusIcon()
            globeItem.isEnabled = true
            retypeItem.isEnabled = true
            accessItem.title = "Accessibility Settings…"
            accessItem.isEnabled = true
        }

        globeItem.state = Self.globeEnabled ? .on : .off
        retypeItem.state = Self.retypeEnabled ? .on : .off
        showLayoutItem.state = Self.showLayout ? .on : .off
        hideSystemMenuItem.state = SystemInputMenu.isVisible ? .off : .on
        autoUpdateItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        updateLoginItem()
    }

    /// Redraws the icon unless the warning must stay (no permission, tap suspended).
    private func refreshStatusIcon() {
        if AXIsProcessTrusted(), !tapSuspended {
            updateStatusIcon()
        } else {
            updateUI()
        }
    }

    /// Globe or current-layout badge; dimmed while both features are off.
    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let state = anyFeatureEnabled ? "On" : "Off"

        if Self.showLayout, let layout = switcher.currentLayout() {
            button.image = LayoutBadge.image(label: LayoutLabel.short(id: layout.id, language: layout.language))
            button.image?.accessibilityDescription = layout.name
            button.toolTip = "\(layout.name) — QuietGlobe \(state)"
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "QuietGlobe")
            button.image?.isTemplate = true
            button.toolTip = "QuietGlobe — \(state)"
        }
        button.alphaValue = anyFeatureEnabled ? 1.0 : 0.45
    }

    /// Any layout switch (Globe, menu, shortcut, another app) refreshes the badge.
    private func observeLayoutChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusIcon()
        }
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the layout list at the top of the menu with a check on the active one.
    func menuNeedsUpdate(_ menu: NSMenu) {
        hideSystemMenuItem.state = SystemInputMenu.isVisible ? .off : .on

        layoutItems.forEach(menu.removeItem)
        layoutItems = []

        let layouts = switcher.enabledLayouts()
        guard layouts.count > 1 else { return }

        let currentID = switcher.currentInputSourceID()
        for (index, layout) in layouts.enumerated() {
            let item = NSMenuItem(title: layout.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.id
            item.state = layout.id == currentID ? .on : .off
            menu.insertItem(item, at: index)
            layoutItems.append(item)
        }
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: layouts.count)
        layoutItems.append(separator)
    }

    /// Permission gone: wait for a real grant. Input stalled: one automatic
    /// retry after a pause (a wake-up key that never reached the session looks
    /// the same as a dead tap); a second stall soon after means the permission
    /// is really gone, so stay off until the user acts.
    private func handleTapFailure(_ failure: EventTapController.Failure) {
        tapSuspended = true
        let now = ProcessInfo.processInfo.systemUptime

        if failure == .inputStalled, lastStallRetry.map({ now - $0 > 15 }) ?? true {
            lastStallRetry = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.tapSuspended, AXIsProcessTrusted() else { return }
                log("retrying the event tap after an input stall")
                self.tapSuspended = false
                self.syncEventTap()
                self.updateUI()
            }
        }

        updateUI()
        startPermissionPolling()
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

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        switcher.selectLayout(id: id)
        refreshStatusIcon()
    }

    @objc private func toggleSystemInputMenu() {
        SystemInputMenu.isVisible.toggle()
        hideSystemMenuItem.state = SystemInputMenu.isVisible ? .off : .on
    }

    @objc private func toggleShowLayout() {
        Self.showLayout.toggle()
        updateUI()
    }

    @objc private func toggleGlobe() {
        toggleFeature { Self.globeEnabled.toggle() }
    }

    @objc private func toggleRetype() {
        toggleFeature { Self.retypeEnabled.toggle() }
    }

    /// Flips one feature, then starts or stops the event tap to match.
    private func toggleFeature(_ flip: () -> Void) {
        guard AXIsProcessTrusted(), !tapSuspended else {
            openAccessibilitySettings()
            return
        }
        lastStallRetry = nil

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
        // The system prompt is what (re)adds QuietGlobe to the Accessibility list.
        // After the entry was removed with "−", macOS does not add it again, and
        // it shows the prompt only once per process: reset our TCC record and
        // relaunch, the new process asks at launch.
        if !AXIsProcessTrusted() || tapSuspended {
            resetAccessibilityRecord()
            relaunch()
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "QuietGlobe"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        alert.informativeText = """
        Keyboard layouts for macOS: Globe switching without the popup,
        Fn+Esc retyping, the current layout in the menu bar.
        Version \(version)

        https://github.com/prakunin/quietglobe
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

    /// Starts a new copy of the app after this one quits.
    private func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, so the new one is not a second instance.
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\" --args \"$3\"",
                             "relaunch", String(ProcessInfo.processInfo.processIdentifier), path,
                             Self.requestAccessibilityArgument]
        do {
            try process.run()
            log("relaunching to ask for Accessibility again")
            NSApp.terminate(nil)
        } catch {
            log("relaunch failed: \(error.localizedDescription)")
            requestAccessibility()
            startPermissionPolling()
        }
    }

    /// `tccutil reset Accessibility <our bundle id>`: forgets our entry, so the
    /// next prompt adds QuietGlobe to the list again.
    private func resetAccessibilityRecord() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            log("tccutil reset Accessibility: exit \(process.terminationStatus)")
        } catch {
            log("tccutil reset failed: \(error.localizedDescription)")
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            guard AXIsProcessTrusted() else {
                // The permission is really gone now: the next grant is a fresh one.
                if self.tapSuspended {
                    self.tapSuspended = false
                    log("Accessibility permission is gone; waiting for a new grant")
                }
                return
            }
            guard !self.tapSuspended else { return }

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
