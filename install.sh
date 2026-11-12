#!/usr/bin/env bash
# Installs QuietGlobe (prakunin fork, with Fn+Esc) by building it from source.
# Requires Xcode Command Line Tools (swiftc). Env: REF (branch/tag, default main),
# INSTALL_DIR (default /Applications or ~/Applications), NO_OPEN=1 (do not launch).
set -euo pipefail

REPO="prakunin/quietglobe"
REF="${REF:-main}"

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${REPO}@${REF}..."
curl -fsSL --retry 3 "https://codeload.github.com/${REPO}/tar.gz/${REF}" | tar -xz -C "$tmp"
src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"

echo "Building..."
(cd "$src" && bash scripts/build.sh 2>&1 | grep -v "libswiftCompatibilityPacks" | tail -1)
app="$src/QuietGlobe.app"
test -d "$app"

if [ -n "${INSTALL_DIR:-}" ]; then
  dest="$INSTALL_DIR"
  mkdir -p "$dest"
elif [ -w /Applications ]; then
  dest="/Applications"
else
  dest="$HOME/Applications"
  mkdir -p "$dest"
fi

if [ -z "${INSTALL_DIR:-}" ]; then
  osascript -e 'tell application "QuietGlobe" to quit' >/dev/null 2>&1 || true
  pkill -x QuietGlobe 2>/dev/null || true
  sleep 1
fi

rm -rf "$dest/QuietGlobe.app"
ditto "$app" "$dest/QuietGlobe.app"

echo "Installed: $dest/QuietGlobe.app"
echo
echo "Next:"
echo "1. Grant Accessibility in System Settings → Privacy & Security → Accessibility."
echo "   After a reinstall/update, remove the old QuietGlobe entry (−) and enable it again:"
echo "   the app is ad-hoc signed, so macOS treats every build as a new app."
echo "2. Set the Globe key to \"Change Input Source\" in System Settings → Keyboard."
echo "3. Press 🌐. Type a word in the wrong layout and press Fn+Esc."

if [ -z "${NO_OPEN:-}" ]; then
  open "$dest/QuietGlobe.app"
fi
