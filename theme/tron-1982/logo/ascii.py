#!/usr/bin/env python3
"""Render the ENCOM logo SVG as terminal art with quadrant block characters.

Each character cell carries a 2x2 pixel block, so a terminal cell (about
twice as tall as wide) maps to square pixels and curves survive far better
than with full blocks.

    ascii.py <logo.svg> <columns> [tagline]
"""
import os
import subprocess
import sys
import tempfile

# Quadrant bits: top-left 8, top-right 4, bottom-left 2, bottom-right 1.
QUAD = {0: " ", 8: "▘", 4: "▝", 2: "▖", 1: "▗", 12: "▀", 3: "▄", 10: "▌", 5: "▐",
        9: "▚", 6: "▞", 14: "▛", 13: "▜", 11: "▙", 7: "▟", 15: "█"}


def render(svg, cols):
    px_w = cols * 2
    with tempfile.TemporaryDirectory() as tmp:
        png, pgm = os.path.join(tmp, "l.png"), os.path.join(tmp, "l.pgm")
        subprocess.run(["rsvg-convert", "-w", str(px_w * 4), "-b", "black", "-o", png, svg], check=True)
        # Downsample with averaging, then threshold: smoother than rendering small.
        subprocess.run(["magick", png, "-colorspace", "gray", "-filter", "box",
                        "-resize", f"{px_w}x", "-threshold", "40%", "-compress", "none", pgm], check=True)
        tokens = open(pgm).read().split()
    w, h = int(tokens[1]), int(tokens[2])
    vals = [int(t) for t in tokens[4:]]
    on = lambda x, y: 0 <= x < w and 0 <= y < h and vals[y * w + x] > 0
    lines = []
    for cy in range(0, h, 2):
        row = ""
        for cx in range(0, w, 2):
            bits = (on(cx, cy) << 3) | (on(cx + 1, cy) << 2) | (on(cx, cy + 1) << 1) | on(cx + 1, cy + 1)
            row += QUAD[bits]
        lines.append(row.rstrip())
    while lines and not lines[-1]:
        lines.pop()
    return lines


def main():
    svg, cols = sys.argv[1], int(sys.argv[2])
    tagline = sys.argv[3] if len(sys.argv) > 3 else ""
    lines = render(svg, cols)
    print("\n".join(lines))
    if tagline:
        width = max(len(l) for l in lines)
        print()
        print(tagline.center(width).rstrip())


main()
