#!/bin/bash
# ENCOM OS-12 for Omarchy: a Tron: Legacy desktop.
#
#   ./install.sh               install or update everything
#   ./install.sh --dry-run     show what would happen, change nothing
#   ./install.sh --no-plymouth skip the boot splash (it needs sudo)
#   ./install.sh --no-wallpaper keep a still wallpaper instead of the live Boardroom
#
# Every file this changes is copied first into
# ~/.local/state/omarchy-encom-os-12/backup-<time>/, and uninstall.sh uses
# that record to put things back. Running it again is safe.

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
DRY=0
PLYMOUTH=ask
WALLPAPER=yes
for arg in "$@"; do
  case $arg in
    --dry-run) DRY=1 ;;
    --no-wallpaper) WALLPAPER=no ;;
    --no-plymouth) PLYMOUTH=no ;;
    --plymouth) PLYMOUTH=yes ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

CFG=$HOME/.config
OMA=$CFG/omarchy
BOARDROOM=$HOME/.local/share/encom-boardroom
LIGHTCYCLES=$HOME/.local/share/encom-lightcycles
STATE=$HOME/.local/state/omarchy-encom-os-12
BACKUP=$STATE/backup-$(date +%Y%m%d-%H%M%S)
USER_ID=${USER:-$(id -un)}

say()  { printf '\e[36m::\e[0m %s\n' "$*"; }
warn() { printf '\e[33m!!\e[0m %s\n' "$*" >&2; }
run()  { if (( DRY )); then printf '   would run: %s\n' "$*"; else "$@"; fi; }

