# Changelog

All notable changes to QuietGlobe will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.2] - 2026-11-22

### Fixed

- Removing QuietGlobe from the Accessibility list with "−" no longer freezes input, not even for a moment. Once a second QuietGlobe checks that it may still tap events: it creates a throw-away probe tap, which macOS refuses after "−" although `AXIsProcessTrusted()` still says yes. On a refusal it removes its event tap before input stalls. The input-stall guard stays as a backstop. When the tap cannot be created again, the menu offers "Grant Accessibility…".

### Changed

- Releases are built on Apple silicon GitHub runners again (the app stays universal).

## [1.3.1] - 2026-11-20

### Fixed

- After sleep or a locked screen QuietGlobe could switch itself off (⚠️ in the menu bar), as if the Accessibility permission were gone. The key that wakes the Mac or is typed at the lock screen never reaches the user session, and the input-stall guard took that for a dead event tap. The guard now pauses while the Mac sleeps, the display is off, the screen is locked or another user is active, and for 10 seconds after.
- If the guard does stop the event tap while the permission is still there, the menu offers "Resume QuietGlobe" instead of "Grant Accessibility…" (which resets the permission), and the tap comes back by itself after wake or unlock.

### Changed

- README rewritten around the three features (silent Globe switching, Fn+Esc, layout indicator), with menu bar screenshots, a Troubleshooting section and an accurate Privacy section.
- QuietGlobe is no longer presented as a fork: the About window, README and installer no longer mention the original project (its copyright stays in LICENSE, as MIT requires).

## [1.3.0] - 2026-11-20

### Added

- The menu bar icon shows the current layout (`RU`, `A`, `PL`…) like the system input menu and updates on any switch, so the system input menu can be hidden. "Show Current Layout in Menu Bar" toggle (on by default) brings back the 🌐 globe.
- Enabled layouts are listed at the top of the menu; click one to switch.
- On first launch the icon is placed next to the clock, where the system input menu usually is; ⌘-drag it elsewhere and macOS keeps your place.
- "Hide System Input Menu" toggle hides the system layout icon (same setting as System Settings → Keyboard → Text Input).

### Fixed

- Removing QuietGlobe from the Accessibility list while it was running froze all keyboard and mouse input until the app was killed. QuietGlobe now notices that input is stuck (the hardware sees keys and mouse, the session gets nothing, even for a single click) and removes its event tap within about 2 seconds. It never re-enables a tap the system disabled without permission; after a stall it retries once after 3 seconds and stays off (⚠️ in the menu bar) if input stalls again.
- "Grant Accessibility…" adds QuietGlobe back to the Accessibility list after it was removed with "−": it resets QuietGlobe's Accessibility record and relaunches the app, which shows the system prompt (macOS shows it only once per process).
- Menu items that need Accessibility are really disabled while it is missing.

## [1.2.0] - 2026-11-12

### Added

- Homebrew cask in the `prakunin/tap` tap, bumped automatically by the release workflow.
- "Check for Updates Automatically" menu toggle (Sparkle's automatic update check).

### Changed

- Fn+Esc beeps when there is nothing to convert (empty buffer, no more words in the series, secure input).

## [1.1.2] - 2026-11-12

### Changed

- The "Enabled" menu item is replaced by two independent toggles: "🌐 Switch layout without popup" and "Fn+Esc: retype last word". With Globe switching off, macOS handles the key natively. The old setting is migrated automatically.
- Built with Swift Package Manager; Sparkle comes in as a package dependency.

### Internal

- Globe/Fn/Esc key handling moved into a pure `KeyStateMachine` and covered by Swift Testing tests (46 in total).
- CI builds and tests every push and pull request; GitHub Actions are pinned by commit SHA.

## [1.1.1] - 2026-11-12

### Added

- Fn+Esc retypes the last word in the other keyboard layout.
- Pressing Esc again while still holding Fn converts the previous word too (a series, until Fn is released).
- Menu toggle for Fn+Esc.
- Prebuilt signed releases published by GitHub Actions (stable self-signed certificate, so the Accessibility grant survives updates).
- In-app updates with Sparkle 2: daily automatic check and menu → Check for Updates…

### Changed

- Globe switches the layout on key-up, and only if no other key was pressed while it was held.
- The one-line installer downloads the signed prebuilt release (checksum verified); building from source is `FROM_SOURCE=1`.
- Bundle identifier is now `io.github.prakunin.quietglobe` (settings and Launch at Login need to be set again once).
- Retype waits for the layout-change system notification instead of polling.

## [1.0.0] - 2026-11-01

### Added

- Globe key interception with a global event tap.
- Instant input source switching via the public Text Input Sources API.
- Suppression of the macOS ABC/Russian input source indicator (HUD).
- Menu bar app with onboarding and launch-at-login.
- Universal 2 build for Apple Silicon and Intel.
- One-line installer and manual zip distribution.
- English and Russian documentation.
