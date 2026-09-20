#!/usr/bin/env python3
"""Build the theme variants from theme/tron-legacy.

Each variant is the same desktop in another Tron palette: the accent family
(the cyan circuitry) moves to the theme's hue, the contrast family (the
orange alarms) moves to its second hue, and the near-black backgrounds take a
faint tint of the accent. Terminal colours that would collide with the new
accent are rotated away, so nothing turns monochrome.

    tools/make-theme.py [name ...]      # default: every variant

It writes theme/<name>/: colors.toml, shell.toml, icons.theme, encom.json,
the logo, three wallpapers, the preview and the boot splash art. Needs
ImageMagick and rsvg-convert. Re-run it after changing a palette here.
"""
import colorsys
import json
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
THEMES_DIR = HERE.parent / "theme"
BASE = THEMES_DIR / "tron-legacy"

# The base theme's colour families, by role. Everything else is left alone.
FAMILY = {
    "accent": ["#6fc3df", "#19c7ff", "#5ab4dc"],
    "accentHi": ["#a8ecff", "#eafaff", "#bfe9ff", "#d8f6ff"],
    "accentDim": ["#1b4d5e", "#1d4d5e", "#14414f", "#123a4a", "#0a6f8f", "#3f6d7e", "#4d7f92"],
    "accentSoft": ["#9fd8ea", "#cfeefa"],
    "contrast": ["#ff8c21", "#ff8a1c"],
    "contrastHi": ["#ffb347", "#ffd07a", "#ffc27a", "#ffd9a8", "#fff1d6"],
    "ink": ["#05090d", "#03060a", "#010305", "#0c1820", "#03070b", "#010306", "#02141b"],
}

# name -> (accent, contrast, title, blurb). The accent replaces the cyan
# circuitry, the contrast the orange alarms; each family is shifted to that
# hue and scaled to its saturation and lightness.
VARIANTS = {
    "clu": ("#ff9d2e", "#38c6f4", "ENCOM OS-12 — Clu",
                  "Clu's grid: amber circuitry, cold cyan alarms."),
    "dillinger-systems": ("#ff3b30", "#7fd0ff", "Dillinger Systems",
                          "Dillinger's grid: crimson circuitry, ice-blue alarms."),
    # The first film reads blue, not violet: its own wordmark is a #1688b9
    # gradient and the transfer sequence peaks around #3b70f6.
    "tron-1982": ("#3b7bff", "#ffc300", "TRON 1982",
                  "The first grid: electric blue circuitry, amber alarms."),
    # The series is jade, not cyan: its field measures #0a6658 to #11a389,
    # with the Renegade in a cool white and the occupation in rust.
    "tron-uprising": ("#11a389", "#c4562f", "TRON Uprising",
                      "The occupied grid: jade circuitry, rust alarms."),
    # The game's system is a dark teal shot through with the Corruption, a
    # chartreuse that measures #43691c to #72ad34 — the one hue in the wheel
    # none of the films use.
    "tron-2-0": ("#79c72f", "#ff5a2b", "TRON 2.0",
                 "The infected system: corruption green, firewall orange."),
}


def hex_to_hls(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)


def hls_to_hex(hue, light, sat):
    r, g, b = colorsys.hls_to_rgb(hue % 1.0, min(1, max(0, light)), min(1, max(0, sat)))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def restyle(colour, anchor, target):
    """`colour` moved from its family's anchor to `target`: the target's hue,
    with saturation and lightness scaled by the same ratio."""
    _, a_light, a_sat = hex_to_hls(anchor)
    t_hue, t_light, t_sat = hex_to_hls(target)
    _, light, sat = hex_to_hls(colour)
    sat_ratio = (t_sat / a_sat) if a_sat else 1
    light_ratio = (t_light / a_light) if a_light else 1
    return hls_to_hex(t_hue, light * light_ratio, sat * sat_ratio)