# Copy a file or directory into place, backing up whatever was there first.
put() {
  local src=$1 dst=$2
  if (( DRY )); then printf '   would install: %s\n' "${dst/#$HOME/\~}"; return; fi
  if [[ -e $dst ]]; then
    mkdir -p "$BACKUP/$(dirname "${dst#$HOME/}")"
    cp -a "$dst" "$BACKUP/${dst#$HOME/}"
    echo "${dst#$HOME/}" >> "$BACKUP/files"
  else
    mkdir -p "$(dirname "$dst")"
    echo "${dst#$HOME/}" >> "$BACKUP/created"
  fi
  rm -rf "$dst"
  cp -a "$src" "$dst"
}

# Replace one of this project's own directories (nothing of the user's lives
# there, so no backup: the Boardroom alone holds a 127 MB database).
put_own() {
  local src=$1 dst=$2
  if (( DRY )); then printf '   would install: %s\n' "${dst/#$HOME/\~}"; return; fi
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  cp -a "$src" "$dst"
}

# Append a block between marker comments, once.
add_block() {
  local file=$1 marker=$2 body=$3 comment=${4:-#}
  if [[ -f $file ]] && grep -qF -- "$comment >>> $marker" "$file"; then return; fi
  if (( DRY )); then printf '   would add block to: %s\n' "${file/#$HOME/\~}"; return; fi
  if [[ -f $file ]]; then
    mkdir -p "$BACKUP/$(dirname "${file#$HOME/}")"
    cp -a "$file" "$BACKUP/${file#$HOME/}"
    echo "${file#$HOME/}" >> "$BACKUP/files"
  fi
  mkdir -p "$(dirname "$file")"
  printf '\n%s >>> %s (added by omarchy-encom-os-12; uninstall.sh removes it)\n%s\n%s <<< %s\n' \
    "$comment" "$marker" "$body" "$comment" "$marker" >> "$file"
}

# ── Preflight ──────────────────────────────────────────────────────────────
command -v omarchy >/dev/null || { echo "This is for Omarchy (https://omarchy.org)." >&2; exit 1; }
missing=()
for cmd in python3 magick rsvg-convert chromium git curl gunzip; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
  echo "Missing: ${missing[*]}. Install them first (omarchy pkg add ...)." >&2
  exit 1
fi
(( DRY )) || { mkdir -p "$BACKUP"; echo "$REPO" > "$BACKUP/source"; }
say "Installing ENCOM OS-12$( (( DRY )) && echo ' (dry run)')"

# ── Theme ──────────────────────────────────────────────────────────────────
say "Theme: colours, shell styling, wallpapers, logo, boot splash art"
put_own "$REPO/theme/encom-os-12" "$OMA/themes/encom-os-12"

# ── Boardroom screensaver / monitor ───────────────────────────────────────
say "Boardroom: fetching Rob Scanlon's encom-boardroom (MIT) at the pinned revision"
REV=$(cat "$REPO/boardroom/UPSTREAM_REV")
if (( ! DRY )); then
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  git clone -q https://github.com/arscan/encom-boardroom "$TMP/upstream-src"
  git -C "$TMP/upstream-src" checkout -q "$REV"
  mkdir -p "$TMP/build/upstream"
  git -C "$TMP/upstream-src" archive "$REV" index.html css images js build | tar -x -C "$TMP/build/upstream"
  echo "$REV" > "$TMP/build/upstream/UPSTREAM_REV"
  sed -n '/^### License/,$p' "$TMP/upstream-src/README.md" > "$TMP/build/upstream/LICENSE"
  cp "$REPO"/boardroom/{server.py,wallpaper.py,checks.py,icons.py,patch.py,encom-local.js,encom-local.css,UPSTREAM_REV} "$TMP/build/"
  mkdir -p "$TMP/build/geo" "$TMP/build/assets"
  cp "$REPO/boardroom/geo/mmdb.py" "$TMP/build/geo/"
  cp "$REPO"/boardroom/assets/{disc.svg,alert-portrait.gif} "$TMP/build/assets/"
  rsvg-convert -w 256 -h 256 -o "$TMP/build/assets/disc.png" "$REPO/boardroom/assets/disc.svg"
  python3 "$TMP/build/patch.py"
  # Keep an existing location database rather than downloading 60 MB again.
  if [[ -f $BOARDROOM/geo/dbip-city-lite.mmdb ]]; then
    cp "$BOARDROOM/geo/"{dbip-city-lite.mmdb,LICENSE,VERSION} "$TMP/build/geo/" 2>/dev/null || true
  fi
  put_own "$TMP/build" "$BOARDROOM"
fi
if [[ ! -f $BOARDROOM/geo/dbip-city-lite.mmdb ]] && (( ! DRY )); then
  say "Boardroom: downloading the DB-IP City Lite location database (CC BY 4.0, ~60 MB)"
  for m in "$(date +%Y-%m)" "$(date -d 'last month' +%Y-%m)"; do
    if curl -sfL -o "$BOARDROOM/geo/dbip.mmdb.gz" "https://download.db-ip.com/free/dbip-city-lite-$m.mmdb.gz"; then
      gunzip -f "$BOARDROOM/geo/dbip.mmdb.gz"
      mv "$BOARDROOM/geo/dbip.mmdb" "$BOARDROOM/geo/dbip-city-lite.mmdb"
      echo "$m" > "$BOARDROOM/geo/VERSION"
      printf 'IP geolocation by DB-IP (https://db-ip.com), "IP to City Lite" database,\nlicensed under Creative Commons Attribution 4.0 International.\n' > "$BOARDROOM/geo/LICENSE"
      break
    fi
  done
  [[ -f $BOARDROOM/geo/dbip-city-lite.mmdb ]] || warn "Could not download the location database; connections will pin at home."
fi
put "$REPO/boardroom/bin/encom-boardroom" "$HOME/.local/bin/encom-boardroom"
put "$REPO/boardroom/bin/encom-screensaver" "$HOME/.local/bin/encom-screensaver"
put "$REPO/boardroom/bin/encom-wallpaper" "$HOME/.local/bin/encom-wallpaper"

# ── Light Cycles screensaver ──────────────────────────────────────────────
say "Light Cycles: the 3-on-3 arena, with three.js r71 (MIT) at a pinned version"
read -r THREE_VER THREE_SHA < "$REPO/lightcycles/THREE_VERSION"
if (( ! DRY )); then
  mkdir -p "$TMP/lc/app"
  curl -sfL -o "$TMP/lc/app/three.min.js" "https://cdn.jsdelivr.net/npm/three@$THREE_VER/three.min.js"
  echo "$THREE_SHA  $TMP/lc/app/three.min.js" | sha256sum -c --quiet - \
    || { echo "three.js download did not match its checksum" >&2; exit 1; }
  cp "$REPO"/lightcycles/{index.html,encom-arena.js,encom-game.js} "$TMP/lc/app/"
  put_own "$TMP/lc" "$LIGHTCYCLES"
fi

# ── Branding: fastfetch logo and screensaver banner from the ENCOM mark ──
say "Terminal: fastfetch readout and ASCII logo"
if (( ! DRY )); then
  LOGO=$OMA/themes/encom-os-12/logo
  python3 "$LOGO/ascii.py" "$LOGO/encom-mark.svg" 50 "I N T E R N A T I O N A L   ·   O S - 1 2" > "$TMP/encom.txt"
  python3 "$LOGO/ascii.py" "$LOGO/encom-mark.svg" 72 "I N T E R N A T I O N A L" > "$TMP/screensaver.txt"
  put "$TMP/encom.txt" "$OMA/branding/encom.txt"
  put "$TMP/screensaver.txt" "$OMA/branding/screensaver.txt"
fi
put "$REPO/fastfetch/config.jsonc" "$CFG/fastfetch/config.jsonc"
add_block "$CFG/foot/foot.ini" encom-os-12 "$(cat "$REPO/terminal/foot-encom.ini")" "#"

# ── Bar widgets ────────────────────────────────────────────────────────────
say "Bar: ENCOM ident and telemetry gauges"
put "$REPO/bar/modules/encom-ident.qml" "$OMA/bar/modules/encom-ident.qml"
put "$REPO/bar/modules/encom-telemetry.qml" "$OMA/bar/modules/encom-telemetry.qml"
put "$REPO/bar/scripts/encom-telemetry" "$OMA/bar/scripts/encom-telemetry"

# ── HUD ────────────────────────────────────────────────────────────────────
say "HUD: desktop panels, boot cascade, alerts, screensaver trigger"
put_own "$REPO/hud" "$OMA/plugins/encom.hud"
run omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
run omarchy plugin enable encom.hud >/dev/null

# ── Workspace nodes and chamfered launcher (clones of Omarchy's own) ─────
say "Shell: workspace nodes and the chamfered launcher"
if [[ ! -d $OMA/plugins/$USER_ID.workspaces ]]; then run omarchy plugin clone omarchy.workspaces >/dev/null; fi
put "$REPO/shell/workspaces/Workspaces.qml" "$OMA/plugins/$USER_ID.workspaces/Workspaces.qml"
if [[ ! -d $OMA/plugins/$USER_ID.menu ]]; then run omarchy plugin clone omarchy.menu >/dev/null; fi
put "$REPO/shell/menu/encom-chamfer-patch.py" "$OMA/plugins/$USER_ID.menu/encom-chamfer-patch.py"
run python3 "$OMA/plugins/$USER_ID.menu/encom-chamfer-patch.py" >/dev/null
# Make the clone menu-only. As a bar widget too, Omarchy counts it as off
# whenever it is not on the bar -- and the ENCOM ident already opens the menu,
# so a second menu button is not wanted there. Menu-only, it is enabled as a
# plain plugin instead.
if (( ! DRY )); then
  python3 - "$OMA/plugins/$USER_ID.menu/manifest.json" <<'PYEOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["kinds"] = [k for k in m.get("kinds", []) if k != "bar-widget"]
m.get("entryPoints", {}).pop("barWidget", None); m.pop("barWidget", None)
json.dump(m, open(p, "w"), indent=2); open(p, "a").write("\n")
PYEOF2
fi
run omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
run omarchy plugin enable "$USER_ID.menu" >/dev/null

# Bar layout: ENCOM ident and workspace nodes on the left, gauges first on
# the right. Everything else in your layout is left where it is.
if (( DRY )); then
  echo "   would update the bar layout in ~/.config/omarchy/shell.json"
else
  [[ -f $OMA/shell.json ]] || cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" "$OMA/shell.json"
  mkdir -p "$BACKUP/.config/omarchy"; cp -a "$OMA/shell.json" "$BACKUP/.config/omarchy/shell.json"
  echo ".config/omarchy/shell.json" >> "$BACKUP/files"
  python3 - "$OMA/shell.json" "$USER_ID" <<'PYEOF'
import json, sys
path, user = sys.argv[1], sys.argv[2]
c = json.load(open(path))
layout = c.setdefault("bar", {}).setdefault("layout", {})
ids = lambda sec: [e.get("id") for e in layout.get(sec, [])]
drop = {"omarchy.menu", "omarchy.workspaces", f"{user}.workspaces", "encom-ident"}
# The launcher clone is also a bar widget, and enabling plugins can add it to
# the layout; the ENCOM ident already opens the menu, so keep it out.
for sec in list(layout):
    layout[sec] = [e for e in layout[sec] if e.get("id") != f"{user}.menu"]
left = [e for e in layout.get("left", []) if e.get("id") not in drop]
layout["left"] = [{"id": "encom-ident", "type": "qml"}, {"id": f"{user}.workspaces"}] + left
if "encom-telemetry" not in ids("right"):
    layout["right"] = [{"id": "encom-telemetry", "type": "qml"}] + layout.get("right", [])
json.dump(c, open(path, "w"), indent=2); open(path, "a").write("\n")
PYEOF
fi

# ── Lock screen: disc wars behind the password field ─────────────────────
# A clone of Omarchy's lock with one added scene; Service.qml (the password
# and fingerprint handling) stays Omarchy's own. encom-lock.hook refreshes the
# clone from omarchy.lock after every Omarchy update.
say "Lock screen: disc wars (Omarchy's lock, with the scene added)"
if [[ ! -d $OMA/plugins/$USER_ID.lock ]]; then run omarchy plugin clone omarchy.lock >/dev/null; fi
put "$REPO/lock/DiscWars.qml" "$OMA/plugins/$USER_ID.lock/DiscWars.qml"
put "$REPO/lock/poses.js" "$OMA/plugins/$USER_ID.lock/poses.js"
put "$REPO/lock/encom-lock-patch.py" "$OMA/plugins/$USER_ID.lock/encom-lock-patch.py"
put "$REPO/hooks/encom-lock.hook" "$OMA/hooks/post-update.d/encom-lock.hook"
if (( ! DRY )); then
  rm -f "$OMA/plugins/$USER_ID.lock/.upstream-sha256"       # force a refresh now
  bash "$OMA/hooks/post-update.d/encom-lock.hook"
fi

# ── Hyprland: square corners, rez/derezz animations, cursor ──────────────
say "Hyprland: square corners, materialize/derezz animations, cursor"
put "$REPO/hypr/encom.lua" "$CFG/hypr/encom.lua"
add_block "$CFG/hypr/looknfeel.lua" encom-os-12 'require("hypr.encom")' "--"

# ── Cursor ─────────────────────────────────────────────────────────────────
say "Cursor: Encom-Cyan (recoloured from Adwaita)"
if ! command -v xcur2png >/dev/null || ! command -v xcursorgen >/dev/null; then
  run omarchy pkg add xcur2png xorg-xcursorgen
fi
if (( ! DRY )); then
  bash "$REPO/cursor/build.sh" "$TMP/cursor-work" "$TMP/Encom-Cyan" | tail -1
  put_own "$TMP/Encom-Cyan" "$HOME/.local/share/icons/Encom-Cyan"
  gsettings set org.gnome.desktop.interface cursor-theme Encom-Cyan 2>/dev/null || true
  for v in 3 4; do
    f=$CFG/gtk-$v.0/settings.ini
    mkdir -p "$(dirname "$f")"
    [[ -f $f ]] && { mkdir -p "$BACKUP/.config/gtk-$v.0"; cp -a "$f" "$BACKUP/.config/gtk-$v.0/"; echo ".config/gtk-$v.0/settings.ini" >> "$BACKUP/files"; }
    grep -q '^\[Settings\]' "$f" 2>/dev/null || echo '[Settings]' >> "$f"
    if grep -q '^gtk-cursor-theme-name' "$f"; then
      sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Encom-Cyan/' "$f"
    else
      echo 'gtk-cursor-theme-name=Encom-Cyan' >> "$f"
    fi
  done
fi

# ── Screensaver: Light Cycles replaces Omarchy's ttfx screensaver ────────
say "Screensaver: Light Cycles on idle (Omarchy's ttfx screensaver switched off)"
run omarchy-toggle screensaver-off on

# ── Live wallpaper: the Boardroom on the desktop layer ───────────────────
put "$REPO/boardroom/systemd/encom-boardroom-server.service" "$CFG/systemd/user/encom-boardroom-server.service"
put "$REPO/boardroom/systemd/encom-wallpaper.service" "$CFG/systemd/user/encom-wallpaper.service"
run systemctl --user daemon-reload
if [[ $WALLPAPER == yes ]]; then
  say "Wallpaper: the live Boardroom (WebKitGTK on the layer shell)"
  need=()
  for pkg in gtk-layer-shell webkit2gtk-4.1 python-gobject python-cairo; do
    pacman -Q "$pkg" >/dev/null 2>&1 || need+=("$pkg")
  done
  (( ${#need[@]} )) && run omarchy pkg add "${need[@]}"
  run systemctl --user enable encom-wallpaper.service
  run systemctl --user restart encom-wallpaper.service
else
  say "Wallpaper: live Boardroom skipped; turn it on later with: encom-wallpaper on"
fi

# ── Boot splash hook ──────────────────────────────────────────────────────
put "$REPO/hooks/encom-plymouth.hook" "$OMA/hooks/post-update.d/encom-plymouth.hook"

# ── Apply ──────────────────────────────────────────────────────────────────
say "Applying the theme"
run omarchy theme set encom-os-12 >/dev/null
run omarchy theme bg set "$HOME/.local/state/omarchy/current/theme/backgrounds/01-grid-horizon.png" >/dev/null
run hyprctl reload >/dev/null
if (( ! DRY )) && [[ -n $(hyprctl configerrors 2>/dev/null | tr -d '[:space:]') ]]; then
  warn "Hyprland reports config errors:"; hyprctl configerrors
fi
run omarchy restart shell >/dev/null 2>&1 || true

if [[ $PLYMOUTH == ask && -t 0 && $DRY == 0 ]]; then
  read -r -p "Install the ENCOM boot splash now? It needs sudo and rebuilds the initramfs. [y/N] " a
  [[ $a == [yY]* ]] && PLYMOUTH=yes || PLYMOUTH=no
fi
if [[ $PLYMOUTH == yes ]]; then
  say "Boot splash"
  run "$OMA/hooks/post-update.d/encom-plymouth.hook"
else
  say "Boot splash skipped; install it later with: omarchy plymouth set-by-theme encom-os-12"
fi

(( DRY )) || say "Done. Backups of anything replaced: ${BACKUP/#$HOME/\~}"
say "Open terminals pick up the new look in new windows. Log out and back in for the cursor everywhere."
