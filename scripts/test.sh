#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# With several files, top-level code is only allowed in a file named main.swift.
cp "$ROOT/Tests/WordBufferTests.swift" "$OUT/main.swift"
swiftc -o "$OUT/wordbuffer-tests" \
  "$ROOT/Sources/WordBuffer.swift" \
  "$OUT/main.swift"
"$OUT/wordbuffer-tests"
