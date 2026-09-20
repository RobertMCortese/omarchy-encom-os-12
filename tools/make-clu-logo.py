#!/usr/bin/env python3
"""Letter CLU in ENCOM's face, for the Clu theme's poster.

There is no CLU wordmark in the films, so this draws one in the ENCOM
lettering: the same frame, the same stroke, the same round terminals, with
the C lifted straight out of the traced ENCOM mark and the L and U drawn to
match. Everything here is measured off that mark — stroke weights, letter
box, advance — so the two sit together as one family.

    tools/make-clu-logo.py <out-dir>
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ENCOM = HERE.parent / "theme" / "tron-legacy" / "logo" / "encom-mark.svg"

# Measured from the ENCOM mark (see the raster measurements in its history):
VIEW = "6.5 10 320.5 74.8"
FRAME = (7.7, 11.3, 325.8, 83.5)   # outer box
FRAME_STROKE = 9.4
FRAME_RADIUS = 27                  # outer corner radius
LETTER_STROKE = 9.9
LETTER_TOP, LETTER_BOT = 27.0, 67.3
LETTER_WIDTH, ADVANCE = 56.5, 60.5
CORNER = 7                         # centre-line corner radius in the letters


def encom_c():
    """The C, straight out of the traced mark, and where it sits."""
    d = re.search(r' d="([^"]+)"', ENCOM.read_text()).group(1)
    parts = [p.strip() + " Z" for p in d.split("Z") if p.strip()]
    c = parts[3]
    xs = [float(v) for v in re.findall(r"-?\d+\.?\d*", c)][0::2]
    return c, min(xs)


def letter(kind, left):
    """L or U as a centre line, to be stroked with round caps and joins."""
    half = LETTER_STROKE / 2
    x0, x1 = left + half, left + LETTER_WIDTH - half
    y0, y1 = LETTER_TOP + half, LETTER_BOT - half
    r = CORNER
    if kind == "L":
        return (f"M{x0:.1f} {y0:.1f} V{y1 - r:.1f} "
                f"A{r} {r} 0 0 0 {x0 + r:.1f} {y1:.1f} H{x1:.1f}")
    return (f"M{x0:.1f} {y0:.1f} V{y1 - r:.1f} "
            f"A{r} {r} 0 0 0 {x0 + r:.1f} {y1:.1f} H{x1 - r:.1f} "
            f"A{r} {r} 0 0 0 {x1:.1f} {y1 - r:.1f} V{y0:.1f}")


def build(out):
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    c_path, c_left = encom_c()

    # Three letters, centred between the frame's ends.
    total = 2 * ADVANCE + LETTER_WIDTH
    start = (FRAME[0] + FRAME[2]) / 2 - total / 2
    shift = start - c_left

    fs = FRAME_STROKE / 2
    fx0, fy0, fx1, fy1 = FRAME[0] + fs, FRAME[1] + fs, FRAME[2] - fs, FRAME[3] - fs
    fr = FRAME_RADIUS - fs
    frame = (f"M{fx0 + fr:.1f} {fy0:.1f} H{fx1 - fr:.1f} "
             f"A{fr:.1f} {fr:.1f} 0 0 1 {fx1:.1f} {fy0 + fr:.1f} "
             f"V{fy1 - fr:.1f} A{fr:.1f} {fr:.1f} 0 0 1 {fx1 - fr:.1f} {fy1:.1f} "
             f"H{fx0 + fr:.1f} A{fr:.1f} {fr:.1f} 0 0 1 {fx0:.1f} {fy1 - fr:.1f} "
             f"V{fy0 + fr:.1f} A{fr:.1f} {fr:.1f} 0 0 1 {fx0 + fr:.1f} {fy0:.1f} Z")

    note = ("<!-- CLU lettered in the ENCOM face, after Tron: Legacy (Disney). The C is "
            "from the traced ENCOM mark; the L and U are drawn to its measurements. "
            "For a fan desktop theme; ENCOM and Tron are trademarks of Disney. -->")
    body = (
        f'<path fill="none" stroke="#a8ecff" stroke-width="{FRAME_STROKE}" d="{frame}"/>'
        f'<g transform="translate({shift:.1f} 0)">'
        f'<path fill="#a8ecff" fill-rule="evenodd" d="{c_path}"/></g>'
        f'<path fill="none" stroke="#a8ecff" stroke-width="{LETTER_STROKE}" '
        f'stroke-linecap="round" stroke-linejoin="round" '
        f'd="{letter("L", start + ADVANCE)} {letter("U", start + 2 * ADVANCE)}"/>'
    )
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{VIEW}">{note}{body}</svg>'
    (out / "clu-mark.svg").write_text(svg)
    print("wrote", out / "clu-mark.svg")


build(sys.argv[1] if len(sys.argv) > 1 else HERE.parent / "theme" / "clu" / "logo")
