#!/bin/bash
# How theme/tron-legacy/logo/tron-legacy-mark.svg and
# theme/tron-1982/logo/tron-1982-mark.svg were made, for the record.
#
# The references are the two films' wordmarks as Wikimedia Commons holds them:
#
#   TRON: LEGACY  File:Tron_Legacy_Logo.svg      (outlined TRON over LEGACY)
#   TRON (1982)   File:Tron_(Disney),_Logo.svg   (the filled 1982 wordmark)
#
# Both are traced the same way the ENCOM and Dillinger marks were: render
# flat, threshold, follow the edges. The Legacy reference carries a Disney
# script above the wordmark, which is the studio's mark rather than the
# film's, so the top of it is cropped away before tracing. The 1982 wordmark
# has no year in it, so "1 9 8 2" is set beneath in the desktop's own face and
# traced along with it, the way SYSTEMS sits under Dillinger.
#
#   tools/make-tron-logos.sh [out-root]      default: the repo's theme/
set -euo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)/theme}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fetch() { curl -sfL -A "Mozilla/5.0 (X11; Linux x86_64)" -o "$2" "$1"; }
fetch "https://upload.wikimedia.org/wikipedia/commons/8/84/Tron_Legacy_Logo.svg" "$TMP/legacy.svg"
fetch "https://upload.wikimedia.org/wikipedia/commons/f/f9/Tron_%28Disney%29%2C_Logo.svg" "$TMP/tron.svg"

trace() {  # <pbm> <out.svg> <fill> <note>
  python3 "$HERE/trace.py" "$1" 6 "$TMP/raw.svg"
  python3 - "$TMP/raw.svg" "$2" "$3" "$4" <<'PYEOF'
import re, sys, pathlib
raw, out, fill, note = sys.argv[1:5]
s = pathlib.Path(raw).read_text()
d = re.search(r' d="([^"]+)"', s).group(1)
view = re.search(r'viewBox="([^"]+)"', s).group(1)
pathlib.Path(out).write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}"><!-- {note} -->'
    f'<path fill="{fill}" fill-rule="evenodd" d="{d}"/></svg>')
print("wrote", out)
PYEOF
}

# ── TRON: LEGACY ─────────────────────────────────────────────────────────
# Rendered solid, then the Disney script trimmed off the top.
rsvg-convert -w 1800 -b white "$TMP/legacy.svg" -o "$TMP/legacy.png"
magick "$TMP/legacy.png" -colorspace gray -gravity north -chop 0x150 \
  -trim +repage -bordercolor white -border 20 -resize 600% -threshold 60% "$TMP/legacy.pbm"
trace "$TMP/legacy.pbm" "$ROOT/tron-legacy/logo/tron-legacy-mark.svg" "#a8ecff" \
  "TRON: LEGACY logo, after Tron: Legacy (Disney). Traced for a fan desktop theme; Tron is a trademark of Disney."

# ── TRON (1982), with the year set beneath ───────────────────────────────
rsvg-convert -w 1800 -b white "$TMP/tron.svg" -o "$TMP/tron.png"
magick "$TMP/tron.png" -colorspace gray -trim +repage "$TMP/tron-word.png"
W=$(magick identify -format %w "$TMP/tron-word.png")
# ImageMagick wants the font file, not the family name.
FONT=$(fc-match "JetBrainsMono Nerd Font" -f "%{file}")
magick -background white -fill black -font "$FONT" -pointsize 150 \
  -kerning 60 label:"1 9 8 2" -trim +repage -resize "$((W * 62 / 100))x" "$TMP/year.png"
magick -background white \
  \( "$TMP/tron-word.png" \) \( "$TMP/year.png" \) -gravity center -append \
  -bordercolor white -border 30 -colorspace gray -resize 300% \
  -threshold 92% "$TMP/tron.pbm"   # the wordmark is a gradient: take all of it, not its dark half
trace "$TMP/tron.pbm" "$ROOT/tron-1982/logo/tron-1982-mark.svg" "#a8ecff" \
  "TRON logo, after Tron (1982, Disney), with the year set beneath it. Traced for a fan desktop theme; Tron is a trademark of Disney."

# ── TRON 2.0 ─────────────────────────────────────────────────────────────
# The game's own logo is a chrome-bevelled wordmark that no clean flat copy
# of is to be had, and a bevel would not survive tracing anyway. Its letters
# sit in the same angular family as the first film's, so this sets the 1982
# wordmark with the version beside it, at the wordmark's own height.
TH=$(magick identify -format %h "$TMP/tron-word.png")
magick -background white -fill black -font "$FONT" -pointsize 400 \
  -kerning 10 label:"2.0" -trim +repage -resize "x$((TH * 78 / 100))" "$TMP/ver.png"
magick -background white \
  \( "$TMP/tron-word.png" \) \( -size "$((TH / 4))x10" xc:white \) \( "$TMP/ver.png" \) \
  -gravity south +append \
  -bordercolor white -border 30 -colorspace gray -resize 300% \
  -threshold 92% "$TMP/t20.pbm"
trace "$TMP/t20.pbm" "$ROOT/tron-2-0/logo/tron-2-0-mark.svg" "#a8ecff" \
  "TRON 2.0 title, after the game (Disney/Monolith): the 1982 wordmark with the version set beside it. Traced for a fan desktop theme; Tron is a trademark of Disney."

# ── TRON: UPRISING ───────────────────────────────────────────────────────
# The series has no wordmark of its own: its title card is the Legacy mark
# with UPRISING set under it, so that is how this is built. The LEGACY line
# is cropped off the bottom of the Legacy render and the series name set in
# its place, the same way the year sits under the 1982 wordmark.
magick "$TMP/legacy.png" -colorspace gray -gravity north -chop 0x150 -trim +repage "$TMP/legacy-word.png"
LH=$(magick identify -format %h "$TMP/legacy-word.png")
LW=$(magick identify -format %w "$TMP/legacy-word.png")
magick "$TMP/legacy-word.png" -gravity south -chop "0x$((LH * 22 / 100))" +repage "$TMP/tron-only.png"
magick -background white -fill black -font "$FONT" -pointsize 150 \
  -kerning 70 label:"U P R I S I N G" -trim +repage -resize "$((LW * 70 / 100))x" "$TMP/series.png"
magick -background white \
  \( "$TMP/tron-only.png" \) \( "$TMP/series.png" \) -gravity center -append \
  -bordercolor white -border 30 -colorspace gray -resize 300% -threshold 60% "$TMP/uprising.pbm"
trace "$TMP/uprising.pbm" "$ROOT/tron-uprising/logo/tron-uprising-mark.svg" "#a8ecff" \
  "TRON: UPRISING title, after the series (Disney): the Legacy wordmark with the series name set beneath, as its title card has it. Traced for a fan desktop theme; Tron is a trademark of Disney."
