#!/usr/bin/env bash
# Prepares a release: bumps Info.plist, commits, creates an annotated tag vX.Y.Z.
# Usage: release.sh X.Y.Z [--push]   (CI builds and publishes on tag push)
set -euo pipefail

VERSION="${1:?usage: release.sh X.Y.Z [--push]}"
PUSH="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must look like X.Y.Z" >&2; exit 1; }
[ -z "$PUSH" ] || [ "$PUSH" = "--push" ] || { echo "unknown option: $PUSH" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PLIST="Resources/Info.plist"
PB=/usr/libexec/PlistBuddy
TAG="v$VERSION"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "must be on branch main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree is not clean" >&2; exit 1; }
bash scripts/release-notes.sh "$VERSION" >/dev/null
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists" >&2; exit 1
fi

current="$($PB -c 'Print :CFBundleShortVersionString' "$PLIST")"
build="$($PB -c 'Print :CFBundleVersion' "$PLIST")"
if [ "$current" != "$VERSION" ]; then
  build=$((build + 1))
  $PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  $PB -c "Set :CFBundleVersion $build" "$PLIST"
fi

if [ -n "$(git status --porcelain)" ]; then
  git add "$PLIST"
  git commit -m "Release $VERSION"
fi
git tag -a "$TAG" -m "QuietGlobe $VERSION"
echo "Tagged $TAG (CFBundleVersion $build)."

if [ "$PUSH" = "--push" ]; then
  git push origin main "$TAG"
else
  echo "Publish with: git push origin main $TAG"
fi
