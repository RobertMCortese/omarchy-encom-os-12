#!/bin/bash
# How theme/dillinger-systems/logo/*.svg were made, for the record.
#
# The reference is the Dillinger Systems mark from the Tron wiki
# (https://tron.fandom.com/wiki/Dillinger_Systems): the company's wordmark as
# used in Tron: Ares publicity. It is white on black, so it is inverted before
# tracing. The wordmark and the letterspaced SYSTEMS line are traced
# separately — the thin lettering erodes under the blur that keeps the heavy
# italic's edges smooth — and then recombined.
#
#   tools/make-dillinger-logo.sh <out-dir>
set -euo pipefail
OUT=${1:?usage: make-dillinger-logo.sh <out-dir>}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

curl -sfL -A "Mozilla/5.0" -o "$TMP/ref.img" \
  "https://static.wikia.nocookie.net/tron/images/d/de/Dillinger-systems-personal-computer-suite-v0-qr3da7c6w4zf1.jpg/revision/latest"

# White on black becomes black on white, then up to a size the tracer can
# follow cleanly.
prep() { magick "$TMP/ref.img" -colorspace gray -negate \
           -filter Lanczos -resize 600% "$@"; }
prep -blur 0x4 -threshold 58% "$TMP/smooth.pbm"
prep -threshold 60% "$TMP/sharp.pbm"
python3 "$HERE/trace.py" "$TMP/smooth.pbm" 6 "$TMP/smooth.svg"
python3 "$HERE/trace.py" "$TMP/sharp.pbm" 6 "$TMP/sharp.svg"

python3 - "$TMP" "$OUT" <<'PYEOF'
import re, sys, pathlib
tmp, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

def loops(path):
    s = path.read_text()
    d = re.search(r' d="([^"]+)"', s).group(1)
    res = []
    for part in d.split("Z"):
        nums = [float(v) for v in re.findall(r"-?\d+\.?\d*", part)]
        if nums:
            res.append((part.strip() + " Z", min(nums[1::2]), max(nums[1::2])))
    return res, re.search(r'viewBox="([^"]+)"', s).group(1)

smooth, vb = loops(tmp / "smooth.svg")
sharp, _ = loops(tmp / "sharp.svg")
# The wordmark sits above the SYSTEMS line; the triangle under the g crosses
# it, so it is kept with the wordmark it hangs from.
SPLIT = 118
mark = " ".join(p for p, y0, y1 in smooth if y0 < SPLIT)
sysline = " ".join(p for p, y0, y1 in sharp if y0 >= SPLIT)
note = ("<!-- Dillinger Systems logo, after Tron: Ares (Disney). Traced for a "
        "fan desktop theme; Dillinger Systems and Tron are trademarks of Disney. -->")
svg = lambda view, body: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">{note}{body}</svg>'
(out / "dillinger-logo.svg").write_text(svg(vb,
    f'<path fill="#ffd9d6" fill-rule="evenodd" d="{mark}"/>'
    f'<path fill="#ff6a60" fill-rule="evenodd" d="{sysline}"/>'))
(out / "dillinger-mark.svg").write_text(svg(vb,
    f'<path fill="#ffd9d6" fill-rule="evenodd" d="{mark}"/>'))
print("wrote", out / "dillinger-logo.svg", "and", out / "dillinger-mark.svg")
PYEOF
