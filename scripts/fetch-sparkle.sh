#!/usr/bin/env bash
# Downloads the pinned Sparkle release into vendor/ (idempotent).
# Provides vendor/Sparkle.framework and vendor/bin/sign_update.
set -euo pipefail

SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
STAMP="$VENDOR/.sparkle-version"

if [ "$(cat "$STAMP" 2>/dev/null || true)" = "$SPARKLE_VERSION" ] \
  && [ -d "$VENDOR/Sparkle.framework" ] && [ -x "$VENDOR/bin/sign_update" ]; then
  exit 0
fi

# Work outside the repo (SMB shares add extended attributes that break codesign).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching Sparkle ${SPARKLE_VERSION}..."
curl -fsSL --retry 3 -o "$tmp/sparkle.tar.xz" "$SPARKLE_URL"

actual="$(shasum -a 256 "$tmp/sparkle.tar.xz" | awk '{print $1}')"
if [ "$actual" != "$SPARKLE_SHA256" ]; then
  echo "Sparkle checksum mismatch: expected $SPARKLE_SHA256, got $actual" >&2
  exit 1
fi

mkdir "$tmp/x"
tar -xJf "$tmp/sparkle.tar.xz" -C "$tmp/x" ./Sparkle.framework ./bin/sign_update

rm -rf "$VENDOR"
mkdir -p "$VENDOR/bin"
ditto "$tmp/x/Sparkle.framework" "$VENDOR/Sparkle.framework"
cp "$tmp/x/bin/sign_update" "$VENDOR/bin/sign_update"
chmod +x "$VENDOR/bin/sign_update"
echo "$SPARKLE_VERSION" > "$STAMP"
echo "Sparkle ${SPARKLE_VERSION} ready in vendor/"
