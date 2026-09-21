#!/usr/bin/env python3
"""Draw the comms portrait that sits beside a Boardroom alert.

One animated GIF per theme, in the theme's own colours, drawn from code:

  sentinel    a helmeted silhouette, visor pulsing, head turning a little
  glitch      the same figure breaking up in bands of interference
  polyhedron  a faceted solid turning on its axis, in the 1982 manner
  corrupt     the figure with the Corruption cracking across it

They are original drawings, not anything out of the films. Frames are SVG,
rendered with rsvg-convert and assembled with ImageMagick.

    tools/make-portrait.py [theme ...]   # default: every theme with a palette
"""
import json
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
THEMES = HERE.parent / "theme"
W, H, FRAMES = 200, 154, 24


def head(colour, glow, turn, visor):
    """A helmeted head and shoulders, turned by `turn` (-1..1).

    Lit from the left, the way a face on a comms screen is: the body carries
    a wash of the theme's colour rather than being an outline, with a
    brighter rim down the lit side and the visor glowing over it."""
    cx = W / 2 + turn * 10
    return f'''
      <defs>
        <linearGradient id="lit" x1="0" y1="0" x2="1" y2="0.3">
          <stop offset="0" stop-color="{colour}" stop-opacity="0.55"/>
          <stop offset="0.45" stop-color="{colour}" stop-opacity="0.22"/>
          <stop offset="1" stop-color="{colour}" stop-opacity="0.06"/>
        </linearGradient>
        <radialGradient id="visorGlow" cx="0.5" cy="0.5" r="0.6">
          <stop offset="0" stop-color="{glow}" stop-opacity="0.95"/>
          <stop offset="1" stop-color="{glow}" stop-opacity="0.25"/>
        </radialGradient>
      </defs>
      <g stroke="{colour}" stroke-width="2.5" stroke-linejoin="round">
        <path d="M{cx - 46} {H} q0 -34 46 -34 q46 0 46 34" fill="url(#lit)"/>
        <path d="M{cx - 27} {H - 58} q0 -40 27 -40 q27 0 27 40 q0 34 -27 34 q-27 0 -27 -34 z"
              fill="url(#lit)"/>
        <path d="M{cx - 27} {H - 58} q0 -40 27 -40 q6 0 11 3 q-21 6 -21 37 q0 24 12 32
                 q-2 0.6 -4 0.6 q-25 0 -25 -34 z" fill="{glow}" fill-opacity="0.3" stroke="none"/>
        <path d="M{cx - 22} {H - 70} q22 -12 44 0 q-4 16 -22 16 q-18 0 -22 -16 z"
              fill="url(#visorGlow)" fill-opacity="{visor:.2f}" stroke="{glow}"/>
        <path d="M{cx - 27} {H - 34} l54 0" stroke-opacity="0.5" fill="none"/>
        <path d="M{cx} {H - 24} l0 24" stroke-opacity="0.5" fill="none"/>
      </g>'''


