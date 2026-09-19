"""Find an icon for a program, the way a desktop would, for the Boardroom's
picture panels.

A program name (a window class, a process name) is matched against installed
.desktop files -- by file name, StartupWMClass, Exec and Name -- to get its
Icon=, which is then looked up in the icon themes. SVGs are rasterised once
with rsvg-convert and cached. Everything is local.
"""
import configparser
import os
import pathlib
import re
import shutil
import subprocess
import threading

HOME = pathlib.Path.home()
CACHE = HOME / ".cache" / "encom-boardroom" / "icons"

APP_DIRS = [HOME / ".local/share/applications", pathlib.Path("/usr/share/applications"),
            pathlib.Path("/var/lib/flatpak/exports/share/applications")]
ICON_ROOTS = [HOME / ".local/share/icons", HOME / ".icons", pathlib.Path("/usr/share/icons")]
PIXMAPS = pathlib.Path("/usr/share/pixmaps")

# Big raster first: the panels show icons up to 184px.
SIZE_RANK = {"256x256": 0, "256x256@2x": 1, "512x512": 2, "128x128@2x": 3, "128x128": 4,
             "scalable": 5, "96x96": 6, "64x64": 7, "48x48@2x": 8, "48x48": 9}

SAFE = re.compile(r"[^a-z0-9._-]+")


def _theme_order():
    try:
        current = (HOME / ".local/state/omarchy/current/theme/icons.theme").read_text().strip()
    except OSError:
        current = ""
    order = [current] if current else []
    # Yaru-* themes inherit from Yaru; everything falls back to hicolor.
    for fallback in ("Yaru-blue", "Yaru", "hicolor", "Adwaita", "breeze"):
        if fallback not in order:
            order.append(fallback)
    return order


class Icons:
    def __init__(self):
        self._lock = threading.Lock()
        self._apps = None       # lowercased program key -> Icon= value
        self._files = None      # icon name -> (theme rank, size rank, path)
        self._resolved = {}     # url key -> png path (or None)

    # ── indexes, built lazily on first use ────────────────────────────────
    def _index_apps(self):
        apps = {}
        for base in APP_DIRS:
            if not base.is_dir():
                continue
            for desktop in sorted(base.glob("*.desktop")):
                parser = configparser.ConfigParser(interpolation=None, strict=False)
                try:
                    parser.read(desktop, encoding="utf-8")
                    entry = parser["Desktop Entry"]
                except (configparser.Error, KeyError, UnicodeDecodeError):
                    continue
                icon = entry.get("Icon", "").strip()
                if not icon:
                    continue
                keys = {desktop.stem, desktop.stem.rsplit(".", 1)[-1],
                        entry.get("StartupWMClass", ""), entry.get("Name", "")}
                exec_line = entry.get("Exec", "").split()
                if exec_line:
                    keys.add(os.path.basename(exec_line[0]))
                for key in keys:
                    key = key.strip().lower()
                    if key and key not in apps:      # user entries win (listed first)
                        apps[key] = icon
        return apps

    def _index_files(self):
        files = {}
        for theme_rank, theme in enumerate(_theme_order()):
            for root in ICON_ROOTS:
                base = root / theme
                if not base.is_dir():
                    continue
                for dirpath, _dirs, names in os.walk(base):
                    size_dir = pathlib.Path(dirpath).relative_to(base).parts
                    if not size_dir or size_dir[0] not in SIZE_RANK:
                        continue
                    size_rank = SIZE_RANK[size_dir[0]]
                    for name in names:
                        stem, ext = os.path.splitext(name)
                        if ext not in (".png", ".svg") or stem.endswith("-symbolic"):
                            continue
                        rank = (theme_rank, size_rank)
                        best = files.get(stem)
                        if best is None or rank < best[:2]:
                            files[stem] = (theme_rank, size_rank, os.path.join(dirpath, name))
        if PIXMAPS.is_dir():
            for f in PIXMAPS.iterdir():
                if f.suffix in (".png", ".svg"):
                    files.setdefault(f.stem, (99, 99, str(f)))
        return files

    def _ensure(self):
        with self._lock:
            if self._apps is None:
                self._apps = self._index_apps()
                self._files = self._index_files()

    # ── lookup ────────────────────────────────────────────────────────────
    def icon_name_for(self, program):
        """Icon= value for a program name or window class, if one is installed."""
        self._ensure()
        p = program.strip().lower()
        if not p:
            return None
        for key in (p, p.rsplit(".", 1)[-1], p.split("-", 1)[0]):
            if key in self._apps:
                return self._apps[key]
        return p if p in self._files else None

    def key_for(self, *candidates):
        """URL-safe key for the first candidate that resolves to a real icon."""
        for name in candidates:
            if not name:
                continue
            key = SAFE.sub("-", str(name).lower()).strip("-")
            if key and self.path(key, str(name)):
                return key
        return None

    def path(self, key, name=None):
        """PNG path for a key; resolves and caches on first use."""
        with self._lock:
            if key in self._resolved:
                return self._resolved[key]
        result = self._resolve(name or key)
        with self._lock:
            self._resolved[key] = result
        return result

    def _resolve(self, name):
        self._ensure()
        if os.path.isabs(name) and os.path.isfile(name):
            source = name
        else:
            found = self._files.get(name)
            source = found[2] if found else None
        if not source:
            return None
        if source.endswith(".png"):
            return source
        CACHE.mkdir(parents=True, exist_ok=True)
        out = CACHE / (SAFE.sub("-", name.lower()) + ".png")
        if not out.exists():
            if not shutil.which("rsvg-convert"):
                return None
            try:
                subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", "-a",
                                "-o", str(out), source], check=True, timeout=10,
                               capture_output=True)
            except (OSError, subprocess.SubprocessError):
                return None
        return str(out)
