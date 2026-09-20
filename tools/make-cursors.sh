#!/bin/bash
# Build one cursor theme per desktop theme, in that theme's colours.
#
# Each is Adwaita's geometry recoloured (see cursor/build.sh): the body takes
# the theme's bright accent, the halo its accent, and the outline a very dark
# tint of the same hue rather than flat black, so the cursor sits in the
# theme instead of on top of it.
#
#   tools/make-cursors.sh <out-root> [theme ...]
#
# Writes <out-root>/<Theme>-Cursor for each. Needs xcur2png, xorg-xcursorgen
# and imagemagick; takes a minute or so per theme.
set -euo pipefail
OUT=${1:?usage: make-cursors.sh <out-root> [theme ...]}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
shift || true
THEMES=("$@")
(( ${#THEMES[@]} )) || THEMES=(tron-legacy clu tron-1982 tron-uprising dillinger-systems)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

for theme in "${THEMES[@]}"; do
  pal=$REPO/theme/$theme/encom.json
  [[ -f $pal ]] || { echo "no palette for $theme" >&2; continue; }
  read -r name dark body halo < <(python3 - "$pal" "$theme" <<'PYEOF'
import colorsys, json, sys
palette = json.load(open(sys.argv[1]))
theme = sys.argv[2]
accent, bright = palette["accent"], palette["accentHi"]


def hsl(hexcolour):
    h = hexcolour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)


def hexof(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "#%02x%02x%02x" % tuple(round(v * 255) for v in (r, g, b))


# The outline: the accent's hue held at the lightness the cyan cursor's
# outline was drawn at, so every theme's cursor has the same weight.
h, _, s = hsl(accent)
print("-".join(p.capitalize() for p in theme.split("-")) + "-Cursor",
      hexof(h, 0.055, min(0.85, s + 0.2)), bright, accent)
PYEOF
)
  echo ":: $theme -> $name  body $body  halo $halo  outline $dark"
  bash "$REPO/cursor/build.sh" "$TMP/work" "$OUT/$name" "$name" "$dark" "$body" "$halo" | tail -1
done
