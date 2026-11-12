#!/usr/bin/env bash
# Installs QuietGlobe (prakunin fork, with Fn+Esc).
# Default: downloads the latest signed release from GitHub (no Xcode needed).
# Env: VERSION (e.g. 1.1.1; default latest), INSTALL_DIR (default /Applications
#      or ~/Applications), NO_OPEN=1 (do not launch),
#      FROM_SOURCE=1 (build from source instead; needs Xcode Command Line Tools;
#      REF = branch/tag, default main).
set -euo pipefail

REPO="prakunin/quietglobe"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "${FROM_SOURCE:-}" ]; then
  REF="${REF:-main}"
  if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required to build from source. Run: xcode-select --install" >&2
    exit 1
  fi

  echo "Downloading ${REPO}@${REF}..."
  curl -fsSL --retry 3 "https://codeload.github.com/${REPO}/tar.gz/${REF}" | tar -xz -C "$tmp"
  src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"

  echo "Building..."
  (cd "$src" && OUT_DIR="$tmp/out" bash scripts/build.sh 2>&1 | grep -v "libswiftCompatibilityPacks" | tail -1)
  app="$tmp/out/QuietGlobe.app"
else
  if [ -n "${VERSION:-}" ]; then
    base="https://github.com/${REPO}/releases/download/v${VERSION#v}"
  else
    base="https://github.com/${REPO}/releases/latest/download"
  fi

  echo "Downloading QuietGlobe ${VERSION:-(latest)}..."
  mkdir "$tmp/dl"
  curl -fsSL --retry 3 -o "$tmp/dl/QuietGlobe.zip" "$base/QuietGlobe.zip"
  curl -fsSL --retry 3 -o "$tmp/dl/QuietGlobe.zip.sha256" "$base/QuietGlobe.zip.sha256"
  (cd "$tmp/dl" && shasum -a 256 -c QuietGlobe.zip.sha256)

  mkdir "$tmp/out"
  ditto -x -k "$tmp/dl/QuietGlobe.zip" "$tmp/out"
  app="$tmp/out/QuietGlobe.app"
fi
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
if [ -n "${FROM_SOURCE:-}" ]; then
  echo "   This build is ad-hoc signed: after every rebuild remove the old QuietGlobe entry (−)"
  echo "   and enable it again, macOS treats each build as a new app."
else
  echo "   Release builds keep this permission across updates. Coming from 1.0.x or a source"
  echo "   build? Remove the old QuietGlobe entry (−) and enable the new one once."
fi
echo "2. Set the Globe key to \"Change Input Source\" in System Settings → Keyboard."
echo "3. Press 🌐. Type a word in the wrong layout and press Fn+Esc."
echo "QuietGlobe updates itself: menu → Check for Updates…"

if [ -z "${NO_OPEN:-}" ]; then
  open "$dest/QuietGlobe.app"
fi
