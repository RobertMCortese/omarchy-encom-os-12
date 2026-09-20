# ENCOM OS-12 for Omarchy

A *Tron: Legacy* desktop for [Omarchy](https://omarchy.org): the ENCOM OS-12 look, from the boot splash to the screensaver, built as a working desktop rather than just a wallpaper. It comes in four colours — OS-12 cyan, Clu orange, Ares red and 1982 violet.

![Desktop](docs/desktop.png)

## What you get

**The look**
- A full Omarchy theme: black glass, Tron cyan, Clu-orange for alarms. Terminals, btop, editors and the shell all pick it up. Three more themes come with it ([below](#four-themes)).
- Three generated wallpapers (grid horizon, circuit board, sea of simulation).
- The ENCOM International logo on the bar, the HUD, the terminal and the boot splash.
- Square window corners and windows that *rez* in and *derezz* out.
- The **Encom-Cyan** cursor: Adwaita's shapes, recoloured with a soft cyan halo.
- Translucent terminals over the grid, and an ENCOM fastfetch readout.

**The disc wars lock screen**: behind the password field, two original fighters, a teal program and an orange sentinel, duel with identity discs on concentric ring platforms high above the arena floor. (The 1982 theme puts [a different scene](#four-themes) there.)

![Lock screen: a disc banked off the ceiling, trailing light](docs/lock.png)

![Lock screen, animated](docs/lock.gif)

- The fighters move with real motion capture (a frisbee throw, a stance and a sidestep from the CMU database), with blocks, flips, dodges and falls built on top of it.
- Throws are blocked on the defender's own disc, held like a shield in one hand or both. Sometimes they're dodged instead: a sidestep or a side flip, twist or backflip onto another ring, or a duck, sweep kick or split jump in place. Now and then one connects, knocking the fighter back a ring, or three times in ten derezzing them: their outline shatters into a hundred glowing pieces that tumble down to the arena floor.
- Discs banked off the ceiling knock out rings. A fighter who loses their footing clings to the next ring's edge, and sometimes climbs back up; otherwise the next shot sends them falling into the void. The rings rise again and the duel goes on.
- It's all drawn with plain QtQuick shapes through a hand-projected 3D camera. No Qt Quick 3D, no web view, no real lights.
- It's Omarchy's own lock with one scene added. The password and fingerprint handling are left exactly as Omarchy ships them. An installed post-update hook refreshes the clone from Omarchy's lock after every update. If the scene no longer fits, it switches back to Omarchy's own lock rather than run an out-of-date one.

**The HUD** — etched onto the desktop, below your windows:
- Chamfered console panels: system ident, live CPU / memory / temperature / battery meters, and an identity disc that tracks CPU load.
- A system-check boot cascade each time the shell starts.
- Workspace nodes and ENCOM gauges on the bar, and a chamfered launcher.

**The live Boardroom wallpaper**: the boardroom projection from the film as your desktop background, running as a live monitor of this machine:

![Boardroom](docs/boardroom.png)

- It fills the whole screen at any size. The layout keeps the width-fit scale and grows taller into the spare height; the globe, the 3D cube, the dial, the charts and the icon frames keep their shapes, and a third row of icon frames appears when there's room.

- **SYSTEM**: real events from this computer. New network connections are pinned on the globe using an offline IP database, so no address ever leaves the machine. Windows opening, journal warnings, logins, package changes, devices and periodic system samples all appear too, each with its program's icon.
- **GITHUB**: the original 2013 replay.
- **WIKIPEDIA**: live edits from around the world, pinned by language edition.
- On the desktop it shows SYSTEM. It animates only while the desktop is actually visible (an empty workspace), you're on mains power, and the screen is on and unlocked. The rest of the time it holds its last frame and uses next to no CPU. The HUD steps aside while it runs.
- It needs `gtk-layer-shell`, which the installer adds.

**The Light Cycles screensaver**: after 150 s idle, a three-on-three light cycle match in the *Tron: Legacy* arena, Clu's orange riders against the programs:

![Light Cycles](docs/lightcycles.png)

- All six cycles are AI-driven. For each possible move, the AI measures how much of the arena it could still reach, so it doesn't wind itself into dead ends. Once trapped in a pocket, it hugs the walls to make the space last. With room to spare, it hunts, cutting across the nearest enemy's path. A derezzed rider's ribbon fades and frees its space, as in the film.
- Each side has one **champion** (the longer bar on the scoreboard). Near an enemy, it searches a few moves ahead for both riders (minimax with alpha-beta pruning), scoring positions by territory: the cells it can reach before anyone else. Once walled off, it fills its remaining space as efficiently as it can. In 100 simulated rounds, champions outlasted both teammates 56% of the time, against 40% with the search switched off.
- A scoreboard shows each side's riders still in play and the rounds won. A new round starts a few seconds after one side is wiped out.
- One overhead camera follows the closest duel. It pans, zooms and slowly turns to keep that duel in frame, staying close enough that the cycles are clearly visible. Each cycle also carries a glow marker that keeps the same size on screen.
- The film's look: glossy black cycles with glowing wheel rings and body lines, Clu orange against program blue-white. Light ribbons are bright at the top and bottom edges and see-through in the middle. The arena is a dark grid inside stands drawn in bluish-white vector outlines, with rows of lamps and floodlight towers.
- None of those glows are real light sources. They're textures, lines and sprites, which keeps the Broadwell GPU's load down.
- Silent. It closes on any key or mouse movement, and the screen still locks on schedule behind it.
- The riders wear the theme's colours; on the 1982 theme they go back to the original arcade game's blue against yellow.
- Prefer the Boardroom as the screensaver? Set `"screensaver": "boardroom"` (see below). It then rotates through SYSTEM, GITHUB and WIKIPEDIA.

**Alerts**: disk nearly full, sustained heat, low battery, memory pressure, failed services and out-of-memory kills. They show in the theme's alert colour, ENCOM teal as standard: a **!** on the bar (visible over windows), a SYSTEM ALERT panel on the HUD, and in the Boardroom a SYSTEM ALERT box with an animated comms portrait, Star Fox style.

![An alert arriving in the Boardroom](docs/alert.gif)

*An incoming alert (simulated): the comms window opens, then the message slides out beside it.*

| | |
|---|---|
| ![Launcher](docs/launcher.png) | ![Terminal](docs/terminal.png) |
| ![Boot splash](docs/boot-splash.png) | |

## Four themes

The same desktop comes in four colours. Everything above follows the one you pick: the terminal and editor palettes, the wallpapers, the logo, the boot splash, the HUD and bar, the alerts and their portrait, the light cycles, the lock screen and the Boardroom projection.

![The four themes](docs/themes.png)

| Theme | | The sides |
|---|---|---|
| **ENCOM OS-12** | Tron cyan, Clu orange for alarms | PROGRAMS vs CLU |
| **ENCOM Clu** | Clu's orange, cyan for alarms | CLU vs PROGRAMS |
| **ENCOM Ares** | Ares red over black, cold blue accents | SENTINELS vs PROGRAMS |
| **ENCOM 1982** | The first film: violet and amber | USERS vs PROGRAMS |

Switch with Omarchy's own theme menu, where they're listed as *Encom Os 12*, *Encom Clu*, *Encom Ares* and *Encom Tron 82*, or with `omarchy theme set "Encom Ares"`. Nothing needs rebuilding: every piece reads the current theme's `encom.json` and repaints itself. The Boardroom is recoloured in the browser as it loads: every cyan in it turns the theme's accent and every amber the theme's second colour, each keeping its own lightness so the layout stays readable. Where a theme's accent is a colour the projection already used, the two swap places rather than collapse into one.

**1982 goes further.** The light cycles go back to the original game's blue against yellow, and to the pieces that came with the game this screensaver started from: its arena wall panels, its classic cycle model and its light trails, in place of our Legacy-era ones. (One palette key, `classic`, turns all three on.)

And the password screen is a different scene: not the disc duel but **the transfer**, our own recreation of the ride from the real world into the game world that the first film opens the grid with. Five movements on a 64-second loop, all wireframe, all generated:

1. **The kaleidoscope** — a field of short lines reflected across a grid of mirrors, folding into a new pattern as it drifts, working through teal, red, pale violet, purple and blue
2. **The tunnel** — rings of a polygon, each turned further than the last, flown down the middle of a curving path the camera banks into; grid-ruled tetromino plates tumble past and it ends on nested square frames
3. **The field** — the port opens onto sheets of board stacked one behind another, flown through: traces, dot rows, dot matrix, vias and beads of light running along tracks, the camera panning and spinning
4. **The arrival** — high over a triangulated world with those same plates floating as clouds and red beams standing off the dark cities; down through them, over ground that rises and falls, in towards the one green beam
5. **The C** — a city of extruded blocks with canyons between them around the structure that throws the beam; the camera locks onto it, tips down as it passes over, and goes out through a green kaleidoscope that hands back to the first movement

The 3D is hand-rolled — a camera basis, a perspective divide and near-plane clipping — because the flat vector look wants nothing more. Every edge is one plain QtQuick rectangle from a fixed pool, so a frame costs the same whatever is on screen, and it runs at 30 fps, as its source did at 24.

![The 1982 lock screen: the digitiser](docs/lock-82.gif)

Making your own is a script: colours in, theme out.

```bash
tools/make-theme.py                 # rebuild all variants from theme/encom-os-12
tools/make-portrait.py encom-ares   # redraw one theme's alert portrait
```

`make-theme.py` holds a small table of target colours per theme and restyles the base theme's files into new ones, generating the wallpapers, the logo, the boot art, the preview and the palette. Each palette carries `lockScene` (`duel` or `digitise`), `portrait` (which portrait is drawn: `sentinel`, `glitch` or `polyhedron`) and the two sides' names and colours. `make-portrait.py` draws the portrait as SVG frames and assembles the GIF; drop in a GIF of your own at `theme/<name>/portrait.gif` if you'd rather.

## Install

Needs Omarchy 4.x with Chromium. On a stock install every other dependency is already present, except two small cursor-building tools, which the installer offers to add.

```bash
git clone https://github.com/RobertMCortese/omarchy-encom-os-12
cd omarchy-encom-os-12
./install.sh
```

- `./install.sh --dry-run` shows every step without changing anything.
- It asks before installing the boot splash, which needs sudo and rebuilds the initramfs. `--no-plymouth` skips it.
- Every file it replaces is backed up to `~/.local/state/omarchy-encom-os-12/`, and running it again is safe.
- `omarchy update` can reset the boot splash; an installed post-update hook puts it back.

**Uninstall:** `./uninstall.sh` (also has `--dry-run`).

## Configure

`~/.config/encom-boardroom/config.json`:

| Key | Default | |
|---|---|---|
| `screensaver` | `"lightcycles"` | Which screensaver runs on idle: `"lightcycles"` or `"boardroom"` |
| `home` | Los Angeles | Where this machine sits on the globe: `{"name", "lat", "lon"}` |
| `cycle` | `["system", "github", "wikipedia"]` | Boardroom screensaver rotation |
| `cycle_seconds` | `120` | Time on each |
| `alerts` | see file | Thresholds: disk %, CPU °C, battery %, memory, swap |
| `lock_blank_seconds` | not set | How long the lock screen stays lit with no input before the display blanks. Unset keeps Omarchy's 5 seconds. After changing it, run `python3 ~/.config/omarchy/plugins/$USER.lock/encom-lock-patch.py` and `omarchy restart shell` |

- **Screensaver timeout:** Omarchy's own `idle.screensaver` in `~/.config/omarchy/shell.json`.
- **Turn the ENCOM screensaver off:** `omarchy-toggle encom-screensaver-off`, which gives you no screensaver. To get Omarchy's own back, also run `omarchy toggle screensaver`.
- **Run a screensaver now:** `encom-screensaver lightcycles` or `encom-screensaver boardroom`.
- **Live wallpaper:** `encom-wallpaper on | off | toggle | status`. Install with `--no-wallpaper` to start with it off.
- **Open the Boardroom as a window:** `encom-boardroom`.

## How it fits together

| Path | What |
|---|---|
| `theme/encom-os-12/` | The Omarchy theme, logo (+ ASCII generator) and boot art. Each theme also carries `encom.json`, the palette every piece here reads |
| `theme/encom-clu/`, `encom-ares/`, `encom-tron-82/` | The three variants, generated by `tools/make-theme.py` |
| `hud/` | Quickshell service plugin: HUD panels, alerts, idle trigger |
| `bar/` | Bar widgets and the telemetry probe |
| `shell/` | Workspace nodes, and the patch that chamfers Omarchy's launcher |
| `lock/` | The disc wars scene, the 1982 digitiser (`Digitize.qml`), the baked motion capture (`poses.js`), and the patch that adds the theme's scene to a clone of Omarchy's lock |
| `boardroom/` | Monitor server, alert checks, icon resolver, the layer-shell wallpaper and its services, and `patch.py`, which rebuilds the upstream app |
| `lightcycles/` | The 3-on-3 game: engine, AI, camera and scoreboard (`encom-game.js`), cycles and stadium (`encom-arena.js`), the pinned three.js version, and the original game's arena walls, cycle model and trail (CC0) for the 1982 theme |
| `hypr/`, `terminal/`, `fastfetch/`, `cursor/` | Look'n'feel pieces |
| `tools/` | The theme and portrait generators, how the logo was traced, and how the lock screen's motion capture was baked |

Notes for anyone hacking on it:
- The HUD is a `service` plugin, so edits to it need `omarchy restart shell`.
- The wallpaper is two user services: `encom-boardroom-server` (the monitor on port 8741) and `encom-wallpaper` (a WebKitGTK view on the layer shell's bottom layer). Logs are in `journalctl --user -u encom-wallpaper`.
- The launcher is a clone of Omarchy's menu. After an Omarchy update to the menu, re-run the installer to re-clone and re-patch it.

## Credits

This stands on other people's work. Thank you:

- **[Rob Scanlon (@arscan)](https://github.com/arscan)** built the **[ENCOM Boardroom](https://www.robscanlon.com/encom-boardroom/)**, the HTML5/WebGL recreation of the *Tron: Legacy* boardroom scene that the screensaver runs on ([source](https://github.com/arscan/encom-boardroom), MIT). The installer fetches his original at a pinned revision and patches it locally. His globe library, [encom-globe](https://github.com/arscan/encom-globe), is part of it. The in-app readme still credits him, as it should.
- **[Erich Loftis (@erichlof)](https://github.com/erichlof)** wrote **[3dLightCycles](https://github.com/erichlof/3dLightCycles)** (CC0, public domain), the three.js light cycle game the screensaver started from. The 3-on-3 version is a new engine written for this project, inspired by his.
- **[three.js](https://threejs.org)** (MIT) renders the Light Cycles arena. The installer downloads r71 from npm and verifies its checksum.
- **[Omarchy](https://omarchy.org)** by DHH and contributors: the desktop all of this is built on, and the code the workspace and launcher clones start from.
- **[DB-IP](https://db-ip.com)**: IP to City Lite database, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The installer downloads it.
- **[GNOME Adwaita](https://gitlab.gnome.org/GNOME/adwaita-icon-theme)**: the cursor shapes Encom-Cyan is recoloured from.
- **[Wikimedia EventStreams](https://stream.wikimedia.org)**: the live Wikipedia feed.
- **[Tron wiki](https://tron.fandom.com/wiki/ENCOM)**: the reference image the ENCOM logo was traced from.

*Tron*, *Tron: Legacy* and **ENCOM** are trademarks of Disney. This is an unofficial fan project, not affiliated with or endorsed by Disney. See [CREDITS.md](CREDITS.md) for licences.

## License

The code in this repository is MIT ([LICENSE](LICENSE)). That covers our own work only; third-party pieces keep their own licences, listed in [CREDITS.md](CREDITS.md).
