#!/usr/bin/env python3
"""ENCOM Boardroom: local server and live monitor for this machine.

Serves the patched Boardroom app (app/) on 127.0.0.1 and streams real events
from this machine to it over Server-Sent Events at /events.js, the endpoint the
upstream page already listens on. Standard library only.

Event sources, each a small collector thread:
  NET   new outbound TCP connections (ss), placed on the globe by the offline
        DB-IP database -- no IP ever leaves the machine for a lookup
  APP   windows opening (Hyprland event socket)
  LOG   journal warnings and errors
  AUTH  sudo, polkit, logind sessions, ssh (journal)
  PKG   package installs, upgrades and removals (pacman.log)
  HW    USB, disk and network devices appearing or leaving (udev)
  SYS   periodic CPU / memory / temperature / battery sample

Modes:
  server.py --screensaver   serve, open a fullscreen kiosk window with the
                            org.omarchy.screensaver class (so Omarchy's idle
                            service treats it as its screensaver), and exit on
                            the first input, when the window closes, or when
                            the session locks
  server.py                 same, but a normal app window with no auto-exit
  server.py --serve-only    just serve on --port (for development)
"""
import argparse
import datetime as dt
import http.server
import ipaddress
import json
import os
import pathlib
import queue
import re
import shutil
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE / "app"
sys.path.insert(0, str(HERE / "geo"))
import mmdb  # noqa: E402
sys.path.insert(0, str(HERE))
import icons  # noqa: E402
import checks  # noqa: E402

CONFIG_PATH = pathlib.Path.home() / ".config" / "encom-boardroom" / "config.json"
STATE_DIR = pathlib.Path.home() / ".local" / "state" / "encom-boardroom"
CHROMIUM_PROFILE = pathlib.Path.home() / ".cache" / "encom-boardroom" / "chromium"
TELEMETRY = pathlib.Path.home() / ".config" / "omarchy" / "bar" / "scripts" / "encom-telemetry"

DEFAULT_CONFIG = {
    # Where this machine sits on the globe. PST8PDT carries no coordinates,
    # so this is a sensible default; change it to your city.
    "home": {"name": "HOME", "lat": 34.05, "lon": -118.24},
    "sample_seconds": 15,
    # Streams the screensaver cycles through, and how long each is shown.
    # system: this machine; github: the 2013 replay; wikipedia: live public
    # edits (needs internet, and only connects while that view is showing).
    "cycle": ["system", "github", "wikipedia"],
    "cycle_seconds": 120,
    # Alert thresholds: see checks.DEFAULTS. Written out here so they are
    # visible in the generated config file.
    "alerts": dict(checks.DEFAULTS),
}

STOP = threading.Event()


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, file=sys.stderr, flush=True)


def load_config():
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        user = json.loads(CONFIG_PATH.read_text())
        cfg.update({k: v for k, v in user.items() if k != "home"})
        cfg["home"].update(user.get("home", {}))
    except FileNotFoundError:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
    except (OSError, ValueError) as exc:
        log("config ignored:", exc)
    return cfg


CONFIG = load_config()
HOME = CONFIG["home"]

ICONS = icons.Icons()
DISC_ICON = str(HERE / "assets" / "disc.png")
PORT = 0   # set once the server is bound; icon URLs are absolute so the
           # page de-duplicates them (upstream only does so for http URLs)


