/* ENCOM local glue, loaded after the upstream bundle.
 *
 * Everywhere: the layout stretched to fill the screen's height (see
 * encomFitHeight), and a SYSTEM ALERT box that shows every active alert from
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

// ── Fill the screen's height ────────────────────────────────────────────
// Upstream lays out a 1900 x 707 design and zooms it to the window's width,
// which on a 16:9 screen leaves the bottom quarter black. Keeping that same
// zoom (so nothing overflows the sides), this makes the layout taller by
// the spare height E: frames, the region list and the live list stretch;
// the bottom row moves down; the globe, cube, swirls, charts, clock and icon
// frames keep their exact size and shape and are re-centred in the extra
// room; and when there is room, the right column gets a third row of icon
// frames (a copy the app fills like the others). Pixel values below are
// design pixels, from upstream's stylesheet.
function encomFitHeight() {
  var BASE_H = 707;                          // layout height with the bottom border
  var lastE = -1, cloned = false;
  function $(id) { return document.getElementById(id) }
  function px(el, prop, v) { if (el) el.style[prop] = v + "px" }

  // The third media row, added before the app starts so it is filled and
  // its lights blink like the originals.
  function cloneMediaRow() {
    var top = $("media-top"), blink = $("media-top-blinkies")
    if (!top || !blink || $("media-extra")) return
    var row = top.cloneNode(true), lights = blink.cloneNode(true)
    row.id = "media-extra"; lights.id = "media-extra-blinkies"
    blink.parentNode.insertBefore(lights, blink.nextSibling)
    blink.parentNode.insertBefore(row, lights)
    cloned = true
  }

  function extra() {
    var b = $("boardroom")
    var zoom = (b && parseFloat(b.style.zoom)) || window.innerWidth / 1918
    // 20 screen px of margin top and bottom.
    return { zoom: zoom, E: Math.max(0, Math.floor((window.innerHeight - 40) / zoom) - BASE_H) }
  }

  function apply() {
    var b = $("boardroom")
    if (!b) return
    var f = extra(), E = f.E, zoom = f.zoom
    // Centre the taller layout (upstream centres the old one, a little high).
    if (b.style.zoom) px(b, "top", Math.max(0, (window.innerHeight / zoom - (BASE_H + E)) / 2))
    if (E === lastE) return
    lastE = E

    px(b, "height", 700 + E)
    px($("bottom-border"), "top", 705 + E)

    // Left: the region list spread over the height, the logo at the foot.
    px($("globalization"), "height", 700 + E)
    px($("logo"), "top", 590 + E)
    var sliders = document.querySelectorAll("#globalization [id^=location-slider-]")
    ;[].forEach.call(sliders, function (s, i) { if (i > 0) px(s, "marginTop", 15 + E * 0.55 / (sliders.length - 1)) })

    // The globe stays square, centred in its taller column; its links at the foot.
    px($("globe"), "top", E / 2)
    px($("globe-footer"), "top", 650 + E)

    // Middle: the live list shows more rows; cube and swirls keep their size,
    // spread through the extra room; the bottom row moves down.
    ;["user-interaction", "user-interaction-container"].forEach(function (id) { px($(id), "height", 495 + E) })
    px($("interaction"), "height", 449 + E)
    px($("interaction-overlay"), "top", 295 + E)
    px($("cube"), "top", 29 + E * 0.25)
    px($("swirls"), "top", 270 + E * 0.75)
    px($("growth"), "top", 500 + E)

    // Right: rows of icon frames, spaced evenly; the clock moves down.
    ;["media", "media-container"].forEach(function (id) { px($(id), "height", 495 + E) })
    var rows = cloned ? [["media-top", "media-top-blinkies"], ["media-extra", "media-extra-blinkies"],
                         ["media-bottom", "media-bottom-blinkies"]]
                      : [["media-top", "media-top-blinkies"], ["media-bottom", "media-bottom-blinkies"]]
    function space(gap) {
      rows.forEach(function (r, i) {
        r.forEach(function (id) { px($(id), "marginTop", (i === 0 ? 34 : 30) + (i === 0 ? gap / 2 : gap)) })
      })
    }
    // A first guess at the gaps, then measure and close them up until the
    // last row ends a little above the panel's foot.
    var gap = (E - (cloned ? 230 : 0)) / rows.length
    space(gap)
    var last = $(rows[rows.length - 1][1]), panel = $("media")
    var over = (last.getBoundingClientRect().bottom - panel.getBoundingClientRect().bottom) / zoom + 8
    if (over > 0) space(gap - over / (rows.length - 0.5))
    px($("timer"), "top", 500 + E)
  }

  // Room for a third row of icon frames? Decide before the app starts.
  if (extra().E >= 260) cloneMediaRow()
  // The app sets its zoom when a stream launches; lay out then, and on resize.
  var b = $("boardroom")
  if (b) new MutationObserver(apply).observe(b, { attributes: true, attributeFilter: ["style"] })
  window.addEventListener("resize", function () { lastE = -1; apply() })
  apply()
}
if (document.body) encomFitHeight();
else document.addEventListener("DOMContentLoaded", encomFitHeight);

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
