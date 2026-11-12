# QuietGlobe

**Disable the system-wide macOS input source indicator — the ABC/Russian popup — for any keyboard layout. Switch input sources instantly with the 🌐 Globe key: no popup, no HUD, no delay.**

> **Fork of [Nishikinodzuki/quietglobe](https://github.com/Nishikinodzuki/quietglobe)** adding **Fn+Esc — retype the last word(s) in the other layout** (like Punto Switcher's “convert last word”). See [Fn+Esc](#fnesc-retype-in-the-other-layout). This fork has no prebuilt release — [build from source](#build-from-source).

**English** · [Русский](README.ru.md) · [Install](#install) · [Feedback](#feedback) · [FAQ](#faq)

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square)](https://swift.org)
[![MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

![QuietGlobe before and after: the macOS ABC/Russian input source popup on the left, instant switching without a popup on the right](docs/assets/quietglobe-before-after.png)

## The problem

On macOS, when you press the 🌐 Globe (Fn) key to switch between keyboard layouts — **ABC ↔ Russian**, **ABC ↔ German**, or any other enabled pair — the system can show a floating **input source indicator** with the layout names. It is system-wide: the popup appears for any enabled keyboard layout, not only ABC/Russian.

It is not just cosmetic:

- it covers your text;
- it stays on screen until you type or it times out;
- it interrupts typing, presentations, screen recordings, and demos.

If you searched for **“disable ABC/Russian popup macOS”**, **“macOS input source indicator”**, **“Globe key HUD”**, **“language switcher popup”**, or **“hide input source HUD”**, this is the popup you mean.

![macOS input source indicator showing ABC and Russian](docs/assets/macos-input-source-indicator.png)

## The fix

**QuietGlobe** intercepts the Globe key, switches the keyboard layout instantly with the public macOS Text Input Sources API, and suppresses the HUD. You keep the same key, but the switch is silent.

- Works with **every enabled keyboard layout** — ABC, Russian, German, French, and more.
- No popup. No delay.
- Native Swift, no private APIs, no network, no telemetry.
- Open source (MIT).

![QuietGlobe demo: typing "Привет, мир!" with and without the input source popup](docs/assets/quietglobe-demo.gif)

## Install

### One-line installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Nishikinodzuki/quietglobe/main/install.sh | bash
```

It downloads the Universal 2 build, verifies SHA-256, installs to `/Applications` (or `~/Applications` if needed), removes quarantine, and opens QuietGlobe.

After installation, open **QuietGlobe** from `/Applications` if it is not already open — it runs in the menu bar (no Dock icon).

### Manual

Download the latest `QuietGlobe-*.zip` from [GitHub Releases](https://github.com/Nishikinodzuki/quietglobe/releases/latest), unzip it, and move `QuietGlobe.app` to `/Applications`.

## First launch

1. Open **QuietGlobe**.
2. macOS asks for **Accessibility** permission. QuietGlobe needs it to intercept the Globe key before the system HUD appears.
3. Open **System Settings → Privacy & Security → Accessibility** and enable **QuietGlobe**.
4. QuietGlobe detects the permission automatically and starts. No restart needed.

> Accessibility permission cannot be granted automatically by macOS. This is a system security requirement, not an installer limitation.

## Usage

- Press **🌐 (Globe/Fn)** to switch between your last used keyboard layouts.
- The Globe key must be configured as **“Change Input Source”** in **System Settings → Keyboard**.
- QuietGlobe lives in the menu bar. Click the 🌐 globe to:
  - **Enabled** — toggle Globe key interception.
  - **Launch at Login** — start QuietGlobe when you log in.
  - **Accessibility Settings…** — open the exact permission pane.
  - **Fn+Esc: retype last word** — toggle the retype hotkey (on by default).
  - **Quit QuietGlobe**.

The layout switches when you **release** 🌐, and only if no other key was pressed while it was held — so 🌐 still works as a modifier (Fn+Esc and friends).

## Fn+Esc: retype in the other layout

Typed `ghbdtn` while in the Latin layout? Press **Fn+Esc** → it becomes `привет` and the layout switches.

- **Fn+Esc** — deletes the last word and retypes the same keys in the other layout. Trailing spaces are kept.
- **Series:** keep holding **Fn** and press **Esc** again — the previous word is added (2 words, then 3, …). The layout switches only on the first Esc of the series. Releasing Fn ends the series.
- Press Fn+Esc again after releasing Fn to convert the last word back.
- QuietGlobe remembers **key codes, not characters**, so Shift/Option combinations (e.g. Polish ą, ę) are reproduced in the target layout.
- The remembered line resets on Return, Tab, arrows, Home/End/PgUp/PgDn, Cmd/Ctrl shortcuts, mouse clicks and app switches. Nothing is recorded while macOS secure input (password fields) is active.
- Retyping works by synthetic Backspace + key presses, so it works in Terminal too. Not supported yet: Caps Lock (retyped in lower case), dead keys / IMEs, very long lines (history is capped at 256 keys).

## Supported macOS

| macOS | Status |
|---|---|
| macOS 13 Ventura | Supported |
| macOS 14 Sonoma | Supported |
| macOS 15 Sequoia | Supported |
| macOS 26 / 27 | Supported (tested on 27.2) |

- Apple Silicon and Intel (Universal 2).
- The Globe key is available on Apple keyboards and most modern MacBook keyboards.

## FAQ

### How do I disable the ABC/Russian popup on macOS?

Install QuietGlobe, grant Accessibility permission, and keep the Globe key set to “Change Input Source”. QuietGlobe switches the layout itself and suppresses the macOS input source indicator. This works for every enabled keyboard layout, not only ABC/Russian. There is no supported macOS setting that removes this popup, which is why QuietGlobe exists.

### Why does macOS show the input source indicator?

macOS shows the indicator when the input source changes via the Globe key or a keyboard shortcut. It is meant to confirm the new layout, but it often stays on screen until you type, which interrupts typing and screen recordings.

### Does QuietGlobe work with Caps Lock or Ctrl+Space?

The first release targets the 🌐 Globe key. Caps Lock and custom shortcuts are on the roadmap. You can still switch layouts with any method — QuietGlobe only removes the popup for the Globe key.

### Why does QuietGlobe need Accessibility permission?

To intercept the Globe key before the system HUD appears, QuietGlobe uses a macOS event tap. macOS requires Accessibility permission for global keyboard event taps. QuietGlobe does not read, store, or send your keystrokes.

### Is QuietGlobe free?

Yes. QuietGlobe is free and open source under the MIT license. There are no ads, subscriptions, or analytics.

### Does QuietGlobe collect data?

No. QuietGlobe has no network access, no telemetry, and no analytics. The source code is public.

### How do I uninstall QuietGlobe?

Quit QuietGlobe, remove it from `/Applications`, and disable/remove it in **System Settings → Privacy & Security → Accessibility**.

### Does QuietGlobe work on macOS 13, 14, 15, 26, and 27?

Yes, QuietGlobe targets macOS 13 Ventura and later. It is built as a Universal 2 binary for Apple Silicon and Intel Macs.

## How it works

1. QuietGlobe registers a global event tap for the Globe key.
2. When you press 🌐, it consumes the key event before the system can show the HUD.
3. It reads the enabled keyboard layouts with `TISCreateInputSourceList`.
4. It switches to the next layout with `TISSelectInputSource`.
5. The result is an instant layout switch with no input source indicator.

QuietGlobe uses public macOS APIs: `CoreGraphics` event taps and the Carbon Text Input Sources API. No private frameworks, no kernel extensions, no keystroke logging.

## Privacy

- No network requests.
- No analytics or telemetry.
- No keystroke content is stored or transmitted. For Fn+Esc the key codes of the current line are kept in memory only (never logged, never written to disk), and are dropped on Return, clicks, app switches and in password fields.
- The source is open for review.

## Build from source

Requirements: macOS 13+, Xcode Command Line Tools.

```bash
git clone https://github.com/prakunin/quietglobe.git
cd quietglobe
./scripts/test.sh
./scripts/build.sh
open QuietGlobe.app
```

## Feedback

- **Bugs and concrete feature requests:** [GitHub Issues](https://github.com/Nishikinodzuki/quietglobe/issues)
- **Ideas and suggestions:** [GitHub Discussions → Ideas](https://github.com/Nishikinodzuki/quietglobe/discussions/categories/ideas)
- **Questions:** [GitHub Discussions → Q&A](https://github.com/Nishikinodzuki/quietglobe/discussions/categories/q-a)
- **Security issues:** report privately via [SECURITY.md](SECURITY.md).

## Contributing

Pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). If QuietGlobe helped you, star the repo — it helps other people find it.

## License

MIT © Nishikinodzuki. See [LICENSE](LICENSE).
