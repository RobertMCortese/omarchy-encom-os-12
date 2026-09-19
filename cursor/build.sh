#!/bin/bash
# Build the Encom-Cyan cursor theme by recolouring Adwaita's shapes.
#
# Hand-drawn cursors look amateurish; Adwaita's geometry is already good, so
# this only remaps its greyscale ramp to cyan and lays a soft cyan halo under
# each frame. Blur radius scales with frame size so a 24px cursor stays crisp.
#
# Needs: xcur2png, xorg-xcursorgen, imagemagick.
#   build.sh <workdir> <outdir>

set -euo pipefail

SRC=/usr/share/icons/Adwaita/cursors
WORK=${1:?usage: build.sh <workdir> <outdir>}
OUT=${2:?usage: build.sh <workdir> <outdir>}

FILL_DARK='#02141b'   # the outline, tinted rather than pure black
FILL_LIGHT='#a8ecff'  # the body
HALO='#6fc3df'

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT/cursors"

recolour() {
  local png=$1 w blur
  w=$(identify -format '%w' "$png")
  blur=$(awk -v w="$w" 'BEGIN { printf "%.2f", w / 38.0 }')
  # +level-colors maps black->first, white->second. (-level-colors does the
  # opposite, which leaves the body untinted and only the halo cyan.)
  magick "$png" -channel RGB +level-colors "$FILL_DARK","$FILL_LIGHT" +channel \
    \( +clone -channel A -blur 0x"$blur" -level 0%,55% +channel -fill "$HALO" -colorize 100 \) \
    -compose DstOver -composite "$png"
}

built=0
failed=0

# Real cursor files become recoloured cursors.
while IFS= read -r -d '' cur; do
  name=$(basename "$cur")
  dir="$WORK/$name"
  mkdir -p "$dir"

  # xcur2png writes its .conf to the current directory, not to -d.
  if ! ( cd "$dir" && xcur2png -d "$dir" "$cur" >/dev/null 2>&1 ); then
    echo "  SKIP (decompile failed): $name" >&2
    failed=$((failed + 1))
    continue
  fi

  shopt -s nullglob
  frames=("$dir"/*.png)
  shopt -u nullglob
  if (( ${#frames[@]} == 0 )); then
    echo "  SKIP (no frames): $name" >&2
    failed=$((failed + 1))
    continue
  fi

  for png in "${frames[@]}"; do recolour "$png"; done

  # The conf holds absolute paths to the PNGs, which were recoloured in place.
  conf="$dir/$name.conf"
  if [[ ! -f $conf ]]; then
    shopt -s nullglob
    confs=("$dir"/*.conf)
    shopt -u nullglob
    if (( ${#confs[@]} == 0 )); then
      echo "  SKIP (no conf): $name" >&2
      failed=$((failed + 1))
      continue
    fi
    conf=${confs[0]}
  fi

  if xcursorgen "$conf" "$OUT/cursors/$name" 2>/dev/null; then
    built=$((built + 1))
  else
    echo "  SKIP (xcursorgen failed): $name" >&2
    failed=$((failed + 1))
  fi
done < <(find "$SRC" -maxdepth 1 -type f -print0)

# Symlinks are the X11 cursor-name aliases; copy them verbatim.
links=0
while IFS= read -r -d '' link; do
  name=$(basename "$link")
  target=$(readlink "$link")
  if [[ -e $OUT/cursors/$target ]]; then
    ln -sf "$target" "$OUT/cursors/$name"
    links=$((links + 1))
  fi
done < <(find "$SRC" -maxdepth 1 -type l -print0)

cat > "$OUT/index.theme" <<'EOF'
[Icon Theme]
Name=Encom-Cyan
Comment=ENCOM OS-12 cursor - Adwaita geometry, Tron cyan with a soft halo
Inherits=Adwaita
EOF

cat > "$OUT/cursor.theme" <<'EOF'
[Icon Theme]
Name=Encom-Cyan
Inherits=Adwaita
EOF

echo "built=$built failed=$failed links=$links"