def palette_for(accent, contrast):
    """Every base colour that moves, mapped to its new value."""
    accent_hue = hex_to_hls(accent)[0] * 360
    out = {}
    for role, colours in FAMILY.items():
        for c in colours:
            if role.startswith("accent"):
                out[c] = restyle(c, "#6fc3df", accent)
            elif role.startswith("contrast"):
                out[c] = restyle(c, "#ff8c21", contrast)
            else:                       # the near-blacks: a faint accent tint
                _, light, sat = hex_to_hls(c)
                out[c] = hls_to_hex(accent_hue / 360, light, min(sat, 0.35))
    # Terminal colours that would now sit on top of the accent move aside.
    for c in ["#3ddbb4", "#6ff2d2", "#3fa9f5", "#7fc9ff", "#9d7bff", "#c0a9ff", "#ff6b3d", "#ff8d63"]:
        hue, light, sat = hex_to_hls(c)
        gap = abs((hue * 360 - accent_hue + 180) % 360 - 180)
        out[c] = hls_to_hex((hue * 360 + 60) / 360, light, sat) if gap < 28 else c
    return out


def swap(text, mapping):
    """Replace colours case-insensitively, longest first, in one pass."""
    pattern = re.compile("|".join(sorted((re.escape(k) for k in mapping), key=len, reverse=True)),
                         re.IGNORECASE)
    return pattern.sub(lambda m: mapping[m.group(0).lower()], text)


def run(cmd):
    subprocess.run(cmd, check=True)


def grid_horizon(accent, accent_hi, ink, W=1920, H=1080):
    """The grid running to a lit horizon: the wallpaper, and the bed every
    theme's poster card sits on, so the cards match whatever else a theme
    keeps in its backgrounds."""
    rows = []
    horizon = H * 0.46
    for i in range(-30, 31):
        x = W / 2 + i * W * 0.085
        rows.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%d" />' % (W / 2 + i * 6, horizon, x, H))
    y, step = horizon, 3.0 * (H / 1080)
    while y < H:
        rows.append('<line x1="0" y1="%.1f" x2="%d" y2="%.1f" />' % (y, W, y))
        step *= 1.32
        y += step
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
      <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="{ink}"/><stop offset="0.46" stop-color="{accent}" stop-opacity="0.22"/>
        <stop offset="0.48" stop-color="{ink}"/><stop offset="1" stop-color="{ink}"/></linearGradient></defs>
      <rect width="{W}" height="{H}" fill="{ink}"/><rect width="{W}" height="{H}" fill="url(#sky)"/>
      <g stroke="{accent}" stroke-width="1.4" opacity="0.5">{"".join(rows)}</g>
      <rect x="0" y="{horizon - 1.5:.0f}" width="{W}" height="3" fill="{accent_hi}" opacity="0.8"/>
    </svg>"""


def wallpapers(out, accent, accent_hi, ink):
    """Three wallpapers in the theme's colours: grid horizon, circuit, sea."""
    beds = out / "backgrounds"
    beds.mkdir(parents=True, exist_ok=True)
    W, H = 1920, 1080

    # 01 grid horizon: a perspective grid running to a lit horizon.
    (beds / "01-grid-horizon.svg").write_text(grid_horizon(accent, accent_hi, ink))

    # 02 circuit: traces and pads, as on a board.
    import random
    random.seed(12)
    parts = []
    for _ in range(190):
        x, y = random.randrange(0, W, 20), random.randrange(0, H, 20)
        d, path = random.choice([(1, 0), (0, 1), (1, 1), (1, -1)]), []
        for _ in range(random.randint(2, 6)):
            nx, ny = x + d[0] * random.randrange(40, 200, 20), y + d[1] * random.randrange(40, 200, 20)
            path.append("L%d %d" % (nx, ny))
            x, y = nx, ny
            d = random.choice([(1, 0), (0, 1), (0, -1)])
        parts.append('<path d="M%d %d %s" fill="none" opacity="%.2f"/>'
                     % (x, y, " ".join(path), random.uniform(0.15, 0.55)))
        if random.random() < 0.3:
            parts.append('<circle cx="%d" cy="%d" r="4" fill="%s" opacity="0.5"/>' % (x, y, accent_hi))
    (beds / "02-circuit.svg").write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
      <rect width="{W}" height="{H}" fill="{ink}"/>
      <g stroke="{accent}" stroke-width="2">{"".join(parts)}</g></svg>''')

    # 03 sea of simulation: still water under a low light.
    waves = []
    for i in range(120):
        y = H * 0.52 + i * i * 0.06
        if y > H:
            break
        waves.append('<line x1="0" y1="%.1f" x2="%d" y2="%.1f" opacity="%.2f"/>' % (y, W, y, 0.5 - i * 0.004))
    (beds / "03-sea-of-simulation.svg").write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
      <defs><radialGradient id="glow" cx="0.5" cy="0.52" r="0.55">
        <stop offset="0" stop-color="{accent_hi}" stop-opacity="0.5"/>
        <stop offset="1" stop-color="{ink}" stop-opacity="0"/></radialGradient></defs>
      <rect width="{W}" height="{H}" fill="{ink}"/>
      <rect width="{W}" height="{H}" fill="url(#glow)"/>
      <g stroke="{accent}" stroke-width="1.6">{"".join(waves)}</g></svg>''')

    for svg_file in sorted(beds.glob("*.svg")):
        run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(svg_file.with_suffix(".png")), str(svg_file)])
        svg_file.unlink()


