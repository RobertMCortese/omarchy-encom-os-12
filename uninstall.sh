#!/bin/bash
# Remove ENCOM OS-12 and put back what install.sh replaced.
#
#   ./uninstall.sh              remove everything
#   ./uninstall.sh --dry-run    show what would happen
#
# Files the first install replaced are restored from its backup; files it
# created are removed. Marker blocks are cut out of looknfeel.lua and
# foot.ini. The bar layout is edited back rather than restored, so changes
# you made to it since are kept. Your Boardroom settings in
# ~/.config/encom-boardroom are left in place.

set -euo pipefail

DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1

CFG=$HOME/.config
OMA=$CFG/omarchy
STATE=$HOME/.local/state/omarchy-encom-os-12
USER_ID=${USER:-$(id -un)}

say() { printf '\e[36m::\e[0m %s\n' "$*"; }
run() { if (( DRY )); then printf '   would run: %s\n' "$*"; else "$@"; fi; }
remove() { if (( DRY )); then printf '   would remove: %s\n' "${1/#$HOME/\~}"; else rm -rf "$1"; fi; }

cut_block() {
  local file=$1 comment=$2
  [[ -f $file ]] && grep -qF -- "$comment >>> encom-os-12" "$file" || return 0
  if (( DRY )); then printf '   would remove the encom-os-12 block from %s\n' "${file/#$HOME/\~}"; return; fi
  python3 - "$file" "$comment" <<'PYEOF'
import re, sys
path, c = sys.argv[1], re.escape(sys.argv[2])
s = open(path).read()
s = re.sub(rf"\n?{c} >>> encom-os-12[^\n]*\n.*?{c} <<< encom-os-12\n?", "\n", s, flags=re.S)
open(path, "w").write(s)
PYEOF
}

# ── Switch away from the theme before removing it ─────────────────────────
if [[ $(omarchy theme current 2>/dev/null) == *"Encom"* || $(omarchy theme current 2>/dev/null) == *"Dillinger"* ]]; then
  say "Switching theme to Tokyo Night"
  run omarchy theme set tokyo-night >/dev/null
fi

# ── Screensaver back to Omarchy's own ─────────────────────────────────────
say "Screensaver: back to Omarchy's"
run omarchy-toggle screensaver-off off
remove "$HOME/.local/state/omarchy/toggles/encom-boardroom-off"
remove "$HOME/.local/state/omarchy/toggles/encom-screensaver-off"
say "Wallpaper: stopping the live Boardroom"
run systemctl --user disable --now encom-wallpaper.service encom-boardroom-server.service 2>/dev/null || true
remove "$CFG/systemd/user/encom-wallpaper.service"
remove "$CFG/systemd/user/encom-boardroom-server.service"
run systemctl --user daemon-reload
pkill -f '[e]ncom-boardroom/server.py' 2>/dev/null || true

# ── Shell: HUD, clones, bar layout ────────────────────────────────────────
say "Shell: HUD, workspace nodes, launcher, bar layout"
run omarchy plugin disable encom.hud >/dev/null 2>&1 || true
for clone in workspaces menu lock; do
  if [[ -d $OMA/plugins/$USER_ID.$clone ]]; then
    run omarchy plugin disable "$USER_ID.$clone" >/dev/null 2>&1 || true
    run omarchy plugin enable "omarchy.$clone" >/dev/null 2>&1 || true
    remove "$OMA/plugins/$USER_ID.$clone"
  fi
done
remove "$OMA/plugins/encom.hud"
if [[ -f $OMA/shell.json ]]; then
  if (( DRY )); then
    echo "   would edit the bar layout back in ~/.config/omarchy/shell.json"
  else
    python3 - "$OMA/shell.json" "$USER_ID" <<'PYEOF'
import json, sys
path, user = sys.argv[1], sys.argv[2]
c = json.load(open(path))
layout = c.get("bar", {}).get("layout", {})
for sec, entries in layout.items():
    out = []
    for e in entries:
        if e.get("id") in ("encom-ident", "encom-telemetry"):
            continue
        if e.get("id") == f"{user}.workspaces":
            e = {"id": "omarchy.workspaces"}
        out.append(e)
    layout[sec] = out
left = layout.setdefault("left", [])
if not any(e.get("id") == "omarchy.menu" for sec in layout.values() for e in sec):
    left.insert(0, {"id": "omarchy.menu"})
json.dump(c, open(path, "w"), indent=2); open(path, "a").write("\n")
PYEOF
  fi
fi
remove "$OMA/bar/modules/encom-ident.qml"
remove "$OMA/bar/modules/encom-telemetry.qml"
remove "$OMA/bar/scripts/encom-telemetry"

# ── Hyprland and terminal ─────────────────────────────────────────────────
say "Hyprland and terminal settings"
cut_block "$CFG/hypr/looknfeel.lua" "--"
remove "$CFG/hypr/encom.lua"
cut_block "$CFG/foot/foot.ini" "#"

# ── Files the first install replaced or created ───────────────────────────
first=$(ls -d "$STATE"/backup-* 2>/dev/null | sort | head -1 || true)
# Files that are ours by name are always removed, never restored.
remove "$HOME/.local/bin/encom-boardroom"
remove "$HOME/.local/bin/encom-screensaver"
remove "$HOME/.local/bin/encom-wallpaper"
remove "$HOME/.local/bin/encom-splash"
remove "$OMA/hooks/post-update.d/encom-plymouth.hook"
remove "$OMA/hooks/post-update.d/encom-lock.hook"
remove "$OMA/branding/encom.txt"
if [[ -n $first ]]; then
  say "Restoring files from ${first/#$HOME/\~}"
  managed=(.config/fastfetch/config.jsonc .config/omarchy/branding/screensaver.txt
           .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini)
  for rel in "${managed[@]}"; do
    if [[ -e $first/$rel ]]; then
      if (( DRY )); then printf '   would restore: ~/%s\n' "$rel"
      else cp -a "$first/$rel" "$HOME/$rel"; fi
    elif grep -qxF "$rel" "$first/created" 2>/dev/null; then
      remove "$HOME/$rel"
    fi
  done
fi

# ── Cursor, Boardroom, theme ──────────────────────────────────────────────
say "Cursor, Boardroom, Light Cycles and theme files"
run gsettings reset org.gnome.desktop.interface cursor-theme 2>/dev/null || true
remove "$HOME/.local/share/icons/Encom-Cyan"
remove "$HOME/.local/share/encom-boardroom"
remove "$HOME/.local/share/encom-lightcycles"
remove "$HOME/.cache/encom-boardroom"
for t in "$OMA"/themes/encom-*/ "$OMA"/themes/dillinger-*/; do
  [[ -d $t ]] && remove "${t%/}"
done

run hyprctl reload >/dev/null
run omarchy restart shell >/dev/null 2>&1 || true

say "Done. The boot splash is unchanged; to restore Omarchy's, run:"
echo "   omarchy plymouth set --refresh-default"
say "Your Boardroom settings are still in ~/.config/encom-boardroom (delete it if you like)."
