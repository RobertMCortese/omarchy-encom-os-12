# ENCOM OS-12 for Omarchy

A *Tron: Legacy* desktop for [Omarchy](https://omarchy.org): the ENCOM OS-12 look, from the boot splash to the screensaver, built as a working desktop rather than a wallpaper.

![Desktop](docs/desktop.png)

## What you get

**The look**
- A full Omarchy theme: black glass, Tron cyan, Clu-orange for alarms. Terminals, btop, editors and the shell all pick it up.
- Three generated wallpapers (grid horizon, circuit board, sea of simulation).
- The ENCOM International logo on the bar, the HUD, the terminal and the boot splash.
- Square window corners and windows that *rez* in and *derezz* out.
- The **Encom-Cyan** cursor: Adwaita's shapes, recoloured with a soft cyan halo.
- Translucent terminals over the grid, and an ENCOM fastfetch readout.

**The HUD** — etched onto the desktop, below your windows:
- Chamfered console panels: system ident, live CPU / memory / temperature / battery meters, and an identity disc that tracks CPU load.
- A system-check boot cascade each time the shell starts.
- Workspace nodes and ENCOM gauges on the bar, and a chamfered launcher.

**The Boardroom screensaver** — after 150 s idle, the boardroom projection from the film, running as a live monitor of this machine:

![Boardroom](docs/boardroom.png)

- **SYSTEM**: real events from this computer. New network connections are pinned on the globe using an offline IP database, so no address ever leaves the machine. Windows opening, journal warnings, logins, package changes, devices and periodic system samples all appear too, each with its program's icon.
- **GITHUB**: the original 2013 replay.
- **WIKIPEDIA**: live edits from around the world, pinned by language edition.
- It rotates through them, and closes on any key or mouse movement. The screen still locks on schedule behind it.

**Alerts**: disk nearly full, sustained heat, low battery, memory pressure, failed services and out-of-memory kills. They show as an orange **!** on the bar (visible over windows), on the HUD, and in the Boardroom.

| | |
|---|---|
| ![Launcher](docs/launcher.png) | ![Terminal](docs/terminal.png) |
| ![Boot splash](docs/boot-splash.png) | |

## Install

Needs Omarchy 4.x with Chromium. On a stock install every other dependency is already present, except two small cursor-building tools, which the installer offers to add.

```bash
git clone https://github.com/<you>/omarchy-encom-os-12
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
| `home` | Los Angeles | Where this machine sits on the globe: `{"name", "lat", "lon"}` |
| `cycle` | `["system", "github", "wikipedia"]` | Screensaver rotation |
| `cycle_seconds` | `120` | Time on each |
| `alerts` | see file | Thresholds: disk %, CPU °C, battery %, memory, swap |

- **Screensaver timeout:** Omarchy's own `idle.screensaver` in `~/.config/omarchy/shell.json`.
- **Turn the Boardroom off:** `omarchy-toggle encom-boardroom-off`, which gives you no screensaver. To get Omarchy's own back, also run `omarchy toggle screensaver`.
- **Open it any time:** `encom-boardroom`.

## How it fits together

| Path | What |
|---|---|
| `theme/encom-os-12/` | The Omarchy theme, logo (+ ASCII generator) and boot art |
| `hud/` | Quickshell service plugin: HUD panels, alerts, idle trigger |
| `bar/` | Bar widgets and the telemetry probe |
| `shell/` | Workspace nodes, and the patch that chamfers Omarchy's launcher |
| `boardroom/` | Monitor server, alert checks, icon resolver, and `patch.py`, which rebuilds the upstream app |
| `hypr/`, `terminal/`, `fastfetch/`, `cursor/` | Look'n'feel pieces |
| `tools/` | How the logo was traced |

Notes for anyone hacking on it:
- The HUD is a `service` plugin, so edits to it need `omarchy restart shell`.
- The launcher is a clone of Omarchy's menu. After an Omarchy update to the menu, re-run the installer to re-clone and re-patch it.

## Credits

This stands on other people's work. Thank you:

- **[Rob Scanlon (@arscan)](https://github.com/arscan)** built the **[ENCOM Boardroom](https://www.robscanlon.com/encom-boardroom/)**, the HTML5/WebGL recreation of the *Tron: Legacy* boardroom scene that the screensaver runs on ([source](https://github.com/arscan/encom-boardroom), MIT). The installer fetches his original at a pinned revision and patches it locally. His globe library, [encom-globe](https://github.com/arscan/encom-globe), is part of it. The in-app readme still credits him, as it should.
- **[Omarchy](https://omarchy.org)** by DHH and contributors: the desktop all of this is built on, and the code the workspace and launcher clones start from.
- **[DB-IP](https://db-ip.com)**: IP to City Lite database, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The installer downloads it.
- **[GNOME Adwaita](https://gitlab.gnome.org/GNOME/adwaita-icon-theme)**: the cursor shapes Encom-Cyan is recoloured from.
- **[Wikimedia EventStreams](https://stream.wikimedia.org)**: the live Wikipedia feed.
- **[Tron wiki](https://tron.fandom.com/wiki/ENCOM)**: the reference image the ENCOM logo was traced from.

*Tron*, *Tron: Legacy* and **ENCOM** are trademarks of Disney. This is an unofficial fan project, not affiliated with or endorsed by Disney. See [CREDITS.md](CREDITS.md) for licences.

## License

The code in this repository is MIT ([LICENSE](LICENSE)). That covers our own work only; third-party pieces keep their own licences, listed in [CREDITS.md](CREDITS.md).