def logo_art(out, accent, accent_hi, ink, poster, mark, splash=None):
    """Two pieces of art in the theme's colour.

    The boot splash and the disk unlock prompt carry the mark the desktop
    wears — ENCOM for the ENCOM houses, Dillinger for Dillinger — because
    that is whose machine it is. The poster card names the theme instead, and
    is only ever seen in the readme and the theme picker."""
    plate = out / "_mark.png"
    run(["rsvg-convert", "-w", "760", "-o", str(plate), str(mark)])
    run(["magick", str(plate), "-background", "none", "-fill", splash or accent_hi, "-colorize", "100",
         "-bordercolor", "none", "-border", "20x20", "-resize", "800x188",
         "-background", ink, "-gravity", "center", "-extent", "800x188", str(out / "unlock.png")])
    plate.unlink()
    tmp = out / "_poster.png"
    run(["rsvg-convert", "-w", "760", "-o", str(tmp), str(poster)])
    # The preview card: a fresh grid in the theme's colours with the wordmark
    # over it, so every card is the same bed whatever wallpapers the theme has.
    bed = out / "_bed.svg"
    bed.write_text(grid_horizon(accent, accent_hi, ink, 1800, 1012))
    run(["rsvg-convert", "-w", "1800", "-h", "1012", "-o", str(out / "_bed.png"), str(bed)])
    run(["magick", str(out / "_bed.png"), "-resize", "1800x1012^",
         "-gravity", "center", "-extent", "1800x1012",
         "(", str(tmp), "-background", "none", "-fill", accent_hi, "-colorize", "100", "-resize", "900x", ")",
         "-gravity", "center", "-composite", str(out / "preview.png")])
    shutil.copy(out / "preview.png", out / "preview-unlock.png")
    tmp.unlink()
    bed.unlink()
    (out / "_bed.png").unlink()


