#!/usr/bin/env bash
# Builds QuietGlobe.app (universal arm64+x86_64, with Sparkle) and signs it.
# Env: CODESIGN_IDENTITY (default "-" = ad-hoc), CODESIGN_KEYCHAIN (optional),
#      OUT_DIR (where to put QuietGlobe.app; default: repo root).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT}"
IDENTITY="${CODESIGN_IDENTITY:--}"

bash "$ROOT/scripts/fetch-sparkle.sh"

# Build and sign outside the repo: on an SMB share codesign fails with
# "resource fork, Finder information, or similar detritus not allowed".
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/QuietGlobe.app"
mkdir -p "$WORK/arm64" "$WORK/x86_64" \
  "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

build_arch() {
  local arch="$1"
  local out="$2"
  swiftc -O \
    -target "${arch}-apple-macos13.0" \
    "$ROOT"/Sources/*.swift \
    -o "$out" \
    -F "$ROOT/vendor" \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -framework Carbon \
    -framework CoreGraphics \
    -framework AppKit \
    -framework ApplicationServices \
    -framework ServiceManagement
}

build_arch arm64 "$WORK/arm64/QuietGlobe"
build_arch x86_64 "$WORK/x86_64/QuietGlobe"

lipo -create \
  "$WORK/arm64/QuietGlobe" \
  "$WORK/x86_64/QuietGlobe" \
  -output "$APP/Contents/MacOS/QuietGlobe"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sparkle.framework (ditto keeps the Versions/Current symlinks).
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto --norsrc --noextattr "$ROOT/vendor/Sparkle.framework" "$FW"
# XPC services are only needed by sandboxed apps; QuietGlobe is not sandboxed.
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

# Sign inside-out, without --deep. No hardened runtime: library validation
# would reject Sparkle.framework (it has no Team ID in a self-signed setup).
sign() {
  local args=(--force --sign "$IDENTITY")
  if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
  codesign "${args[@]}" "$@"
}

sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"

codesign --verify --deep --strict "$APP"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/QuietGlobe.app"
ditto --norsrc --noextattr "$APP" "$OUT_DIR/QuietGlobe.app"

echo "Built $OUT_DIR/QuietGlobe.app"
