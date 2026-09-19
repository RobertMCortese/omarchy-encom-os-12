#!/usr/bin/env python3
"""Trace a binary PBM into an SVG path (crack-following + Douglas-Peucker).

Enough to vectorise a flat logo without potrace: follow the pixel-edge
boundary of every ink region (holes included, filled even-odd), then simplify
the staircase outline. Coordinates are divided by the upscale factor so the
SVG lands back in the reference image's pixel space.

    trace.py <in.pbm> <upscale-factor> <out.svg>
"""
import re
import sys


def read_pbm(path):
    data = open(path, "rb").read()
    m = re.match(rb"P4\s+(?:#.*\s+)*(\d+)\s+(\d+)\s", data)
    w, h = int(m.group(1)), int(m.group(2))
    raw = data[m.end():]
    rowb = (w + 7) // 8
    rows = []
    for y in range(h):
        base = y * rowb
        rows.append([(raw[base + x // 8] >> (7 - x % 8)) & 1 for x in range(w)])
    return w, h, rows


def boundary_loops(w, h, ink):
    """Directed pixel-edge boundaries, ink kept on the right (clockwise)."""
    def at(x, y):
        return 0 <= x < w and 0 <= y < h and ink[y][x]

    nxt = {}
    for y in range(h):
        row = ink[y]
        for x in range(w):
            if not row[x]:
                continue
            if not at(x, y - 1):
                nxt[(x, y)] = (x + 1, y)
            if not at(x + 1, y):
                nxt[(x + 1, y)] = nxt.get((x + 1, y)) or (x + 1, y + 1)
            if not at(x, y + 1):
                nxt[(x + 1, y + 1)] = nxt.get((x + 1, y + 1)) or (x, y + 1)
            if not at(x - 1, y):
                nxt[(x, y + 1)] = nxt.get((x, y + 1)) or (x, y)
    loops = []
    while nxt:
        start, cur = next(iter(nxt.items()))
        loop = [start]
        del nxt[start]
        while cur != start and cur in nxt:
            loop.append(cur)
            cur = nxt.pop(cur)
        if len(loop) > 8:
            loops.append(loop)
    return loops


def simplify(points, tol):
    """Douglas-Peucker on a closed loop."""
    def dp(pts):
        if len(pts) < 3:
            return pts
        (x1, y1), (x2, y2) = pts[0], pts[-1]
        dx, dy = x2 - x1, y2 - y1
        norm = (dx * dx + dy * dy) ** 0.5 or 1e-9
        best, idx = 0.0, 0
        for i in range(1, len(pts) - 1):
            px, py = pts[i]
            d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / norm
            if d > best:
                best, idx = d, i
        if best <= tol:
            return [pts[0], pts[-1]]
        return dp(pts[: idx + 1])[:-1] + dp(pts[idx:])

    far = max(range(len(points)), key=lambda i: (points[i][0] - points[0][0]) ** 2 +
              (points[i][1] - points[0][1]) ** 2)
    a = dp(points[: far + 1])
    b = dp(points[far:] + [points[0]])
    return a[:-1] + b[:-1]


def main():
    src, scale, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    sys.setrecursionlimit(100000)
    w, h, ink = read_pbm(src)
    parts = []
    for loop in boundary_loops(w, h, ink):
        pts = simplify(loop, tol=0.9)
        if len(pts) >= 3:
            parts.append("M" + " L".join(f"{x / scale:.2f} {y / scale:.2f}" for x, y in pts) + " Z")
    vw, vh = w / scale, h / scale
    open(out, "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {vw:.2f} {vh:.2f}" '
        f'width="{vw:.0f}" height="{vh:.0f}"><path fill-rule="evenodd" d="'
        + " ".join(parts) + '"/></svg>')
    print(f"{len(parts)} outlines -> {out}")


main()
