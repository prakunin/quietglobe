# Changelog

All notable changes to QuietGlobe will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
