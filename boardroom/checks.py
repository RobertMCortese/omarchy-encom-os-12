#!/usr/bin/env python3
"""ENCOM alert checks: the conditions worth interrupting for.

One implementation shared by the Boardroom server (which imports it) and the
desktop HUD (which runs it as a command):

    checks.py --json            active alerts as a JSON list
    checks.py --json --journal  also crashes / OOM kills from the last 5 minutes

Each alert is {"key", "level" (WARN|CRIT), "who", "title"}. Checks are cheap
reads of /proc, /sys, df and systemctl. Temperature must stay high for several
consecutive checks; that count is carried in `state` (a dict the caller keeps,
or a small file in $XDG_RUNTIME_DIR when run as a command).
"""
import json
import os
import pathlib
import subprocess
import sys

CONFIG_PATH = pathlib.Path.home() / ".config" / "encom-boardroom" / "config.json"

DEFAULTS = {
    "disk_percent": 90,            # any real filesystem at least this full
    "temp_c": 95,                  # CPU package, sustained for temp_samples checks
    "temp_samples": 3,
    "battery_percent": 15,         # while discharging
    "mem_available_percent": 10,   # MemAvailable below this share of RAM
    "swap_percent": 75,
}


def thresholds():
    try:
        user = json.loads(CONFIG_PATH.read_text()).get("alerts", {})
    except (OSError, ValueError):
        user = {}
    return {**DEFAULTS, **user}


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _alert(key, level, who, title):
    return {"key": key, "level": level, "who": who, "title": title}


def disks(t):
    """Each real device once: btrfs subvolumes (/, /home, /var/log ...) are
    one device mounted several times, and a full disk should be one alert."""
    out = _run(["df", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs",
                "-x", "overlay", "-x", "squashfs"])
    seen, alerts = set(), []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 6 or not parts[4].endswith("%"):
            continue
        device, use, mount = parts[0], int(parts[4][:-1]), parts[5]
        if device in seen:
            continue
        seen.add(device)
        if use >= t["disk_percent"]:
            alerts.append(_alert(f"disk:{mount}", "CRIT" if use >= 97 else "WARN",
                                 "storage", f"{mount} is {use}% full"))
    return alerts


def memory(t):
    mem = {}
    for line in pathlib.Path("/proc/meminfo").read_text().splitlines():
        k, _, v = line.partition(":")
        mem[k] = int(v.split()[0])
    alerts = []
    avail = 100 * mem["MemAvailable"] / mem["MemTotal"]
    if avail < t["mem_available_percent"]:
        alerts.append(_alert("memory", "WARN", "memory", f"only {avail:.0f}% of RAM available"))
    if mem.get("SwapTotal"):
        swap = 100 * (mem["SwapTotal"] - mem["SwapFree"]) / mem["SwapTotal"]
        if swap >= t["swap_percent"]:
            alerts.append(_alert("swap", "WARN", "memory", f"swap {swap:.0f}% used"))
    return alerts


def failed_units():
    alerts = []
    for scope in ([], ["--user"]):
        for line in _run(["systemctl", *scope, "--failed", "--no-legend", "--plain"]).splitlines():
            unit = line.split()[0] if line.split() else ""
            if unit:
                key = ("user:" if scope else "") + unit
                alerts.append(_alert(f"unit:{key}", "CRIT", "systemd", f"{unit} failed"))
    return alerts


def cpu_temp():
    # The CPU package zone; on this Mac the first zone is the chipset.
    for want in ("x86_pkg_temp", "coretemp", "cpu-thermal", "acpitz"):
        for zone in pathlib.Path("/sys/class/thermal").glob("thermal_zone*"):
            try:
                if (zone / "type").read_text().strip() == want:
                    return int((zone / "temp").read_text()) // 1000
            except (OSError, ValueError):
                continue
    return None


def power(t, state):
    alerts = []
    temp = cpu_temp()
    if temp is not None:
        state["hot"] = state.get("hot", 0) + 1 if temp >= t["temp_c"] else 0
        if state["hot"] >= t["temp_samples"]:
            alerts.append(_alert("temp", "WARN", "thermal",
                                 f"CPU at {temp}°C for {state['hot']} checks running"))
    for bat in pathlib.Path("/sys/class/power_supply").glob("BAT*"):
        try:
            level = int((bat / "capacity").read_text())
            status = (bat / "status").read_text().strip()
        except (OSError, ValueError):
            continue
        if status == "Discharging" and level <= t["battery_percent"]:
            alerts.append(_alert("battery", "CRIT" if level <= t["battery_percent"] // 2 else "WARN",
                                 "power", f"battery at {level}% and discharging"))
        break
    return alerts


def journal_recent(minutes=5):
    """Critical journal entries and OOM kills from the last few minutes, for
    callers that are not following the journal live."""
    alerts = []
    out = _run(["journalctl", "-q", "--no-pager", "-o", "json", "--since", f"-{minutes}min",
                "-p", "0..2"])
    for line in out.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ident = e.get("SYSLOG_IDENTIFIER") or e.get("_COMM") or "journal"
        msg = e.get("MESSAGE")
        if isinstance(msg, str):
            alerts.append(_alert(f"journal:{ident}", "CRIT", ident, msg[:120]))
    for line in _run(["journalctl", "-q", "--no-pager", "-k", "-o", "cat", "--since",
                      f"-{minutes}min", "--grep", "Out of memory: Killed process"]).splitlines():
        alerts.append(_alert("oom", "CRIT", "kernel", line[:120]))
    # One row per key: the latest wins.
    return list({a["key"]: a for a in alerts}.values())


def evaluate(state=None, journal=False):
    """All current alerts. `state` carries the sustained-temperature count."""
    t = thresholds()
    state = {} if state is None else state
    alerts = disks(t) + memory(t) + failed_units() + power(t, state)
    if journal:
        alerts += journal_recent()
    return alerts


def main():
    state_path = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "encom-alerts.state"
    try:
        state = json.loads(state_path.read_text())
    except (OSError, ValueError):
        state = {}
    alerts = evaluate(state, journal="--journal" in sys.argv)
    try:
        state_path.write_text(json.dumps(state))
    except OSError:
        pass
    print(json.dumps(alerts))


if __name__ == "__main__":
    main()
