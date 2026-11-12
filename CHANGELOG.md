# Changelog

All notable changes to QuietGlobe will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-11-12

### Added

- Fn+Esc retypes the last word in the other keyboard layout.
- Pressing Esc again while still holding Fn converts the previous word too (a series, until Fn is released).
- Menu toggle for Fn+Esc.

### Changed

- Globe switches the layout on key-up, and only if no other key was pressed while it was held.
- The one-line installer builds the fork from source (no prebuilt binaries).
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