# ── Event bus ──────────────────────────────────────────────────────────────
class Bus:
    """Fan events out to connected pages, at a pace the globe can show.

    Each stream (system, wikipedia) has its own queue and pacing, and a page
    subscribes to one stream, so a flood on one never starves another.
    Bursts are smoothed to a few events a second; beyond a short backlog the
    oldest are dropped, since a monitor that lags minutes behind is worse than
    one that skips a few. Meta (link status) goes to everyone.
    """

    RATE = 4.0         # events per second per stream, maximum
    BACKLOG = 60

    def __init__(self):
        self._lock = threading.Lock()
        self._subs = []            # (stream, queue)
        self._pending = {}         # stream -> queue
        self.last_meta = None

    def subscribe(self, stream):
        q = queue.Queue(maxsize=200)
        with self._lock:
            self._subs.append((stream, q))
            # A page that connects mid-run gets the current link status now
            # rather than at the next sample.
            if self.last_meta:
                q.put_nowait(self.last_meta)
        return q

    def unsubscribe(self, q):
        with self._lock:
            self._subs = [(s, sq) for s, sq in self._subs if sq is not q]

    def listening(self, stream):
        with self._lock:
            return any(s in (stream, "all") for s, _ in self._subs)

    def backlog(self, stream):
        q = self._pending.get(stream)
        return q.qsize() if q else 0

    def publish(self, event, immediate=False):
        stream = event.get("stream")
        if stream == "meta":
            self.last_meta = event
        if immediate:
            self._deliver(event)
            return
        with self._lock:
            q = self._pending.get(stream)
            if q is None:
                q = self._pending[stream] = queue.Queue()
                threading.Thread(target=self._pump, args=(stream, q), daemon=True,
                                 name="bus-" + stream).start()
        if q.qsize() >= self.BACKLOG:
            try:
                q.get_nowait()
            except queue.Empty:
                pass
        q.put(event)

    def _deliver(self, event):
        stream = event.get("stream")
        with self._lock:
            subs = [q for s, q in self._subs if stream == "meta" or s in (stream, "all")]
        for q in subs:
            try:
                q.put_nowait(event)
            except queue.Full:
                pass

    def _pump(self, stream, pending):
        interval = 1.0 / self.RATE
        while not STOP.is_set():
            # Hold events until a page is listening: the startup scan of
            # existing connections is what populates the globe, and it runs
            # before the browser has connected.
            if not self.listening(stream):
                STOP.wait(0.25)
                continue
            try:
                event = pending.get(timeout=0.5)
            except queue.Empty:
                continue
            if stream == "system":
                History.record()
            self._deliver(event)
            time.sleep(interval)


BUS = Bus()


def emit(kind, who, title, *, latlon=None, place=None, size="", popularity="",
         stream="system", pin_home=True, icon=(), alert=False):
    """Publish one Boardroom message.

    System events without a location pin at home; pass pin_home=False for
    events that have no place (a registered Wikipedia editor), which then list
    in the live feed without a globe pin.
    """
    if latlon is None and pin_home:
        latlon = (HOME["lat"], HOME["lon"])
        place = place or HOME["name"]
    event = {
        "stream": stream,
        "type": kind,
        "username": str(who)[:40],
        "title": str(title)[:90],
        "location": str(place or "")[:40],
        "size": size,
        "popularity": popularity,
    }
    if latlon is not None:
        event["latlon"] = {"lat": latlon[0], "lon": latlon[1]}
    if alert:
        event["alert"] = True
    key = ICONS.key_for(*icon) if icon and PORT else None
    if key:
        event["picSmall"] = event["picLarge"] = f"http://127.0.0.1:{PORT}/icon/{key}"
    BUS.publish(event)


def app_icon(program, *fallbacks):
    """Icon candidates for a program: its installed icon, then fallbacks."""
    return (ICONS.icon_name_for(program), *fallbacks)


# ── History (the HISTORIC PERFORMANCE chart) ──────────────────────────────
class History:
    """Daily activity: journal entries per day, plus this monitor's own event
    counts, which it records as it runs so the chart fills in over time."""

    PATH = STATE_DIR / "history.json"
    _lock = threading.Lock()
    _today = {}

    @classmethod
    def record(cls):
        day = dt.date.today().isoformat()
        with cls._lock:
            cls._today[day] = cls._today.get(day, 0) + 1

    @classmethod
    def flush(cls):
        with cls._lock:
            if not cls._today:
                return
            pending, cls._today = cls._today, {}
        try:
            saved = json.loads(cls.PATH.read_text())
        except (OSError, ValueError):
            saved = {}
        for day, n in pending.items():
            saved[day] = saved.get(day, 0) + n
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = cls.PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(saved, sort_keys=True))
        tmp.replace(cls.PATH)

    @classmethod
    def series(cls, max_days=120):
        counts = {}
        try:
            out = subprocess.run(["journalctl", "-q", "--no-pager", "-o", "short-unix"],
                                 capture_output=True, text=True, timeout=20).stdout
            for line in out.splitlines():
                head = line.split(" ", 1)[0]
                try:
                    ts = float(head)
                except ValueError:
                    continue
                if ts < 1e9:
                    continue
                day = dt.date.fromtimestamp(ts).isoformat()
                counts[day] = counts.get(day, 0) + 1
        except (OSError, subprocess.SubprocessError) as exc:
            log("journal history unavailable:", exc)
        try:
            for day, n in json.loads(cls.PATH.read_text()).items():
                counts[day] = counts.get(day, 0) + n
        except (OSError, ValueError):
            pass
        if not counts:
            return []

        first = dt.date.fromisoformat(min(counts))
        today = dt.date.today()
        first = max(first, today - dt.timedelta(days=max_days - 1))
        series = []
        day = first
        while day <= today:
            n = counts.get(day.isoformat(), 0)
            series.append({"year": day.year, "month": day.month, "day": day.day, "events": n})
            day += dt.timedelta(days=1)
        # The ticker divides by the first day, so start on a day with activity.
        while series and series[0]["events"] == 0:
            series.pop(0)
        return series


