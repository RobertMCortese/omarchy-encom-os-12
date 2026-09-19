#!/usr/bin/env python3
"""Draw the comms portrait that sits beside a Boardroom alert.

One animated GIF per theme, in the theme's own colours, drawn from code:

  sentinel    a helmeted silhouette, visor pulsing, head turning a little
  glitch      the same figure breaking up in bands of interference
  polyhedron  a faceted solid turning on its axis, in the 1982 manner

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
    """A helmeted head and shoulders, turned by `turn` (-1..1)."""
    cx = W / 2 + turn * 10
    return f'''
      <g stroke="{colour}" fill="none" stroke-width="2.5" stroke-linejoin="round">
        <path d="M{cx - 46} {H} q0 -34 46 -34 q46 0 46 34" fill="#00000055"/>
        <path d="M{cx - 27} {H - 58} q0 -40 27 -40 q27 0 27 40 q0 34 -27 34 q-27 0 -27 -34 z" fill="#00000088"/>
        <path d="M{cx - 22} {H - 70} q22 -12 44 0 q-4 16 -22 16 q-18 0 -22 -16 z"
              fill="{glow}" fill-opacity="{visor:.2f}" stroke="{glow}"/>
        <path d="M{cx - 27} {H - 34} l54 0" stroke-opacity="0.5"/>
        <path d="M{cx} {H - 24} l0 24" stroke-opacity="0.5"/>
      </g>'''


def frame_svg(style, i, colour, glow, ink):
    t = i / FRAMES
    turn = math.sin(t * 2 * math.pi)
    body = ""
    if style in ("sentinel", "glitch"):
        body = head(colour, glow, turn * 0.6, 0.35 + 0.35 * abs(math.sin(t * 4 * math.pi)))
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
            edges += (f'<path d="M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f}"/>'
                      f'<path d="M{u[0]:.1f} {u[1]:.1f} L{v[0]:.1f} {v[1]:.1f}"/>'
                      f'<path d="M{p[0]:.1f} {p[1]:.1f} L{u[0]:.1f} {u[1]:.1f}" stroke-opacity="0.55"/>')
        body = (f'<g stroke="{colour}" fill="none" stroke-width="2.5">{edges}</g>'
                f'<circle cx="{cx}" cy="{cy}" r="{5 + 2 * math.sin(t * 4 * math.pi):.1f}" fill="{glow}"/>')

    scan = "".join(f'<rect x="0" y="{y}" width="{W}" height="1" fill="#000" fill-opacity="0.35"/>'
                   for y in range(0, H, 3))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
      <rect width="{W}" height="{H}" fill="{ink}"/>
      <rect width="{W}" height="{H}" fill="{colour}" fill-opacity="0.05"/>
      {body}{scan}
    </svg>'''


def build(theme):
    palette = json.loads((THEMES / theme / "encom.json").read_text())
    style = palette.get("portrait", "sentinel")
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
