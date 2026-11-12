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
- Xcode Command Line Tools (`xcode-select --install`)

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

## Project structure

- `Sources/main.swift` — app entry point (`NSApplication`, `.accessory`).
- `Sources/AppDelegate.swift` — menu bar status item, menu, TCC permission, login item.
- `Sources/EventTapController.swift` — global event tap and Globe key handling.
- `Sources/InputSourceSwitcher.swift` — Text Input Sources layout switching.
- `Sources/Log.swift` — `os.Logger` wrapper.
- `Resources/Info.plist` — bundle metadata (`LSUIElement`, macOS 13+).
- `scripts/build.sh` — universal build + signing.
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