# ── Alerts ─────────────────────────────────────────────────────────────────
class Alerts:
    """Conditions worth interrupting for. Each alert is raised once, stays up
    while its condition holds, and is announced again as RESOLVED when it
    clears. Journal-driven alerts (a crash, an OOM kill) have no condition to
    watch, so they expire after TRANSIENT_SECONDS."""

    TRANSIENT_SECONDS = 300

    def __init__(self):
        self._lock = threading.Lock()
        self.active = {}          # key -> {"level", "who", "title", "since", "expires"}

    def raise_(self, key, level, who, title, expires=None):
        with self._lock:
            if key in self.active:
                if expires:
                    self.active[key]["expires"] = expires
                return
            self.active[key] = {"level": level, "who": who, "title": title,
                                "since": time.time(), "expires": expires}
        log(f"alert {level} {key}: {title}")
        emit("ALERT", who, f"{level}: {title}", size=level, alert=True,
             icon=("dialog-error" if level == "CRIT" else "dialog-warning",))
        BUS.publish({"stream": "alert", "action": "raise", "key": key, "level": level,
                     "who": who, "title": title}, immediate=True)

    def clear(self, key):
        with self._lock:
            item = self.active.pop(key, None)
        if not item:
            return
        log(f"alert cleared {key}")
        emit("OK", item["who"], f"RESOLVED: {item['title']}", size="OK",
             icon=("emblem-default", "dialog-information"))
        BUS.publish({"stream": "alert", "action": "clear", "key": key}, immediate=True)

    def transient(self, key, level, who, title):
        self.raise_(key, level, who, title[:120], expires=time.time() + self.TRANSIENT_SECONDS)

    def snapshot(self):
        with self._lock:
            return [{"key": k, **{f: v[f] for f in ("level", "who", "title")}}
                    for k, v in sorted(self.active.items(), key=lambda kv: kv[1]["since"])]

    def expire(self):
        now = time.time()
        with self._lock:
            due = [k for k, v in self.active.items() if v["expires"] and v["expires"] < now]
        for key in due:
            self.clear(key)

    def set(self, key, condition, level, who, title):
        if condition:
            self.raise_(key, level, who, title)
        else:
            self.clear(key)

ALERTS = Alerts()


def alert_collector():
    """Every 20 seconds: run the shared checks and raise or clear to match.

    Journal-driven alerts are raised live by journal_collector and expire on
    their own, so the diff only clears keys that the checks own.
    """
    state = {}
    owned = set()
    while not STOP.is_set():
        current = {a["key"]: a for a in checks.evaluate(state)}
        for key, a in current.items():
            ALERTS.raise_(key, a["level"], a["who"], a["title"])
        for key in owned - current.keys():
            ALERTS.clear(key)
        owned = set(current)
        ALERTS.expire()
        STOP.wait(20)


# ── Collectors ─────────────────────────────────────────────────────────────
def collector(fn):
    def run():
        while not STOP.is_set():
            try:
                fn()
            except Exception as exc:  # a broken source must not take the monitor down
                log(f"{fn.__name__} failed: {exc!r}; retrying in 10s")
            STOP.wait(10)
    return threading.Thread(target=run, daemon=True, name=fn.__name__)


