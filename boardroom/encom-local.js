/* ENCOM local glue, loaded after the upstream bundle.
 *
 * Everywhere: a SYSTEM ALERT box that shows every active alert from
 * server.py, on any stream. It reads the current set at load (each screensaver
 * rotation is a fresh page) and then follows the alert stream.
 *
 * #screensaver mode: hide the cursor, open a stream folder by itself once the
 * light table is up, and hand control back on the first real input by asking
 * server.py to close the window.
 *
 * The upstream app cannot return from a stream to the folders (it unbinds the
 * folder handlers on launch), so cycling works by reloading onto the next
 * stream: #screensaver:<stream>. Each change therefore replays the terminal
 * intro, which is the film's own transition. Order and interval come from
 * ~/.config/encom-boardroom/config.json via window.encomConfig.
 *
 * The bundle keeps jQuery private, so everything here is plain DOM; jQuery's
 * handlers still fire for native click events.
 */
function encomAlerts() {
  var box = document.createElement("div");
  box.id = "encom-alerts";
  box.hidden = true;
  box.innerHTML =
    '<div class="frame">' +
      '<div class="portrait"><img src="encom-portrait.gif" alt=""><span class="channel">CH-12</span></div>' +
      '<div class="body"><div class="head">SYSTEM ALERT</div><div class="rows"></div></div>' +
    '</div>';
  document.body.appendChild(box);
  var rows = box.querySelector(".rows");
  var active = {};

  function render() {
    var keys = Object.keys(active);
    box.hidden = keys.length === 0;
    rows.innerHTML = "";
    keys.forEach(function (key) {
      var a = active[key];
      var row = document.createElement("div");
      row.className = "row" + (a.level === "CRIT" ? " crit" : "");
      var lvl = document.createElement("span");
      lvl.className = "lvl";
      lvl.textContent = a.level;
      row.appendChild(lvl);
      row.appendChild(document.createTextNode(a.who.toUpperCase() + "  " + a.title));
      rows.appendChild(row);
    });
  }

  fetch("/alerts.json").then(function (r) { return r.json(); }).then(function (list) {
    list.forEach(function (a) { active[a.key] = a; });
    render();
  }).catch(function () {});

  var es = new EventSource("/events.js?stream=alert");
  es.onmessage = function (ev) {
    var msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.stream !== "alert") return;
    if (msg.action === "raise") active[msg.key] = msg;
    else if (msg.action === "clear") delete active[msg.key];
    render();
  };
}
// Scripts load in <head>, before <body> exists.
if (document.body) encomAlerts();
else document.addEventListener("DOMContentLoaded", encomAlerts);

(function screensaver() {
  // #screensaver[:stream] rotates and closes on input; #wallpaper[:stream]
  // is the desktop background: it opens one stream and stays.
  var match = /^#(screensaver|wallpaper)(?::(\w+))?/.exec(location.hash);
  if (!match) return;
  var wallpaper = match[1] === "wallpaper";

  var cfg = window.encomConfig || {};
  var cycle = (cfg.cycle && cfg.cycle.length) ? cfg.cycle : ["system"];
  var seconds = Math.max(30, Number(cfg.cycle_seconds) || 120);
  var requested = match[2];
  var current = wallpaper ? (requested || "system")
                          : (cycle.indexOf(requested) >= 0 ? requested : cycle[0]);

  // Stream name -> upstream folder id ("system" reuses the Test Stream slot).
  var FOLDERS = { system: "lt-launch-test", github: "lt-launch-github", wikipedia: "lt-launch-wikipedia" };

  if (!wallpaper) {
    var style = document.createElement("style");
    style.textContent = "*, *::before, *::after { cursor: none !important; }";
    document.head.appendChild(style);
  }

  var tries = 0;
  var launcher = setInterval(function () {
    tries++;
    var table = document.getElementById("light-table");
    var folder = document.getElementById(FOLDERS[current] || FOLDERS.system);
    if (table && folder && getComputedStyle(table).visibility === "visible") {
      clearInterval(launcher);
      setTimeout(function () { folder.click(); }, 1800);
    } else if (tries > 160) {
      clearInterval(launcher);
    }
  }, 250);

  // The wallpaper never rotates or closes; everything below is screensaver-only.
  if (wallpaper) return;

  if (cycle.length > 1) {
    setTimeout(function () {
      var next = cycle[(cycle.indexOf(current) + 1) % cycle.length];
      location.hash = "screensaver:" + next;
      location.reload();
    }, seconds * 1000);
  }

  var dismissed = false;
  function dismiss() {
    if (dismissed) return;
    dismissed = true;
    fetch("/dismiss", { method: "POST", keepalive: true }).catch(function () {});
  }

  // A window appearing under a stationary pointer can emit a synthetic
  // mousemove, so ignore input for a moment and require a real movement.
  var armedAt = Date.now() + 1500;
  var origin = null;
  function armed() { return Date.now() > armedAt; }

  ["keydown", "mousedown", "wheel", "touchstart"].forEach(function (type) {
    window.addEventListener(type, function (e) {
      if (!armed()) return;
      e.preventDefault();
      e.stopPropagation();
      dismiss();
    }, { capture: true, passive: false });
  });

  window.addEventListener("mousemove", function (e) {
    if (!armed()) return;
    if (!origin) { origin = { x: e.screenX, y: e.screenY }; return; }
    if (Math.abs(e.screenX - origin.x) + Math.abs(e.screenY - origin.y) > 12) dismiss();
  }, true);
})();
