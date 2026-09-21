#!/usr/bin/env python3
"""Stamp discwars/index.html's script tags with a hash of what they load.

A browser caches index.html and each script separately, so without this a
viewer can end up holding a new page and an old engine. That combination
fails in the worst way: the page offers a control the engine has never
heard of, the click throws, and nothing happens at all.

Versioning each src by content makes the mismatch impossible -- new markup
asks for a URL the cache has never seen, and old markup keeps the engine it
was written against. Run this after changing anything under discwars/.
"""
import hashlib
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parent / "discwars"
PAGE = APP / "index.html"
SCRIPTS = ("palette.js", "poses.js", "discwars.js")


def stamp(name):
    return hashlib.sha256((APP / name).read_bytes()).hexdigest()[:8]


page = PAGE.read_text()
changed = []
for name in SCRIPTS:
    want = stamp(name)
    # Matches the bare name and any version already on it.
    pattern = re.compile(r'(<script src="%s)(\?v=[0-9a-f]+)?(")' % re.escape(name))
    found = pattern.search(page)
    if not found:
        raise SystemExit(f"{name} is not loaded by {PAGE.name}")
    if (found.group(2) or "")[3:] != want:
        changed.append(f"{name} -> {want}")
    page = pattern.sub(r'\g<1>?v=%s\g<3>' % want, page)

PAGE.write_text(page)
print("\n".join(changed) if changed else "already stamped; nothing to do")