def build(name):
    accent, contrast, title, blurb = VARIANTS[name]
    out = THEMES_DIR / name
    out.mkdir(parents=True, exist_ok=True)
    mapping = palette_for(accent, contrast)
    mapping.update(TINT.get(name, {}))

    for f in ("colors.toml", "shell.toml"):
        text = swap((BASE / f).read_text(), mapping)
        text = re.sub(r"^# ENCOM OS-12.*$", "# " + title, text, count=1, flags=re.M)
        text = re.sub(r"^# (Black glass|ENCOM OS-12 shell surfaces).*$",
                      "# " + blurb, text, count=1, flags=re.M)
        (out / f).write_text(text)
    shutil.copy(BASE / "icons.theme", out / "icons.theme")
    # A theme with a wordmark of its own keeps it; the rest take ENCOM's.
    brand, markname = BRAND.get(name, ("ENCOM OS-12", "encom-mark.svg"))
    own = THEMES_DIR / name / "logo" / markname
    if not own.exists():
        shutil.copytree(BASE / "logo", out / "logo", dirs_exist_ok=True)
    else:
        shutil.copy(BASE / "logo" / "ascii.py", out / "logo" / "ascii.py")
    mark = out / "logo" / markname
    # Everything that draws the mark reads logo/mark.svg from whichever theme
    # is current, so it follows a theme switch without being told.
    shutil.copy(mark, out / "logo" / "mark.svg")

    palette = json.loads(swap((BASE / "encom.json").read_text(), mapping))
    palette["portrait"] = PORTRAIT[name]
    palette["brand"] = brand
    palette["sigil"] = SIGIL.get(name, "disc")
    palette["cursor"] = cursor_name(name)
    palette["lockScene"] = LOCK_SCENE.get(name, "duel")
    if name in CLASSIC:
        palette["classic"] = True
    palette.update(OVERRIDE.get(name, {}))
    palette.update(SIDES.get(name, {}))
    (out / "encom.json").write_text(json.dumps(palette, indent=2) + "\n")

    # The art takes its colours from the finished palette, so a theme that
    # overrides one (Uprising's white highlight) is drawn in it too.
    accent, bright, ink = palette["accent"], palette["accentHi"], palette["ink"]
    wallpapers(out, accent, bright, ink)
    logo_art(out, accent, bright, ink, poster_of(name), out / "logo" / "mark.svg",
             palette.get("splash"))
    print(name, "accent", accent, "contrast", mapping["#ff8c21"])


# The lock screen scene: the disc duel, or 1982's digitiser.
LOCK_SCENE = {"tron-1982": "digitise"}
# Themes that use the 1982 game's own pieces — the arena wall panels, the
# classic cycle model and its light trails — rather than our Legacy-era
# ones. They came with 3dLightCycles, which this screensaver started from.
CLASSIC = {"tron-1982"}
# Which portrait appears beside a Boardroom alert. A style name is drawn by
# tools/make-portrait.py; "own" means the theme ships a portrait.gif of its
# own and the generator leaves it alone.
PORTRAIT = {"clu": "sentinel", "dillinger-systems": "own",
            "tron-1982": "polyhedron", "tron-uprising": "glitch",
            "tron-2-0": "corrupt"}

# Whose house this is: the wordmark a theme carries, and the name that
# goes with it on the bar, the HUD and the lock screen.
BRAND = {"dillinger-systems": ("DILLINGER SYSTEMS", "dillinger-mark.svg")}
# The sigil on the bar and the HUD: ENCOM's identity disc, or the wedge —
# the triangle under the Dillinger wordmark's g, in an angular frame.
SIGIL = {"dillinger-systems": "wedge"}

# Base colours a theme remaps by hand, before anything is swapped, so the
# change reaches the terminal and editor palettes too and not just the JSON.
# A pale tint of a red reads pink, whatever its hue says, so Dillinger's
# highlight leans towards orange as it lightens instead of washing out.
TINT = {"dillinger-systems": {"#a8ecff": "#ff8a5c"}}

# Palette keys a theme sets for itself, after the colour swap has run.
# Uprising's highlight is the Renegade's cool white rather than a pale tint
# of its jade, because that white against the jade is what the series looks
# like; its black carries a little of the same green.
# "splash" is the mark's colour on the boot screen, for a theme whose
# highlight is not its own colour: Uprising boots jade, not white.
OVERRIDE = {"tron-uprising": {"accentHi": "#e6f1ef", "ink": "#04100e",
                              "splash": "#2fd0b0"},
            # The game's black is the system's own dark teal, not neutral.
            "tron-2-0": {"accentHi": "#cdf08a", "ink": "#061513"},
            # Its mark boots in a vivid red rather than the highlight, which
            # even warmed is too light to read as Dillinger's own colour.
            "dillinger-systems": {"splash": "#ff2418"}}

