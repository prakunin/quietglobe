# Contributing to QuietGlobe

Thanks for taking the time to contribute.

## Before you start

- Search existing issues, discussions, and pull requests.
- For large changes, open an issue first so we can agree on the approach.
- Keep the app focused: quiet, instant input source switching on macOS.

## Where to ask

- **Bug reports and concrete feature requests:** [open an issue](https://github.com/prakunin/quietglobe/issues).
- **Ideas, questions, and general feedback:** also via issues.
- **Security issues:** do not open a public issue; see [SECURITY.md](SECURITY.md).

## Development

Requirements:

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`); Swift 6 toolchain (Xcode 16 / matching CLT)

Build:

```bash
./scripts/build.sh
open QuietGlobe.app
```

The build script creates a Universal 2 app and signs it ad-hoc by default. For development, use a stable signing identity so macOS keeps the Accessibility permission across rebuilds:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

macOS ties Accessibility permission to the code signature. Ad-hoc and unsigned builds change identity on every rebuild, so the toggle may need to be enabled again.

## Releasing

1. Move the notes from `[Unreleased]` to a new `## [X.Y.Z] - date` section in `CHANGELOG.md` and commit it on `main`.
2. Run `scripts/release.sh X.Y.Z --push`. It bumps `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist` (if needed), commits, creates the annotated tag `vX.Y.Z` and pushes it. Without `--push` it only prints the push command.
3. The `Release` workflow (`.github/workflows/release.yml`) tests, builds, signs with the persistent self-signed certificate, and publishes `QuietGlobe.zip`, `QuietGlobe.zip.sha256` and `appcast.xml` to a GitHub release. Installed apps pick it up through Sparkle.

Repository secrets: `MACOS_CERT_P12_BASE64` and `MACOS_CERT_PASSWORD` (code-signing certificate `QuietGlobe Self-Signed (prakunin)`), `SPARKLE_ED_PRIVATE_KEY` (Sparkle EdDSA key; the public key is `SUPublicEDKey` in `Info.plist`). Back up the certificate and both keys in the maintainer's password manager: losing the certificate or the EdDSA key means existing installs cannot update seamlessly and need a manual reinstall (and an Accessibility re-grant).

Sparkle is pinned in `Package.swift` (exact version) and `Package.resolved`, fetched by SwiftPM as a binary artifact (its `sign_update` is used by `make-appcast.sh`); the release build is not hardened-runtime on purpose (library validation would reject Sparkle).

## Project structure

- `Package.swift` — SwiftPM manifest (library `QuietGlobeCore`, executable `QuietGlobe`, tests; Sparkle dependency).
- `Sources/QuietGlobeCore/` — pure logic, no AppKit: `WordBuffer` and `KeyStateMachine` (Globe/Fn/Fn+Esc state machine).
- `Sources/QuietGlobe/main.swift` — app entry point (`NSApplication`, `.accessory`).
- `Sources/QuietGlobe/AppDelegate.swift` — menu bar status item, menu, TCC permission, login item.
- `Sources/QuietGlobe/EventTapController.swift` — global event tap; a thin adapter from CGEvent to `KeyStateMachine`.
- `Sources/QuietGlobe/InputSourceSwitcher.swift` — Text Input Sources layout switching.
- `Sources/QuietGlobe/Retyper.swift`, `Log.swift` — retyping and the `os.Logger` wrapper.
- `Tests/QuietGlobeCoreTests/` — unit tests (Swift Testing), run with `scripts/test.sh`.
- `Resources/Info.plist` — bundle metadata (`LSUIElement`, macOS 13+).
- `scripts/build.sh` — universal SwiftPM build (with Sparkle) + app bundle + signing; `test.sh` (`swift test`), `make-appcast.sh`, `release-notes.sh`, `release.sh` — release tooling.
- `docs/assets/` — screenshots, before/after images, and the demo GIF used by the READMEs.

## How it works

1. `AppDelegate` creates an `NSStatusItem` and its menu.
2. `EventTapController` installs a `CGEventTap` for key down/up events.
3. When the Globe key (key code 179) is pressed, the tap consumes it and calls `InputSourceSwitcher`.
4. `InputSourceSwitcher` finds enabled keyboard layouts with `TISCreateInputSourceList` and selects the next one with `TISSelectInputSource`.
5. Because the Globe key event never reaches the system text input switcher, macOS does not show the ABC/Russian HUD.

Accessibility permission is required for the event tap. `SMAppService` handles launch at login.

## Pull requests

- Keep changes small and focused.
- Follow the existing Swift style.
- Test on at least one physical Mac with Accessibility permission.
- Update `CHANGELOG.md` and the README(s) if behavior or installation changes.
- Do not commit build artifacts, `DerivedData`, `.build`, or `*.app` bundles.

## Reporting bugs

Please include:

- macOS version (`sw_vers`).
- Mac model and chip (Apple Silicon or Intel).
- Keyboard layouts enabled (for example ABC and Russian).
- Whether the Globe key is set to “Change Input Source”.
- Steps to reproduce and, if possible, a screen recording.

## Security

Do not open public issues for security problems. See [SECURITY.md](SECURITY.md).
