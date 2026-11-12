#!/usr/bin/env bash
# Writes appcast.xml (one item) for a signed release zip.
# Usage: make-appcast.sh VERSION BUILD ZIP NOTES_MD
# Env: SPARKLE_ED_PRIVATE_KEY (Sparkle ed25519 private key), OUT (default ./appcast.xml),
#      QG_SCRATCH (SwiftPM scratch dir, where sign_update lives; default outside the repo)
set -euo pipefail

VERSION="${1:?usage: make-appcast.sh VERSION BUILD ZIP NOTES_MD}"
BUILD="${2:?}"
ZIP="${3:?}"
NOTES="${4:?}"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is not set}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-appcast.xml}"
TMP_BASE="${TMPDIR:-/tmp}"
SCRATCH="${QG_SCRATCH:-${TMP_BASE%/}/quietglobe-spm}"
# sign_update ships in the Sparkle SwiftPM artifact bundle (pinned in Package.swift).
SIGN="$SCRATCH/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN" ] || (cd "$ROOT" && swift package --scratch-path "$SCRATCH" resolve >&2)
[ -x "$SIGN" ] || { echo "sign_update not found at $SIGN" >&2; exit 1; }

# The key goes through stdin only, never to disk or argv.
SIG="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN" --ed-key-file - -p "$ZIP" | tr -d '[:space:]')"
[ -n "$SIG" ] || { echo "sign_update returned no signature" >&2; exit 1; }
LENGTH="$(wc -c < "$ZIP" | tr -d '[:space:]')"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
URL="https://github.com/prakunin/quietglobe/releases/download/v${VERSION}/QuietGlobe.zip"

# Minimal markdown -> HTML: headers, bullet lists, paragraphs, **bold**, `code`.
HTML="$(awk '
  function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
  function inl(s) {
    s = esc(s)
    while (match(s, /\*\*[^*]+\*\*/)) s = substr(s, 1, RSTART-1) "<b>" substr(s, RSTART+2, RLENGTH-4) "</b>" substr(s, RSTART+RLENGTH)
    while (match(s, /`[^`]+`/)) s = substr(s, 1, RSTART-1) "<code>" substr(s, RSTART+1, RLENGTH-2) "</code>" substr(s, RSTART+RLENGTH)
    return s
  }
  function closelist() { if (inl_list) { print "</ul>"; inl_list = 0 } }
  /^#+[ \t]/ { closelist(); t = $0; sub(/^#+[ \t]+/, "", t); print "<h3>" inl(t) "</h3>"; next }
  /^[ \t]*[-*][ \t]+/ { if (!inl_list) { print "<ul>"; inl_list = 1 } t = $0; sub(/^[ \t]*[-*][ \t]+/, "", t); print "<li>" inl(t) "</li>"; next }
  /^[ \t]*$/ { closelist(); next }
  { closelist(); print "<p>" inl($0) "</p>" }
  END { closelist() }
' "$NOTES")"
# CDATA cannot contain "]]>".
HTML="${HTML//]]>/]]&gt;}"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>QuietGlobe</title>
    <link>https://github.com/prakunin/quietglobe</link>
    <description>QuietGlobe updates</description>
    <language>en</language>
    <item>
      <title>QuietGlobe ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[${HTML}]]></description>
      <enclosure url="${URL}" sparkle:edSignature="${SIG}" length="${LENGTH}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote $OUT"
