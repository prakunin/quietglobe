#!/usr/bin/env bash
# Prints the body of the "## [VERSION]" section of CHANGELOG.md.
set -euo pipefail

VERSION="${1:?usage: release-notes.sh VERSION}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

notes="$(awk -v v="$VERSION" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' "$ROOT/CHANGELOG.md")"

# Trim leading/trailing blank lines.
notes="$(printf '%s\n' "$notes" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md has no section (or an empty one) for [$VERSION]" >&2
  exit 1
fi
printf '%s\n' "$notes"
