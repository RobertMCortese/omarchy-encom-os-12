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
