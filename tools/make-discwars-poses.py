#!/usr/bin/env python3
"""Re-emit lock/poses.js as a plain script the web page can load.

The lock screen's copy is a QML library (`.pragma library`, bare `var`s),
which a browser cannot read. This carries the same baked clips over to
discwars/poses.js as one global, so the two stay from a single source:
re-run it after tools/bake-poses.py.
"""
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "lock" / "poses.js"
OUT = HERE.parent / "discwars" / "poses.js"

src = SRC.read_text()
fps = int(re.search(r"var fps = (\d+)", src).group(1))
joints = json.loads(re.search(r"var joints = (\[.*?\]);", src, re.S).group(1))
clips = json.loads(re.search(r"var clips = (\{.*\})\s*;?\s*$", src, re.S)
                   .group(1).rstrip().rstrip(";"))

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(
    "// Baked from the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu):\n"
    "// 79_92 (frisbee throw), 124_09 (stance), 15_01 (sidestep).\n"
    "// Generated from lock/poses.js by tools/make-discwars-poses.py -- do not edit.\n"
    "window.POSES = " + json.dumps({"fps": fps, "joints": joints, "clips": clips},
                                   separators=(",", ":")) + ";\n")
summary = ", ".join(f"{name} {len(clip['frames'])}" for name, clip in clips.items())
print(f"{OUT.relative_to(HERE.parent)}: {OUT.stat().st_size} bytes, clips {summary}")
