# Credits and licences

## ENCOM Boardroom — Rob Scanlon

The live wallpaper (and optional screensaver) is **Rob Scanlon's [ENCOM Boardroom](https://www.robscanlon.com/encom-boardroom/)**
([github.com/arscan/encom-boardroom](https://github.com/arscan/encom-boardroom)), an HTML5/WebGL
recreation of the boardroom scene in *Tron: Legacy*. It is used under the MIT licence:

> The MIT License (MIT)
> Copyright (c) 2014-2017 Robert Scanlon
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without
> restriction, including without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
> BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This repository does not contain his code. `install.sh` clones it at the revision in
`boardroom/UPSTREAM_REV`, keeps his licence alongside it, and `boardroom/patch.py` applies the
local changes:
- a SYSTEM stream in place of the random test stream
- captions derived from the data
- buffering of events that arrive during the intro
- alert rows

His own "created by @arscan" credit inside the app is left as it is.

## 3dLightCycles — Erich Loftis

The Light Cycles screensaver started as **Erich Loftis's
[3dLightCycles](https://github.com/erichlof/3dLightCycles)**, a three.js light cycle game after
*Tron*, which he dedicated to the public domain under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). The first version here
patched his game directly. Three-on-three play needed a different engine, so the current version
is new code in `lightcycles/` (a shared collision grid, AI, derez and rounds), written for this
project and inspired by his. No licence terms apply to his work, but it is credited here all the
same, with thanks.

Three of his files are shipped as they are, for the 1982 theme, which asks for the pieces the
original game had rather than the Legacy-era ones drawn here:

| File | What |
|---|---|
| `lightcycles/arenaWalls2.png` | The arena wall panels |
| `lightcycles/classic-cycle.json` | The classic 1982 light cycle model |
| `lightcycles/classic-trail.png` | The light trail |

They are CC0, so no terms attach, and the thanks stand.

## CMU Graphics Lab Motion Capture Database

The lock screen fighters move with motion capture from the CMU Graphics Lab Motion Capture
Database: subject 79 trial 92 (a frisbee throw), subject 124 trial 9 (a stance) and subject 15
trial 1 (a sidestep). The database is free to use, including in products, but not to resell as
data. `lock/poses.js` holds only the joint positions the scene draws, baked by
`tools/bake-poses.py`. As CMU asks:

> The data used in this project was obtained from mocap.cs.cmu.edu.
> The database was created with funding from NSF EIA-0196217.

## three.js

The Light Cycles screensaver runs on [three.js](https://threejs.org) r71 (MIT, © three.js
authors). `install.sh` downloads `three.min.js` from npm at the version in
`lightcycles/THREE_VERSION` and checks it against the SHA-256 recorded there. The cycles, ribbons,
arena and stadium are drawn from code and canvas textures; no image assets are used.

## Omarchy

Built on [Omarchy](https://omarchy.org) (github.com/basecamp/omarchy). The workspace nodes
(`shell/workspaces/Workspaces.qml`) are adapted from Omarchy's workspace widget. The chamfered
launcher is Omarchy's own menu, cloned on your machine by `omarchy plugin clone` and patched by
`shell/menu/encom-chamfer-patch.py`; this repository does not copy the menu. The lock screen works
the same way: Omarchy's lock is cloned on your machine and `lock/encom-lock-patch.py` adds the
disc wars scene (`lock/DiscWars.qml`, original to this project) to it.

## DB-IP

IP geolocation by [DB-IP](https://db-ip.com), "IP to City Lite" database, licensed under
[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
It is downloaded by the installer, not stored here.

## Adwaita cursors

The Encom-Cyan cursor is generated on install by recolouring the cursors of GNOME's
[Adwaita icon theme](https://gitlab.gnome.org/GNOME/adwaita-icon-theme) (CC BY-SA 3.0 /
LGPL-3.0). This repository contains only the script that does it (`cursor/build.sh`).

## Wikimedia

The live Wikipedia view reads Wikimedia's public
[EventStreams](https://wikitech.wikimedia.org/wiki/Event_Platform/EventStreams) recentchange feed,
only while that view is on screen. Edit content is © its contributors under CC BY-SA.

## ENCOM, Dillinger Systems, Tron and Disney

*Tron*, *Tron: Legacy*, *Tron: Ares*, **ENCOM** and **Dillinger Systems** are trademarks of Disney.
Two wordmarks here were traced from reference images on the Tron wiki:

| Logo | Reference | Traced by |
|---|---|---|
| ENCOM International, in `theme/tron-legacy/logo/` | [Tron wiki: ENCOM](https://tron.fandom.com/wiki/ENCOM) | `tools/make-logo.sh` |
| Dillinger Systems, in `theme/dillinger-systems/logo/` | [Tron wiki: Dillinger Systems](https://tron.fandom.com/wiki/Dillinger_Systems) | `tools/make-dillinger-logo.sh` |
| TRON: LEGACY, in `theme/tron-legacy/logo/` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Tron_Legacy_Logo.svg) | `tools/make-tron-logos.sh` |
| TRON (1982), in `theme/tron-1982/logo/` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Tron_(Disney),_Logo.svg) | `tools/make-tron-logos.sh` |

The CLU wordmark (`theme/clu/logo/clu-mark.svg`) is not from the films: there is no CLU logo, so
`tools/make-clu-logo.py` letters one in ENCOM's face, taking the C from the traced ENCOM mark and
drawing the L and U to its measurements.

This is an unofficial fan project, not affiliated with or endorsed by Disney; neither logo is
covered by this repository's MIT licence.

Two comms portraits on the Boardroom's alert box are short clips from the films (© Disney),
reduced in size and colour depth. Both are included as fan use and, like the logos, are not
covered by this repository's MIT licence:

| File | Clip |
|---|---|
| `boardroom/assets/alert-portrait.gif` | Marv, Sam Flynn's Boston terrier, from *Tron: Legacy* |
| `theme/dillinger-systems/portrait.gif` | The Master Control Program from *Tron* (1982) |

The other themes' portraits are drawn from code by `tools/make-portrait.py` and are ours.