def follow(cmd):
    """Yield stdout lines of a long-running command until STOP."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            text=True, bufsize=1)
    CHILDREN.append(proc)
    try:
        for line in proc.stdout:
            if STOP.is_set():
                break
            yield line.rstrip("\n")
    finally:
        proc.terminate()


CHILDREN = []

_GEO = None
_GEO_LOCK = threading.Lock()


def geolocate(ip):
    global _GEO
    with _GEO_LOCK:
        if _GEO is None:
            _GEO = mmdb.Reader(str(HERE / "geo" / "dbip-city-lite.mmdb"))
        rec = _GEO.get(ip)
    if not rec or "location" not in rec:
        return None
    loc = rec["location"]
    city = (rec.get("city") or {}).get("names", {}).get("en", "")
    cc = (rec.get("country") or {}).get("iso_code", "")
    return (loc["latitude"], loc["longitude"]), ", ".join(p for p in (city, cc) if p)


PORT_NAMES = {22: "ssh", 53: "dns", 80: "http", 443: "https", 993: "imaps", 5222: "xmpp",
              8080: "http-alt", 3478: "stun", 5228: "gcm", 9418: "git"}
SS_PEER = re.compile(r"^\S+\s+\S+\s+(\S+)\s+(\S+)\s*(.*)$")
SS_PROC = re.compile(r'\(\("([^"]+)"')


def split_hostport(text):
    host, _, port = text.rpartition(":")
    host = host.strip("[]")
    if host.startswith("::ffff:"):
        host = host[7:]
    host = host.split("%", 1)[0]
    return host, int(port) if port.isdigit() else 0


def net_collector():
    """New established TCP connections to public addresses."""
    seen = {}
    hits = {}
    first = True
    while not STOP.is_set():
        out = subprocess.run(["ss", "-Htnp", "state", "established"],
                             capture_output=True, text=True, timeout=10).stdout
        now = {}
        for line in out.splitlines():
            m = SS_PEER.match(line.strip())
            if not m:
                continue
            _local, peer, rest = m.groups()
            host, port = split_hostport(peer)
            try:
                addr = ipaddress.ip_address(host)
            except ValueError:
                continue
            if not addr.is_global:
                continue
            proc = SS_PROC.search(rest)
            key = (m.group(1), peer)
            now[key] = (host, port, proc.group(1) if proc else "system")

        # Show what is already connected when the monitor opens, then only
        # what is new, so the globe starts populated rather than empty.
        for key, (host, port, name) in now.items():
            if key in seen:
                continue
            hits[host] = hits.get(host, 0) + 1
            geo = geolocate(host)
            service = PORT_NAMES.get(port, str(port))
            if geo:
                emit("NET", name, f"{host} {service}", latlon=geo[0], place=geo[1],
                     size=port, popularity=hits[host],
                     icon=app_icon(name, "preferences-system-network"))
            elif not first:
                emit("NET", name, f"{host} {service}", size=port, popularity=hits[host],
                     icon=app_icon(name, "preferences-system-network"))
        seen = now
        first = False
        STOP.wait(2)


def window_collector():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not sig:
        log("no HYPRLAND_INSTANCE_SIGNATURE; window events off")
        STOP.wait(3600)
        return
    path = f"{runtime}/hypr/{sig}/.socket2.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.settimeout(1.0)
        buf = b""
        while not STOP.is_set():
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                continue
            if not chunk:
                return
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                name, _, data = line.decode("utf-8", "replace").partition(">>")
                if name == "openwindow":
                    parts = data.split(",", 3)
                    if len(parts) == 4:
                        _addr, ws, cls, title = parts
                        if cls == "org.omarchy.screensaver":
                            continue
                        emit("APP", cls or "window", title or cls, size=f"ws {ws}",
                             icon=app_icon(cls, "utilities-terminal" if "TUI" in cls else
                                           "application-x-executable"))
                elif name == "workspacev2":
                    ws_id, _, ws_name = data.partition(",")
                    emit("APP", "hyprland", f"workspace {ws_name}", size=f"ws {ws_id}",
                         icon=("preferences-desktop-display", "video-display"))


AUTH_IDS = {"sudo", "su", "sshd", "sshd-session", "polkitd", "systemd-logind", "login",
            "unix_chkpwd", "pkexec", "hyprlock"}
PRIORITY_NAMES = {0: "EMERG", 1: "ALERT", 2: "CRIT", 3: "ERROR", 4: "WARN"}


def journal_collector():
    for line in follow(["journalctl", "-f", "-o", "json", "-n", "0", "--no-pager"]):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ident = e.get("SYSLOG_IDENTIFIER") or e.get("_COMM") or "journal"
        msg = e.get("MESSAGE")
        if not isinstance(msg, str):
            continue
        try:
            prio = int(e.get("PRIORITY", 6))
        except ValueError:
            prio = 6
        if ident in AUTH_IDS:
            if ident == "systemd-logind" and "session" not in msg.lower():
                continue
            emit("AUTH", ident, msg, size=PRIORITY_NAMES.get(prio, "INFO"),
                 icon=("system-lock-screen",))
        elif prio <= 4:
            emit("LOG", ident, msg, size=PRIORITY_NAMES[prio], popularity=prio,
                 icon=app_icon(ident, "dialog-warning" if prio == 4 else "dialog-error"))
            if prio <= 2:
                ALERTS.transient(f"journal:{ident}", "CRIT", ident, msg)
        if "Out of memory: Killed process" in msg:
            ALERTS.transient("oom", "CRIT", "kernel", msg)


PACMAN = re.compile(r"\[ALPM\] (installed|upgraded|removed|downgraded|reinstalled) (\S+) \((.*)\)")


def pacman_collector():
    path = pathlib.Path("/var/log/pacman.log")
    with path.open() as fh:
        fh.seek(0, os.SEEK_END)
        while not STOP.is_set():
            line = fh.readline()
            if not line:
                STOP.wait(2)
                continue
            m = PACMAN.search(line)
            if m:
                action, pkg, ver = m.groups()
                emit("PKG", pkg, f"{action} {ver}", size=action,
                     icon=app_icon(pkg, "package-x-generic"))


HW_ICONS = {"usb": "drive-removable-media", "block": "drive-harddisk",
            "net": "preferences-system-network", "power_supply": "battery",
            "input": "input-keyboard", "sound": "audio-card"}
UDEV = re.compile(r"^UDEV\s+\[[\d.]+\]\s+(add|remove|change)\s+(\S+)\s+\((\w+)\)")


def udev_collector():
    cmd = ["udevadm", "monitor", "--udev"]
    for sub in ("usb", "block", "net", "power_supply", "input", "sound"):
        cmd += ["--subsystem-match", sub]
    last = {}
    for line in follow(cmd):
        m = UDEV.match(line)
        if not m:
            continue
        action, devpath, subsystem = m.groups()
        # Batteries emit "change" constantly; only report adds/removes, and
        # collapse the several nodes one device creates into one event.
        if action == "change":
            continue
        name = devpath.rstrip("/").rsplit("/", 1)[-1]
        key = (action, subsystem, devpath.rsplit("/", 2)[0])
        if time.time() - last.get(key, 0) < 3:
            continue
        last[key] = time.time()
        emit("HW", subsystem, f"{action} {name}", size=action,
             icon=(HW_ICONS.get(subsystem, "drive-removable-media"), "drive-removable-media"))


def sample_collector():
    every = max(5, int(CONFIG.get("sample_seconds", 15)))
    while not STOP.is_set():
        try:
            d = json.loads(subprocess.run([str(TELEMETRY)], capture_output=True, text=True,
                                          timeout=10).stdout)
            bat = f" · BAT {d['bat']}%" if d.get("bat", -1) >= 0 else ""
            emit("SYS", socket.gethostname(), icon=(DISC_ICON,), title=
                 f"CPU {d['cpu']}% · MEM {d['mem']}% · {d['temp']}°C{bat}",
                 size=d["cpu"], popularity=d["mem"])
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            pass
        sessions = subprocess.run(["loginctl", "list-sessions", "--no-legend"],
                                  capture_output=True, text=True).stdout.strip().splitlines()
        BUS.publish({"stream": "meta", "size": len(sessions)}, immediate=True)
        History.flush()
        STOP.wait(every)


WIKI_STREAM = "https://stream.wikimedia.org/v2/stream/recentchange"
WIKI_UA = "encom-boardroom-local/1.0 (personal desktop screensaver; stdlib urllib)"

# Wikipedia hides unregistered editors' IPs behind temporary accounts now, so
# edits cannot be placed by editor. They are placed at their language
# edition's home region instead, and labelled as such. Multilingual projects
# (English, Wikidata, Commons) have no honest region and get no pin.
LANG_REGION = {
    "ja": (35.68, 139.69), "de": (52.52, 13.40), "fr": (48.86, 2.35), "es": (40.42, -3.70),
    "it": (41.90, 12.50), "ru": (55.76, 37.62), "zh": (39.90, 116.40), "pt": (-15.79, -47.88),
    "pl": (52.23, 21.01), "nl": (52.37, 4.90), "uk": (50.45, 30.52), "ar": (30.04, 31.24),
    "fa": (35.69, 51.39), "ko": (37.57, 126.98), "tr": (39.93, 32.86), "sv": (59.33, 18.07),
    "he": (31.77, 35.21), "id": (-6.21, 106.85), "vi": (21.03, 105.85), "cs": (50.08, 14.44),
    "fi": (60.17, 24.94), "hu": (47.50, 19.04), "no": (59.91, 10.75), "da": (55.68, 12.57),
    "ro": (44.43, 26.10), "el": (37.98, 23.73), "th": (13.76, 100.50), "hi": (28.61, 77.21),
    "bn": (23.81, 90.41), "ca": (41.39, 2.17), "sr": (44.79, 20.45), "bg": (42.70, 23.32),
    "ms": (3.14, 101.69), "ta": (13.08, 80.27), "ur": (33.68, 73.05), "hy": (40.18, 44.51),
}


def wikipedia_collector():
    """Live public edits, connected only while a page is showing Wikipedia."""
    import urllib.request

    if not BUS.listening("wikipedia"):
        STOP.wait(2)
        return
    req = urllib.request.Request(WIKI_STREAM, headers={"User-Agent": WIKI_UA})
    log("wikipedia: connecting")
    with urllib.request.urlopen(req, timeout=30) as resp:
        idle_since = None
        for raw in resp:
            if STOP.is_set():
                return
            # Drop the connection once nobody has been watching for a while.
            if BUS.listening("wikipedia"):
                idle_since = None
            elif idle_since is None:
                idle_since = time.time()
            elif time.time() - idle_since > 10:
                log("wikipedia: no viewers; disconnecting")
                return
            if BUS.backlog("wikipedia") > 20:
                continue
            line = raw.decode("utf-8", "replace")
            if not line.startswith("data:"):
                continue
            try:
                e = json.loads(line[5:])
            except ValueError:
                continue
            if e.get("type") not in ("edit", "new") or e.get("bot"):
                continue
            server = e.get("server_name", "")
            lang, _, project = server.partition(".")
            length = e.get("length") or {}
            delta = (length.get("new") or 0) - (length.get("old") or 0)
            region = LANG_REGION.get(lang) if project == "wikipedia.org" else None
            emit(lang.upper()[:4] or "WIKI", e.get("user", "?"), e.get("title", ""),
                 latlon=region, place=server.replace(".org", "") if region else "",
                 size=f"{delta:+d}", popularity=length.get("new") or "",
                 stream="wikipedia", pin_home=False)


# ── HTTP ───────────────────────────────────────────────────────────────────
DISMISSED = threading.Event()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(APP), **kw)

    def log_message(self, *_):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/events.js":
            return self.stream()
        if path.startswith("/icon/"):
            return self.icon(path[len("/icon/"):])
        if path == "/alerts.json":
            return self.body(json.dumps(ALERTS.snapshot()).encode(), "application/json")
        if path == "/history.js":
            # Runs before the bundle, which opens its EventSource at load from
            # window._esPath: point it at the one stream this page will show.
            # A page opened by hand (no #screensaver) may pick any folder, so
            # it takes every stream.
            cfg = {"cycle": CONFIG.get("cycle", ["system"]),
                   "cycle_seconds": CONFIG.get("cycle_seconds", 120)}
            body = (
                "window.encomSystemHistory = " + json.dumps(History.series()) + ";\n"
                "window.encomConfig = " + json.dumps(cfg) + ";\n"
                "(function () {\n"
                "  var m = /^#screensaver(?::(\\w+))?/.exec(location.hash);\n"
                "  var c = window.encomConfig.cycle;\n"
                "  var s = m ? (c.indexOf(m[1]) >= 0 ? m[1] : c[0]) : 'all';\n"
                "  window._esPath = '/events.js?stream=' + s;\n"
                "})();\n"
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return None
        return super().do_GET()

    def body(self, data, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def icon(self, key):
        # Only keys the server itself resolved are served: a key never maps to
        # a caller-supplied path, since it cannot contain "/".
        path = ICONS.path(key) if key and "/" not in key else None
        if not path:
            return self.send_error(404)
        try:
            data = pathlib.Path(path).read_bytes()
        except OSError:
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=3600")
        # Skip our no-store end_headers: icons are safe to cache.
        http.server.BaseHTTPRequestHandler.end_headers(self)
        self.wfile.write(data)

    def do_POST(self):
        if self.path == "/dismiss":
            DISMISSED.set()
            self.send_response(204)
            self.end_headers()
            return
        self.send_error(404)

    def stream(self):
        query = self.path.partition("?")[2]
        wanted = dict(p.partition("=")[::2] for p in query.split("&") if p).get("stream", "all")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        q = BUS.subscribe(wanted)
        try:
            self.wfile.write(b": encom\n\n")
            self.wfile.flush()
            while not STOP.is_set():
                try:
                    event = q.get(timeout=15)
                    self.wfile.write(b"data: " + json.dumps(event).encode() + b"\n\n")
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            BUS.unsubscribe(q)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


# ── Window lifecycle ───────────────────────────────────────────────────────
def locked():
    try:
        out = subprocess.run(["omarchy-shell", "lock", "isLocked"], capture_output=True,
                             text=True, timeout=3).stdout.strip()
        return out == "true"
    except (OSError, subprocess.SubprocessError):
        return False


def open_window(url, screensaver):
    """Start Chromium on its own profile.

    Screensaver mode uses --kiosk with a plain URL rather than --app: in app
    mode Chromium names the window after the URL (chrome-127.0.0.1__-Default)
    and ignores --class, and Omarchy's idle service only recognises a
    screensaver by the org.omarchy.screensaver class.
    """
    chromium = shutil.which("chromium")
    if not chromium:
        sys.exit("chromium not found")
    CHROMIUM_PROFILE.mkdir(parents=True, exist_ok=True)
    cmd = [chromium, f"--user-data-dir={CHROMIUM_PROFILE}", "--no-first-run",
           "--no-default-browser-check", "--noerrdialogs", "--disable-session-crashed-bubble",
           "--disable-infobars", "--disable-translate", "--ozone-platform-hint=auto"]
    if screensaver:
        cmd += ["--kiosk", "--class=org.omarchy.screensaver", url]
    else:
        cmd += [f"--app={url}"]
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     stdin=subprocess.DEVNULL, start_new_session=True)


def browser_pids():
    """PIDs of every Chromium process on the boardroom's private profile.

    The process we start does not stay the browser (the launcher hands off and
    exits), so the window's lifetime is tracked by these instead. The profile
    is ours alone, so this never matches your everyday Chromium.
    """
    # Chromium rewrites its process title, joining argv with spaces instead of
    # NULs, so match the flag as a space-delimited token in the joined text.
    marker = f" --user-data-dir={CHROMIUM_PROFILE} "
    pids = []
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        text = " " + raw.replace(b"\0", b" ").decode("utf-8", "replace") + " "
        if marker in text:
            pids.append(int(entry.name))
    return pids


def close_browser():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = browser_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        for _ in range(20):
            if not browser_pids():
                return
            time.sleep(0.25)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screensaver", action="store_true")
    ap.add_argument("--serve-only", action="store_true")
    ap.add_argument("--port", type=int, default=0)
    args = ap.parse_args()

    if args.screensaver and locked():
        return

    server = Server(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    global PORT
    PORT = port
    # Build the icon indexes now, off the event path, so the first events
    # are not held up by a one-second scan of the icon themes.
    threading.Thread(target=ICONS._ensure, daemon=True, name="icons").start()
    threading.Thread(target=server.serve_forever, daemon=True, name="http").start()

    for fn in (net_collector, window_collector, journal_collector, pacman_collector,
               udev_collector, sample_collector, wikipedia_collector, alert_collector):
        collector(fn).start()

    def stop(*_):
        STOP.set()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    url = f"http://127.0.0.1:{port}/" + ("#screensaver" if args.screensaver else "")
    log("serving", url)

    if not args.serve_only:
        close_browser()     # a leftover from a crashed run would hold the profile
        open_window(url, args.screensaver)
        # Give the browser time to appear before treating its absence as closed.
        for _ in range(80):
            if browser_pids() or STOP.is_set():
                break
            STOP.wait(0.25)
    last_lock_check = 0.0
    try:
        while not STOP.is_set():
            if not args.serve_only and not browser_pids():
                log("browser closed; exiting")
                break
            if args.screensaver:
                if DISMISSED.is_set():
                    log("dismissed by input; closing")
                    break
                if time.time() - last_lock_check > 3:
                    last_lock_check = time.time()
                    if locked():
                        log("session locked; closing")
                        break
            STOP.wait(0.25)
    finally:
        STOP.set()
        if not args.serve_only:
            close_browser()
        for child in CHILDREN:
            if child.poll() is None:
                child.terminate()
        History.flush()
        server.shutdown()


if __name__ == "__main__":
    main()
