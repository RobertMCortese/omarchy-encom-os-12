#!/usr/bin/env python3
"""Show the ENCOM disc wars duel behind the Omarchy lock screen's password field.

<user>.lock is a clone of the built-in omarchy.lock (made by the installer).
This makes one edit to the clone's LockView.qml: a DiscWars item (from
DiscWars.qml beside it) drawn over the blurred wallpaper and under the mouse
area and password field. Service.qml, which handles the password and
fingerprint, is never touched.

A clone does not receive Omarchy's updates to the lock, so the installer's
post-update hook (encom-lock.hook) re-clones it from the current omarchy.lock
and runs this again whenever omarchy.lock changes. The edit is applied once;
running this again is safe.
"""
import os
import sys

MARK = "// ENCOM disc wars"
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "LockView.qml")
src = open(path).read()

if MARK in src:
    print("already patched")
    sys.exit(0)

# The scene goes straight after the blurred wallpaper, before the MouseArea,
# so clicks and the password field keep working exactly as before.
OLD = """      blurMultiplier: 1.25
      contrast: -0.08
    }
"""
NEW = """      blurMultiplier: 1.25
      contrast: -0.08
    }

    // ENCOM disc wars: the duel, over the wallpaper and under the field.
    DiscWars {
      anchors.fill: parent
    }
"""

if src.count(OLD) != 1:
    sys.exit("wallpaper effect block not found — the upstream lock changed; patch by hand")
open(path, "w").write(src.replace(OLD, NEW, 1))
print("patched")
