#!/usr/bin/env python3
"""ENCOM Boardroom as the desktop background.

A WebKitGTK view on the wlr-layer-shell desktop layer: below every window,
above the wallpaper image, never taking keyboard focus, and click-through.
It loads the Boardroom page from server.py.

    wallpaper.py <url> [--max-fps=N] [--always-animate] [--fps]

It animates only while the desktop is actually on show (an empty workspace,
on mains power, no screensaver running) and otherwise freezes on its last
frame at next to no cost. --fps logs the page's frame rate.

Run by the encom-wallpaper user service; turn it on and off with
encom-wallpaper.
"""
import json
import os
import socket
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("WebKit2", "4.1")
from gi.repository import GLib, Gtk, GtkLayerShell, WebKit2  # noqa: E402
import cairo  # noqa: E402

# Cap the page's frame rate. The Boardroom's motion is slow, and at the
# browser's native 60 fps the web process alone costs most of a CPU core.
FPS_CAP = """
(function () {
  // Frame-rate cap plus pause switch, installed before the page's scripts so
  // its render loop only ever sees this requestAnimationFrame.
  var interval = 1000 / %d, last = 0, queue = [];
  var paused = false, gen = 0;
  var native = window.requestAnimationFrame.bind(window);

  // One pump per generation. Resuming bumps the generation, which retires any
  // older pump still in flight, so a resume can always start a fresh loop
  // without ever ending up with two of them running at once.
  function start() {
    var mine = ++gen;
    last = 0;
    native(function pump(now) {
      if (paused || mine !== gen) return;      // paused, or retired by a newer pump
      if (now - last >= interval - 1) {
        last = now;
        var run = queue; queue = [];
        for (var i = 0; i < run.length; i++) { try { run[i](now); } catch (e) {} }
      }
      native(pump);
    });
  }

  window.requestAnimationFrame = function (cb) { queue.push(cb); return queue.length; };
  // Called by wallpaper.py. Paused, the page stops drawing (its last frame
  // stays on screen); resumed, it carries on where it left off.
  //
  // Resuming always starts a new pump rather than trying to work out whether
  // the old one is still alive. It usually is not: pausing hides the view, and
  // WebKit suspends a hidden page's requestAnimationFrame outright -- often
  // before the running pump gets the frame it would have noticed the pause on.
  // Anything that tracked liveness from in here would be guessing, and a wrong
  // guess leaves the wallpaper frozen until the service is restarted.
  window.__encomSetPaused = function (p) {
    paused = !!p;
    if (!paused) start();
  };

  // WebKit can suspend and resume the page on its own account, so heal on the
  // way back rather than waiting to be told.
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && !paused) start();
  });

  start();
})();
"""

FPS_PROBE = """
(function () {
  var frames = 0, t0 = performance.now();
  function tick(now) {
    frames++;
    if (now - t0 >= 5000) {
      console.log("ENCOM-FPS " + (frames * 1000 / (now - t0)).toFixed(1));
      frames = 0; t0 = now;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
"""


def hypr(request):
    """One request on Hyprland's command socket (no hyprctl process spawned)."""
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    path = f"{os.environ.get('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid())}/hypr/{sig}/.socket.sock"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            s.connect(path)
            s.sendall(request.encode())
            chunks = []
            while True:
                b = s.recv(65536)
                if not b:
                    break
                chunks.append(b)
        return json.loads(b"".join(chunks) or b"null")
    except (OSError, ValueError):
        return None


def on_ac_power():
    base = "/sys/class/power_supply"
    try:
        supplies = os.listdir(base)
    except OSError:
        return True
    mains = [s for s in supplies if open(f"{base}/{s}/type").read().strip() == "Mains"]
    if not mains:
        return True                     # a desktop: no battery to protect
    return any(open(f"{base}/{s}/online").read().strip() == "1" for s in mains)


_lock = {"at": 0.0, "locked": False}


def locked():
    """Omarchy's lock screen, asked at most every 5 s (it costs a process)."""
    now = time.monotonic()
    if now - _lock["at"] > 5:
        _lock["at"] = now
        try:
            out = subprocess.run(["omarchy-shell", "lock", "isLocked"], capture_output=True,
                                 text=True, timeout=3).stdout.strip()
            _lock["locked"] = out == "true"
        except (OSError, subprocess.SubprocessError):
            _lock["locked"] = False
    return _lock["locked"]


