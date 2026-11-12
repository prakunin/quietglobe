#!/usr/bin/env bash
# Builds QuietGlobe.app (universal arm64+x86_64, with Sparkle) and signs it.
# Env: CODESIGN_IDENTITY (default "-" = ad-hoc), CODESIGN_KEYCHAIN (optional),
#      OUT_DIR (where to put QuietGlobe.app; default: repo root),
#      QG_SCRATCH (SwiftPM scratch dir; default outside the repo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT}"
IDENTITY="${CODESIGN_IDENTITY:--}"

# TMPDIR ends with "/" on macOS; keep "//" out of the scratch path.
TMP_BASE="${TMPDIR:-/tmp}"
SCRATCH="${QG_SCRATCH:-${TMP_BASE%/}/quietglobe-spm}"

# Build and sign outside the repo: on an SMB share codesign fails with
# "resource fork, Finder information, or similar detritus not allowed".
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/QuietGlobe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Universal binary in one SwiftPM invocation (works with Command Line Tools only).
SWIFT_ARGS=(-c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH")
(cd "$ROOT" && swift build "${SWIFT_ARGS[@]}" --product QuietGlobe)
BIN_DIR="$(cd "$ROOT" && swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
cp "$BIN_DIR/QuietGlobe" "$APP/Contents/MacOS/QuietGlobe"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sparkle.framework from the SwiftPM binary artifact (ditto keeps the Versions/Current symlinks).
FW="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_FW="$SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FW" ] || { echo "Sparkle.framework not found in $SPARKLE_FW" >&2; exit 1; }
ditto --norsrc --noextattr "$SPARKLE_FW" "$FW"
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
