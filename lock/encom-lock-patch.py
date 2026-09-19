#!/usr/bin/env python3
"""Show the ENCOM lock scene behind the Omarchy lock screen's password field.

<user>.lock is a clone of the built-in omarchy.lock (made by the installer).
This makes one edit to the clone's LockView.qml: a DiscWars item (from
DiscWars.qml beside it) drawn over the blurred wallpaper and under the mouse
area and password field.

Optionally, one more: how long the lock screen stays lit with no input
before Omarchy blanks the display (5 seconds by default). Only when
"lock_blank_seconds" is set in ~/.config/encom-boardroom/config.json does
this change that one timer's interval in the clone's Service.qml, and it
notes Omarchy's own value beside it so that removing the setting puts it
back. Nothing else in Service.qml, which handles the password and
fingerprint, is touched; if the timer is not where it was, it is left alone.

A clone does not receive Omarchy's updates to the lock, so the installer's
post-update hook (encom-lock.hook) re-clones it from the current omarchy.lock
and runs this again whenever omarchy.lock changes. Running this again is
safe; run it after changing the setting, then restart the shell
(omarchy restart shell) for the lock to pick it up.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.expanduser("~/.config/encom-boardroom/config.json")

# The lock scene: the disc duel, or another the theme asks for (1982 uses
# the digitiser), with the current theme's palette handed to it.
SCENE_BLOCK = """    // ENCOM lock scene: the theme's scene, over the wallpaper and under the
    // password field, in the theme's colours.
    Loader {
      id: encomScene
      anchors.fill: parent
      property var themePalette: ({})
      source: themePalette.lockScene === "digitise" ? "Digitize.qml" : "DiscWars.qml"
      onLoaded: item.encomPalette = Qt.binding(function () { return encomScene.themePalette })
    }

    FileView {
      path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/encom.json"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: { try { encomScene.themePalette = JSON.parse(text()) } catch (e) { } }
      onLoadFailed: encomScene.themePalette = ({})
    }
"""

# Where the scene goes: straight after the blurred wallpaper, before the
# MouseArea, so clicks and the password field keep working as before.
ANCHOR = """      blurMultiplier: 1.25
      contrast: -0.08
    }
"""


def patch_view():
    """Put the theme's scene behind the password field."""
    path = os.path.join(HERE, "LockView.qml")
    src = open(path).read()
    if "// ENCOM lock scene" in src:
        return "scene: already in"

    # An earlier install: replace whatever was put in with the current block.
    old = re.search(r"\n    // ENCOM disc wars.*?\n    \}\n(?:\n    FileView \{.*?\n    \}\n)?",
                    src, re.S)
    if old:
        src = src[:old.start()] + "\n" + SCENE_BLOCK + src[old.end():]
    else:
        if src.count(ANCHOR) != 1:
            sys.exit("wallpaper effect block not found — the upstream lock changed; patch by hand")
        src = src.replace(ANCHOR, ANCHOR + "\n" + SCENE_BLOCK, 1)

    for imp in ("import Quickshell\n", "import Quickshell.Io\n"):
        if imp not in src:
            src = src.replace("import QtQuick\n", "import QtQuick\n" + imp, 1)
    open(path, "w").write(src)
    return "scene: in" if old else "scene: added"


def blank_seconds():
    """The opt-in setting, or None when unset (or unusable)."""
    try:
        value = json.load(open(CONFIG)).get("lock_blank_seconds")
    except (OSError, ValueError):
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return max(5, min(3600, int(value)))


def patch_blank():
    """How long the lit lock screen waits for input before blanking."""
    path = os.path.join(HERE, "Service.qml")
    src = open(path).read()
    timer = re.compile(r"(    id: idleBlankTimer\n    interval: )(\d+)"
                       r"(?:  // ENCOM lock_blank_seconds \(Omarchy: (\d+)\))?\n")
    found = timer.findall(src)
    if len(found) != 1:
        return "display blank: timer not found, left as Omarchy has it"
    current, omarchy = int(found[0][1]), int(found[0][2] or found[0][1])
    seconds = blank_seconds()
    if seconds is None:
        line, note = str(omarchy), "Omarchy's %g s" % (omarchy / 1000)
    else:
        line = "%d  // ENCOM lock_blank_seconds (Omarchy: %d)" % (seconds * 1000, omarchy)
        note = "%d s (lock_blank_seconds)" % seconds
    patched = timer.sub(lambda m: m.group(1) + line + "\n", src, count=1)
    if patched != src:
        open(path, "w").write(patched)
        return "display blank: " + note + ", was %g s" % (current / 1000)
    return "display blank: " + note


print(patch_view())
print(patch_blank())