def should_animate():
    """Animate only when the wallpaper is really on show: an empty workspace,
    on mains power, the display on and unlocked, and no screensaver over it."""
    ws = hypr("j/activeworkspace")
    if ws and ws.get("windows", 0) > 0:
        return False
    if not on_ac_power():
        return False
    monitors = hypr("j/monitors") or []
    if monitors and not any(m.get("dpmsStatus", True) for m in monitors):
        return False
    clients = hypr("j/clients") or []
    if any(c.get("class") == "org.omarchy.screensaver" for c in clients):
        return False
    return not locked()


def main():
    url = sys.argv[1]
    probe = "--fps" in sys.argv

    win = Gtk.Window()
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_namespace(win, "encom-boardroom-wallpaper")
    # BOTTOM sits above the wallpaper image (BACKGROUND) and below windows.
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.BOTTOM)
    for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                 GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
        GtkLayerShell.set_anchor(win, edge, True)
    GtkLayerShell.set_exclusive_zone(win, -1)          # ignore the bar's reserved space
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE)

    settings = WebKit2.Settings()
    settings.set_enable_webgl(True)
    settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.ALWAYS)
    settings.set_enable_write_console_messages_to_stdout(True)

    view = WebKit2.WebView.new_with_settings(settings)
    manager = view.get_user_content_manager()
    fps = next((int(a.split("=", 1)[1]) for a in sys.argv if a.startswith("--max-fps=")), 24)
    # Injected before the page's own scripts, so the app's render loop sees
    # the capped requestAnimationFrame from its first frame.
    manager.add_script(WebKit2.UserScript(
        FPS_CAP % fps, WebKit2.UserContentInjectedFrames.TOP_FRAME,
        WebKit2.UserScriptInjectionTime.START, None, None))
    if probe:
        manager.add_script(WebKit2.UserScript(
            FPS_PROBE, WebKit2.UserContentInjectedFrames.TOP_FRAME,
            WebKit2.UserScriptInjectionTime.END, None, None))
    view.load_uri(url)

    # Paused, the view is swapped for a snapshot of its last frame. Hidden,
    # WebKit treats the page as not visible and suspends it entirely: timers,
    # CSS animations and drawing all stop, which pausing the page's own render
    # loop alone does not achieve (the Boardroom also animates through CSS
    # and jQuery timers).
    still = Gtk.Image()
    stack = Gtk.Stack()
    stack.add_named(view, "live")
    stack.add_named(still, "still")
    win.add(stack)

    # Click-through: an empty input region hands every click to what is below.
    win.connect("realize", lambda w: w.input_shape_combine_region(cairo.Region()))
    always = "--always-animate" in sys.argv
    state = {"paused": None}

    def freeze(snapshot_result):
        try:
            surface = view.get_snapshot_finish(snapshot_result)
            still.set_from_surface(surface)
        except GLib.Error:
            pass                         # no frame yet: an empty still is fine
        stack.set_visible_child_name("still")

    def set_paused(paused):
        view.evaluate_javascript(
            f"window.__encomSetPaused && window.__encomSetPaused({str(paused).lower()})",
            -1, None, None, None, None, None)

    def tick():
        paused = False if always else not should_animate()
        if paused != state["paused"]:
            state["paused"] = paused
            if paused:
                set_paused(True)
                view.get_snapshot(WebKit2.SnapshotRegion.VISIBLE, WebKit2.SnapshotOptions.NONE,
                                  None, lambda v, r: freeze(r))
            else:
                # Show the view before resuming: WebKit suspends a hidden
                # page's timers and animation frames, so a resume delivered
                # while it is still hidden has nothing to start.
                stack.set_visible_child_name("live")
                set_paused(False)
        return True

    # Re-apply after every page load (the Boardroom reloads the view it shows).
    view.connect("load-changed", lambda v, e: state.update(paused=None)
                 if e == WebKit2.LoadEvent.FINISHED else None)
    GLib.timeout_add_seconds(1, tick)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
