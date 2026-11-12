#!/usr/bin/env bash
# Runs the unit tests (Swift Testing) of QuietGlobeCore.
# Env: QG_SCRATCH (SwiftPM scratch dir; default outside the repo: SMB shares are slow).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# TMPDIR ends with "/" on macOS; a "//" in the path breaks the Swift Testing macro plugin lookup.
TMP_BASE="${TMPDIR:-/tmp}"
SCRATCH="${QG_SCRATCH:-${TMP_BASE%/}/quietglobe-spm}"

cd "$ROOT"
swift test --scratch-path "$SCRATCH"