def frame_svg(style, i, colour, glow, ink):
    t = i / FRAMES
    turn = math.sin(t * 2 * math.pi)
    body = ""
    if style in ("sentinel", "glitch", "corrupt"):
        body = head(colour, glow, turn * 0.6, 0.35 + 0.35 * abs(math.sin(t * 4 * math.pi)))
        if style == "corrupt":
            # Veins of it, spreading and receding: each starts at the same
            # place every frame and grows with t, so it reads as one thing
            # creeping rather than a new scribble each time.
            veins = ""
            for v in range(6):
                x, y = 18 + v * 30, H - 6
                path = [f"M{x} {y}"]
                ang = -math.pi / 2 + math.sin(v * 1.7) * 0.5
                reach = 22 + 52 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + v))
                for seg in range(5):
                    ang += math.sin(v * 2.3 + seg) * 0.7
                    x += math.cos(ang) * reach / 5
                    y += math.sin(ang) * reach / 5
                    path.append(f"L{x:.0f} {y:.0f}")
                veins += (f'<path d="{" ".join(path)}" fill="none" stroke="{glow}" '
                          f'stroke-width="{1.6 + v % 2}" stroke-opacity="0.85"/>')
            body += veins
        if style == "glitch":
            # Torn bands, sliding across and breaking up the picture.
            bands = ""
            for b in range(5):
                y = (t * 260 + b * 41) % H
                dx = (b - 2) * 7 * math.sin(t * 6 * math.pi + b)
                bands += (f'<rect x="{dx:.0f}" y="{y:.0f}" width="{W}" height="6" '
                          f'fill="{glow}" fill-opacity="0.22"/>')
            body += bands
    else:
        # A faceted solid: two rings of vertices, turning, with its edges drawn.
        cx, cy, r = W / 2, H / 2, 46
        a0 = t * 2 * math.pi
        top, bottom = [], []
        for k in range(6):
            a = a0 + k * math.pi / 3
            top.append((cx + math.cos(a) * r, cy - 18 - math.sin(a) * r * 0.34))
            bottom.append((cx + math.cos(a) * r * 0.82, cy + 20 - math.sin(a) * r * 0.28))
        edges = ""
        for k in range(6):
            p, q = top[k], top[(k + 1) % 6]
            u, v = bottom[k], bottom[(k + 1) % 6]
            # Each face carries a wash that brightens as it turns to the
            # light, so the solid reads as shaded rather than as a cage.
            lit = 0.06 + 0.3 * max(0.0, math.cos(a0 + k * math.pi / 3 + 0.6))
            edges += (f'<path d="M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f} '
                      f'L{v[0]:.1f} {v[1]:.1f} L{u[0]:.1f} {u[1]:.1f} Z" '
                      f'fill="{colour}" fill-opacity="{lit:.2f}" stroke="none"/>'
                      f'<path d="M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f}"/>'
                      f'<path d="M{u[0]:.1f} {u[1]:.1f} L{v[0]:.1f} {v[1]:.1f}"/>'
                      f'<path d="M{p[0]:.1f} {p[1]:.1f} L{u[0]:.1f} {u[1]:.1f}" stroke-opacity="0.55"/>')
        body = (f'<g stroke="{colour}" fill="none" stroke-width="2.5">{edges}</g>'
                f'<circle cx="{cx}" cy="{cy}" r="{5 + 2 * math.sin(t * 4 * math.pi):.1f}" fill="{glow}"/>')

    # Interlacing: every other line dropped, and a brighter band rolling down
    # the picture the way a camera out of sync with a screen shows one.
    scan = "".join(f'<rect x="0" y="{y}" width="{W}" height="1" fill="#000" fill-opacity="0.45"/>'
                   for y in range(0, H, 2))
    roll = (t * H * 1.6) % (H + 40) - 20
    band = (f'<rect x="0" y="{roll:.0f}" width="{W}" height="14" fill="{colour}" '
            f'fill-opacity="0.10"/>'
            f'<rect x="0" y="{roll + 14:.0f}" width="{W}" height="2" fill="{glow}" '
            f'fill-opacity="0.22"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
      <rect width="{W}" height="{H}" fill="{ink}"/>
      <rect width="{W}" height="{H}" fill="{colour}" fill-opacity="0.07"/>
      {body}{band}{scan}
    </svg>'''


def shoot(theme, palette):
    """A theme that ships footage of its own: portrait-source.gif, put on the
    same screen as the drawn ones. Its greys are mapped onto the theme's ramp
    — ink through accent to the bright — and the same interlacing laid over
    it, so a clip and a drawing sit side by side without one looking pasted
    in from somewhere else."""
    src = THEMES / theme / "portrait-source.gif"
    out = THEMES / theme / "portrait.gif"
    if not src.exists():
        print(theme, "has no portrait-source.gif to work from")
        return
    colour, glow = palette["accent"], palette["accentHi"]
    ink = palette.get("ink", "#02060a")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        lines = tmp / "lines.png"
        rows = "".join(f'<rect x="0" y="{y}" width="{W}" height="1" fill="#000" '
                       f'fill-opacity="0.45"/>' for y in range(0, H, 2))
        (tmp / "lines.svg").write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">{rows}</svg>')
        subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H),
                        "-o", str(lines), str(tmp / "lines.svg")], check=True)
        subprocess.run([
            "magick", str(src), "-coalesce",
            # Fitted, not filled: a clip squarer than the window loses the
            # bottom of the subject if it is made to fill, and two thin bars
            # of ink cost less than a chin does.
            "-resize", f"{W}x{H}", "-background", ink, "-gravity", "center",
            "-extent", f"{W}x{H}",
            "-colorspace", "gray",
            # Footage shot in daylight sits in a narrow band of greys, and a
            # ramp laid straight over it comes out as fog. Pull it open first
            # and put some snap in the middle.
            "-auto-level", "-sigmoidal-contrast", "7,50%",
            # black to the theme's ink, white to its bright: the clip now
            # carries the theme's colour instead of its own.
            "+level-colors", f"{ink},{glow}",
            "-fill", colour, "-colorize", "15",
            "null:", str(lines), "-layers", "composite",
            "-colorspace", "sRGB", "-type", "TrueColor", "-colors", "64",
            "-layers", "Optimize", str(out)], check=True)
    print(theme, "from portrait-source.gif", out.stat().st_size, "bytes")


def build(theme):
    palette = json.loads((THEMES / theme / "encom.json").read_text())
    style = palette.get("portrait", "sentinel")
    if style == "own":
        return shoot(theme, palette)
    colour, glow, ink = palette["accent"], palette["accentHi"], palette.get("ink", "#02060a")
    out = THEMES / theme / "portrait.gif"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for i in range(FRAMES):
            (tmp / f"f{i:02d}.svg").write_text(frame_svg(style, i, colour, glow, ink))
            subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H),
                            "-o", str(tmp / f"f{i:02d}.png"), str(tmp / f"f{i:02d}.svg")], check=True)
        frames = sorted(str(p) for p in tmp.glob("*.png"))
        subprocess.run(["magick", "-delay", "8", *frames, "-loop", "0", "-colorspace", "sRGB",
                        "-type", "TrueColor", "-colors", "64", "-layers", "Optimize", str(out)], check=True)
    print(theme, style, out.stat().st_size, "bytes")


names = sys.argv[1:] or sorted(p.name for p in THEMES.iterdir() if (p / "encom.json").exists())
if not shutil.which("rsvg-convert"):
    sys.exit("needs rsvg-convert")
for name in names:
    build(name)
