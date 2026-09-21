-- ENCOM OS-12 look'n'feel for Hyprland.
-- Installed to ~/.config/hypr/encom.lua and loaded from looknfeel.lua by a
-- `require("hypr.encom")` line the installer adds between marker comments.

-- ── ENCOM OS-12 ──────────────────────────────────────────────────────────
-- Square corners: the Encom console has no rounded anything, and on a 1366px
-- panel sharp edges also buy back a few pixels per window. Delete this block
-- to go back to the Omarchy default.
hl.config({
  decoration = {
    rounding = 0,
    -- Push unfocused windows back so the lit cyan border on the focused one
    -- reads as "this is the active program".
    dim_inactive = true,
    dim_strength = 0.22,
  },
})

-- ── ENCOM OS-12: materialize / derezz ────────────────────────────────────
-- Programs in the film rez into existence and break apart on the way out.
-- These keep the short durations set above (the battery tuning is the point)
-- and change only the curve and the style, so nothing here costs extra GPU
-- time -- an animation of the same length just reads differently.
hl.curve("encomRez", { type = "bezier", points = { { 0.10, 0.90 }, { 0.14, 1.0 } } })
hl.curve("encomDerezz", { type = "bezier", points = { { 0.70, 0.00 }, { 1.0, 0.35 } } })
hl.curve("encomTrace", { type = "bezier", points = { { 0.22, 1.0 }, { 0.30, 1.0 } } })

-- Grow from a small seed rather than the near-full 90%, so a new window
-- resolves into place instead of popping.
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.4, bezier = "encomRez", style = "popin 15%" })
-- Hold, then break apart fast.
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.2, bezier = "encomDerezz", style = "popin 15%" })
hl.animation({ leaf = "windows", enabled = true, speed = 2.4, bezier = "encomRez" })

-- The cyan gradient border is the most Tron thing on screen; let it snap to
-- the focused window rather than easing lazily.
hl.animation({ leaf = "border", enabled = true, speed = 2.6, bezier = "encomTrace" })

-- Menus and the bar are layer surfaces: rez them the same way.
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.4, bezier = "encomRez", style = "popin 80%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "encomDerezz", style = "popin 80%" })

-- ── ENCOM OS-12: cursor ──────────────────────────────────────────────────
-- Each theme has a cursor of its own in ~/.local/share/icons, and names it in
-- its palette. This reads the name from whichever theme is current rather
-- than carrying one, because Hyprland sets this at startup and a fixed name
-- would hand every boot the same pointer whatever the desktop wears.
--
-- Only XCURSOR_THEME is set: naming a HYPRCURSOR_THEME that does not exist as
-- a hyprcursor package would make Hyprland fall back noisily.
local function theme_cursor()
  local path = os.getenv("HOME") .. "/.local/state/omarchy/current/theme/encom.json"
  local f = io.open(path, "r")
  if not f then return "Tron-Legacy-Cursor" end
  local text = f:read("*a")
  f:close()
  return text:match('"cursor"%s*:%s*"([^"]+)"') or "Tron-Legacy-Cursor"
end

hl.env("XCURSOR_THEME", theme_cursor())
