#!/bin/bash
# How theme/encom-os-12/logo/*.svg were made, for the record.
#
# The reference is "Encom inter logo.png" from the Tron wiki
# (https://tron.fandom.com/wiki/ENCOM): the ENCOM International mark used in
# Tron: Legacy publicity. It is small and compressed, so the mark is traced
# from a lightly blurred 6x upscale (smooth curves) and the thin
# INTERNATIONAL lettering from an unblurred one (the blur erodes it).
#
#   tools/make-logo.sh <out-dir>
set -euo pipefail
OUT=${1:?usage: make-logo.sh <out-dir>}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

curl -sfL -A "Mozilla/5.0" -o "$TMP/ref.img" \
  "https://static.wikia.nocookie.net/tron/images/e/ea/Encom_inter_logo.png/revision/latest"

prep() { magick "$TMP/ref.img" -background white -flatten -colorspace gray -level 66%,100% \
           -filter Lanczos -resize 600% "$@"; }
prep -blur 0x5 -threshold 50% "$TMP/smooth.pbm"
prep -threshold 50% "$TMP/sharp.pbm"
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
mark = " ".join(p for p, y0, y1 in smooth if y1 < 90)       # the framed ENCOM
intl = " ".join(p for p, y0, y1 in sharp if y0 > 90)        # INTERNATIONAL
note = ("<!-- ENCOM International logo, after Tron: Legacy (Disney). Traced for a "
        "fan desktop theme; ENCOM and Tron are trademarks of Disney. -->")
svg = lambda view, body: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">{note}{body}</svg>'
(out / "encom-logo.svg").write_text(svg(vb,
    f'<path fill="#a8ecff" fill-rule="evenodd" d="{mark}"/>'
    f'<path fill="#6fc3df" fill-rule="evenodd" d="{intl}"/>'))
(out / "encom-mark.svg").write_text(svg("6.5 10 320.5 74.8",
    f'<path fill="#a8ecff" fill-rule="evenodd" d="{mark}"/>'))
print("wrote", out / "encom-logo.svg", "and", out / "encom-mark.svg")
PYEOF