# The wordmark on a theme's poster — its preview card and its boot splash.
# This is the name of the thing, which is not always the mark the desktop
# wears: the ENCOM themes keep ENCOM on the bar and the HUD, and say what
# they are on the poster.
POSTER = {
    "tron-legacy": "tron-legacy-mark.svg",
    "tron-uprising": "tron-uprising-mark.svg",
    "tron-2-0": "tron-2-0-mark.svg",
    "clu": "clu-mark.svg",
    "tron-1982": "tron-1982-mark.svg",
    "dillinger-systems": "dillinger-mark.svg",
}

# The two sides in Light Cycles and the disc duel. By default they are the
# theme's accent against its contrast colour; 1982 instead takes the colours
# the original light cycle game was played in.
SIDES = {
    "clu": {"sideAName": "CLU", "sideBName": "PROGRAMS"},
    "dillinger-systems": {"sideAName": "DILLINGER", "sideBName": "ENCOM"},
    "tron-1982": {"sideA": "#3b7bff", "sideAHi": "#d7e6ff",
                  "sideB": "#ffbe00", "sideBHi": "#fff3cf",
                  "sideAName": "USERS", "sideBName": "PROGRAMS"},
    # The Renegade's white against the occupation's rust.
    "tron-uprising": {"sideA": "#dff3ee", "sideAHi": "#ffffff",
                      "sideB": "#c4562f", "sideBHi": "#ffb48c",
                      "sideAName": "RENEGADE", "sideBName": "OCCUPATION"},
    # The user against the Corruption, which is the game's whole argument.
    "tron-2-0": {"sideA": "#6fd8ff", "sideAHi": "#d8f6ff",
                 "sideB": "#8fd63f", "sideBHi": "#d6f79a",
                 "sideAName": "USER", "sideBName": "CORRUPTION"},
}

def cursor_name(name):
    """The cursor theme built for a desktop theme, by tools/make-cursors.sh."""
    return "-".join(p.capitalize() for p in name.split("-")) + "-Cursor"


def poster_of(name):
    own = THEMES_DIR / name / "logo" / POSTER.get(name, "mark.svg")
    return own if own.exists() else THEMES_DIR / name / "logo" / "mark.svg"


def repost(name):
    """Redraw one theme's poster art from its wordmark and its own wallpaper.
    Works for the base theme too, which build() never touches."""
    out = THEMES_DIR / name
    # Every theme keeps the mark the desktop wears at logo/mark.svg; the base
    # theme has no build() pass to put it there.
    brand, markname = BRAND.get(name, ("ENCOM OS-12", "encom-mark.svg"))
    own = out / "logo" / markname
    if own.exists():
        shutil.copy(own, out / "logo" / "mark.svg")
    # The base theme has no build() pass to record its cursor either.
    palette = json.loads((out / "encom.json").read_text())
    if palette.get("cursor") != cursor_name(name):
        palette["cursor"] = cursor_name(name)
        (out / "encom.json").write_text(json.dumps(palette, indent=2) + "\n")
    palette = json.loads((out / "encom.json").read_text())
    logo_art(out, palette["accent"], palette["accentHi"],
             palette.get("ink", "#010305"), poster_of(name), out / "logo" / "mark.svg",
             palette.get("splash"))
    print(name, "poster from", poster_of(name).name)


args = sys.argv[1:]
if args and args[0] == "--posters":
    for theme in (args[1:] or ["tron-legacy", *VARIANTS]):
        repost(theme)
else:
    for theme in (args or VARIANTS):
        build(theme)
