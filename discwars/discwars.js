// ENCOM OS-12: the disc duel, on a canvas.
//
// A port of the lock screen's scene (lock/DiscWars.qml) to the web. Two
// original fighters, a program and a sentinel, each stand on a platform
// ringed by four concentric rings floating high above the arena floor, and
// fight over it with identity discs.
//
// They trade discs fast. A throw at the body is blocked on the defender's
// own disc, held up as a shield (only when that disc is home), or dodged
// with a sidestep or a flip (a side flip, a butterfly twist or a backflip)
// that carries it to another ring, never off the edge, and across a gap if
// a ring is gone; or in place with a duck, a sweep kick or a split jump; the
// disc ricochets off the glass. Now and then a throw connects: the fighter
// is knocked back a ring and stunned, or, with no ring behind, slides off
// and grabs the edge; or, three times in ten, derezzes, its outline breaking
// into a hundred pieces that tumble down to the arena floor. Now and then a
// throw is banked off the ceiling onto one of the opponent's rings, often
// the one it stands on; the defender may catch it on a shield held overhead,
// or lose the ring. Losing its footing, a fighter drops and clings to the
// edge of the nearest ring still up; the next banked throw takes that out
// and it falls and derezzes. The rings rise again, the fighter rezzes back
// in, and the duel goes on.
//
// The movement is motion capture (poses.js, baked from the CMU Graphics Lab
// database: a frisbee throw, a stance, a sidestep); the block, the flip and
// the hang are built on top of it. The scene is 3D through a slowly drifting
// perspective camera, projected by hand each frame.
//
// The QML original placed one QtQuick rectangle per edge and let the scene
// graph sort them by a `z` property. Here every edge is a stroke instead,
// and the draw list is sorted by depth once a frame -- a painter's
// algorithm, which is what that `z` amounted to. Limbs are round-capped
// lines rather than rounded rectangles nudged to overlap at the joints,
// which is the same shape for less arithmetic.
(function () {
  "use strict";

  var Poses = window.POSES;

  // ── Palettes ──────────────────────────────────────────────────────────
  // The six ENCOM OS-12 themes, as the desktop wears them.
  var THEMES = {
    "tron-legacy": { name: "TRON Legacy", sideA: "#6fc3df", sideAHi: "#d8f6ff", sideB: "#ff8c21", sideBHi: "#ffd9a8", accent: "#6fc3df", accentHi: "#a8ecff", ink: "#010306" },
    "clu":         { name: "CLU",         sideA: "#ff9d2e", sideAHi: "#ffd7a9", sideB: "#38c6f4", sideBHi: "#bdecfb", accent: "#ff9d2e", accentHi: "#ffc37e", ink: "#050402" },
    "tron-1982":   { name: "TRON 1982",   sideA: "#3b7bff", sideAHi: "#d7e6ff", sideB: "#ffbe00", sideBHi: "#fff3cf", accent: "#3b7bff", accentHi: "#8fb3ff", ink: "#020305" },
    "tron-uprising": { name: "Uprising",  sideA: "#dff3ee", sideAHi: "#ffffff", sideB: "#c4562f", sideBHi: "#ffb48c", accent: "#11a389", accentHi: "#e6f1ef", ink: "#04100e" },
    "tron-2-0":    { name: "TRON 2.0",    sideA: "#6fd8ff", sideAHi: "#d8f6ff", sideB: "#8fd63f", sideBHi: "#d6f79a", accent: "#79c72f", accentHi: "#cdf08a", ink: "#061513" },
    "dillinger-systems": { name: "Dillinger", sideA: "#ff3b30", sideAHi: "#ffd1ac", sideB: "#7fd0ff", sideBHi: "#ffffff", accent: "#ff3b30", accentHi: "#ffa781", ink: "#050202" }
  };
  var pal = THEMES["tron-legacy"];
  var program, programHi, sentinel, sentinelHi, ink, line, lineHi;
  function applyPalette(p) {
    pal = p;
    program = p.sideA; programHi = p.sideAHi;
    sentinel = p.sideB; sentinelHi = p.sideBHi;
    ink = p.ink; line = p.accent; lineHi = p.accentHi;
    rebuildLines();
  }

  // ── Arena constants ───────────────────────────────────────────────────
  var floorY = -3.5;                 // the arena floor, far below
  var ceilY = 4.2;
  var centreX = 8.0;                 // the two ranks stand this far either side
  var rankGap = 5.4;                 // between teammates, across the arena's depth
  // 1v1, 2v2 or 3v3. The arena, the camera and the number of duels running at
  // once all follow from this.
  var teamSize = 1;
  var arenaZ = 5.5;                  // the glass wall, far enough back to clear the rings
  // Rings per fighter: the platform, then four rings; [inner, outer] radii.
  var ringRadii = [[0, 0.5], [0.56, 0.96], [1.02, 1.42], [1.48, 1.88], [1.94, 2.34]];
  var ringCount = ringRadii.length;
  var ringSegs = 24;

  // Two clocks: `now` runs the fight at `pace` times real speed; `wall` is
  // real time, for what should stay watchable (camera, sparks, falls).
  var pace = 2.55;
  var now = 0, wall = 0;

  var fov = 48 * Math.PI / 180;
  var cam = { p: [0, 3, 10], f: [0, 0, -1], r: [1, 0, 0], u: [0, 1, 0], F: 1000 };
  var W = 0, H = 0;                  // canvas size in CSS pixels

  // ── Vector helpers ────────────────────────────────────────────────────
  function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function norm(a) { var l = Math.sqrt(dot(a, a)) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }
  function lerp3(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
  function rand(a, b) { return a + Math.random() * (b - a); }
  function ease(u) { return u * u * (3 - 2 * u); }

  // Where the camera is drawn to: the middle of the arena, pulled toward
  // whatever exchange is in the air. With one duel this barely moves; with
  // three it keeps the busy corner of the arena in frame.
  var look = [0, 0.7, 0];
  function aimPoint() {
    var sx = 0, sz = 0, n = 0;
    for (var i = 0; i < ds.length; i++) {
      if (ds[i].state !== "flight") continue;
      sx += ds[i].pos[0]; sz += ds[i].pos[2]; n++;
    }
    // The duel's framing was composed around a fixed camera, so it keeps one;
    // only a team match, which is too wide to hold in one shot, is followed.
    var pull = (teamSize - 1) / 2;
    if (!n || pull === 0) return [0, 0.7, 0];
    return [sx / n * 0.35 * pull, 0.7, sz / n * 0.6 * pull];
  }

  function aimCamera(dt) {
    // A slow drift around the front of the arena, rising and falling.
    var want = aimPoint(), ease_ = Math.min(1, (dt || 0.016) * 0.7);
    look = [look[0] + (want[0] - look[0]) * ease_, 0.7,
            look[2] + (want[2] - look[2]) * ease_];
    var yaw = 0.22 * Math.sin(wall * 0.06);
    var dist = 14.6 + (teamSize - 1) * 2.9;
    var h = 2.2 + 0.5 * Math.sin(wall * 0.045 + 1) + (teamSize - 1) * 0.35;
    var target = look;
    var p = [target[0] + Math.sin(yaw) * dist, h, target[2] + Math.cos(yaw) * dist];
    var f = norm(sub(target, p)), r = norm(cross(f, [0, 1, 0])), u = cross(r, f);
    cam = { p: p, f: f, r: r, u: u, F: (H / 2) / Math.tan(fov / 2) };
  }

  // World point -> [screenX, screenY, depth]
  function project(w) {
    var d = sub(w, cam.p), z = Math.max(0.05, dot(d, cam.f));
    return [W / 2 + cam.F * dot(d, cam.r) / z, H / 2 - cam.F * dot(d, cam.u) / z, z];
  }

  // ── The draw list ─────────────────────────────────────────────────────
  // Everything the frame wants drawn goes in here with a depth, and the
  // list is sorted once before any of it is painted. The records are kept
  // in a pool and refilled each frame so a steady scene stops allocating.
  var pool = [], dn = 0;
  function put(kind, z) {
    var r = pool[dn];
    if (!r) { r = {}; pool[dn] = r; }
    dn++;
    r.k = kind; r.z = z; r.o = 1;
    return r;
  }
  // A round-capped stroke between two screen points: the QML original's
  // rounded rectangle, which is the same shape.
  function seg(z, a, b, w, col, alpha, cap) {
    var r = put("seg", z);
    r.ax = a[0]; r.ay = a[1]; r.bx = b[0]; r.by = b[1];
    r.w = w; r.c = col; r.o = alpha; r.cap = cap || "butt";
    return r;
  }
  // A limb: dark inside, edged in the fighter's light.
  function limb(z, a, b, w, col, alpha) {
    var r = put("limb", z);
    r.ax = a[0]; r.ay = a[1]; r.bx = b[0]; r.by = b[1];
    r.w = w; r.c = col; r.o = alpha;
    return r;
  }

  var ctx = null;

  function strokeLine(r, width, style) {
    ctx.lineWidth = Math.max(0.35, width);
    ctx.strokeStyle = style;
    ctx.beginPath();
    ctx.moveTo(r.ax, r.ay);
    ctx.lineTo(r.bx, r.by);
    ctx.stroke();
  }

  function ellipse(cx, cy, rx, ry) {
    ctx.beginPath();
    ctx.ellipse(cx, cy, Math.max(0.5, rx), Math.max(0.5, ry), 0, 0, Math.PI * 2);
  }

  var BODY = "#03080b";              // the dark inside of a figure

  // ── Names ─────────────────────────────────────────────────────────────
  // Drawn from the stroke font in vector.js, in screen space at the point
  // over the head, so a name is always square to the viewer however the
  // camera has come round -- and sized off the same perspective divide as
  // the head beneath it, so it shrinks with distance like everything else.
  var Font = null;
  function nameAt(text, cx, cy, cap, col, alpha, z) {
    if (!Font) Font = window.DiscWarsFont || null;
    if (!Font || !text || cap < 2.2) return;       // too far off to read anyway
    var u = cap / Font.height;                     // glyph units to pixels
    var x = cx - Font.width(text) * u / 2;
    var w = Math.max(1, cap * 0.13);
    for (var i = 0; i < text.length; i++) {
      var g = Font.glyph(text.charAt(i));
      if (g) {
        for (var k = 0; k < g.length; k++) {
          var st = g[k];
          for (var j = 0; j + 1 < st.length; j++) {
            seg(z, [x + st[j][0] * u, cy + st[j][1] * u],
                   [x + st[j + 1][0] * u, cy + st[j + 1][1] * u],
                w, col, alpha, "round");
          }
        }
      }
      x += Font.advance * u;
    }
  }

  function paint() {
    var items = pool.slice(0, dn);
    items.sort(function (a, b) { return a.z - b.z; });
    for (var i = 0; i < items.length; i++) {
      var r = items[i];
      ctx.globalAlpha = Math.max(0, Math.min(1, r.o));
      if (r.k === "seg") {
        ctx.lineCap = r.cap;
        strokeLine(r, r.w, r.c);
      } else if (r.k === "limb") {
        ctx.lineCap = "round";
        strokeLine(r, r.w, r.c);                    // the lit edge
        if (r.w > 3.6) strokeLine(r, r.w - 3, BODY);  // hollowed out
      } else if (r.k === "head") {
        ctx.lineCap = "butt";
        ctx.beginPath();
        ctx.roundRect(r.x, r.y, r.w, r.h, Math.min(r.w, r.h) / 2);
        ctx.fillStyle = BODY; ctx.fill();
        ctx.lineWidth = 1.5; ctx.strokeStyle = r.c; ctx.stroke();
        var vh = Math.max(2, r.h * 0.14), vw = r.w * 0.5;
        ctx.beginPath();
        ctx.roundRect(r.x + r.vx, r.y + r.h * 0.42, vw, vh, vh / 2);
        ctx.fillStyle = r.c; ctx.fill();
      } else if (r.k === "disc") {
        ellipse(r.x, r.y, r.w * 0.95, r.h * 0.95);   // glow
        ctx.fillStyle = r.c; ctx.globalAlpha = 0.18 * r.o; ctx.fill();
        ctx.globalAlpha = Math.max(0, Math.min(1, r.o));
        ellipse(r.x, r.y, r.w / 2, r.h / 2);
        ctx.fillStyle = BODY; ctx.fill();
        ctx.lineWidth = Math.max(2, Math.min(r.w, r.h) * 0.12);
        ctx.strokeStyle = r.hot; ctx.stroke();
        ellipse(r.x, r.y, r.w * 0.2, r.h * 0.2);
        ctx.lineWidth = 1.5; ctx.strokeStyle = r.c; ctx.stroke();
      } else if (r.k === "spark") {
        var ring = r.size * (1 + r.age * 8);
        ctx.globalAlpha = Math.max(0, 1 - r.age / 0.5);
        ellipse(r.x, r.y, ring / 2, ring / 2);
        ctx.lineWidth = 2; ctx.strokeStyle = r.c; ctx.stroke();
        ctx.globalAlpha = Math.max(0, 0.85 - r.age * 4);
        ellipse(r.x, r.y, r.size * 0.9, r.size * 0.9);
        ctx.fillStyle = "#ffffff"; ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  // ── Arena: floor far below, the glass back wall, the ceiling edge ─────
  // [from, to, opacity, colour, width]
  var lines = [];
  function rebuildLines() {
    var L = [], X = 16, Z = arenaZ, lo = floorY, hi = ceilY;
    for (var x = -X; x <= X; x += 1.5) L.push([[x, lo, -Z], [x, lo, Z], 0.1, line, 1]);
    for (var z = -Z; z <= Z + 0.01; z += 1) L.push([[-X, lo, z], [X, lo, z], 0.1, line, 1]);
    for (var wx = -X; wx <= X; wx += 4) L.push([[wx, lo, -Z], [wx, hi, -Z], 0.1, line, 1]);
    L.push([[-X, 0, -Z], [X, 0, -Z], 0.08, line, 1]);
    for (var cx = -X; cx <= X; cx += 4) L.push([[cx, hi, -Z], [cx, hi, 2], 0.12, line, 1]);
    L.push([[-X, hi, -Z], [X, hi, -Z], 0.45, lineHi, 1]);
    L.push([[-X, lo, -Z], [-X, hi, -Z], 0.45, lineHi, 1]);
    L.push([[X, lo, -Z], [X, hi, -Z], 0.45, lineHi, 1]);
    lines = L;
  }

  // ── Rings ─────────────────────────────────────────────────────────────
  // Rings are per fighter, per ring: state "up", "falling" (t = when it went)
  // or "rising" (t = when it started back). buildMatch fills them in.

  function ringLook(p, k) {                      // [y offset, opacity]
    var r = pads[p].rings[k];
    if (r.s === "falling") { var a = wall - r.t; return [-4.5 * a * a, Math.max(0, 1 - a / 1.1)]; }
    if (r.s === "rising") { var b = Math.min(1, (wall - r.t) / 0.9); return [-1.5 * (1 - ease(b)), b]; }
    return [0, 1];
  }
  function breakRing(p, k) { pads[p].rings[k] = { s: "falling", t: wall }; }
  function restoreRings(p) {
    for (var k = 0; k < ringCount; k++)
      if (pads[p].rings[k].s !== "up") pads[p].rings[k] = { s: "rising", t: wall };
  }
  // How long a ring stays gone before it rises again by itself. With more
  // fighters there is more shooting, so without this an arena played long
  // enough would end up with nothing left to stand on.
  var ringBack = 26;
  function ringUp(p, k) { return pads[p].rings[k].s !== "falling"; }

  // ── Fighters ──────────────────────────────────────────────────────────
  // Joints (Poses.joints): 0 pelvis, 1/5 hips, 2/6 knees, 3/7 ankles, 4/8 toes,
  // 9 chest, 10 neck, 11 head top, 12/16 shoulders, 13/17 elbows,
  // 14/18 wrists, 15/19 hands (left/right).
  var limbs = [
    [1, 2, 0.13], [2, 3, 0.10], [3, 4, 0.07], [5, 6, 0.13], [6, 7, 0.10], [7, 8, 0.07],
    [1, 5, 0.13], [0, 9, 0.25], [9, 10, 0.08], [12, 16, 0.11],
    [12, 13, 0.08], [13, 14, 0.07], [14, 15, 0.06], [16, 17, 0.08], [17, 18, 0.07], [18, 19, 0.06]
  ];

  // ── Who they are ──────────────────────────────────────────────────────
  // Three pools, drawn from without repeating inside a match. Short enough
  // to read over a head at the back of the arena.
  var NAMES = [
    // Unix commands
    "GREP", "AWK", "SED", "CHMOD", "KILL", "PING", "CURL", "TAR", "CRON",
    "SUDO", "MOUNT", "FSCK", "NICE", "TEE", "SORT", "UNIQ", "FIND", "MAKE",
    "DIFF", "PATCH", "TRAP", "YES", "DMESG", "STTY", "NOHUP", "XARGS",
    // Greek given names
    "ALEXIOS", "NIKOS", "STAVROS", "KOSTAS", "THEO", "ARIS", "PETROS",
    "SPIROS", "ELENI", "SOFIA", "DESPINA", "THALIA", "IOANNA", "ANDREAS",
    "VASILIS", "MANOS", "PHAEDRA", "DAPHNE", "ZOE", "IRIS", "LYDIA",
    "PHOEBE", "CALLISTA", "ORESTES", "AGATHA", "LEANDROS",
    // Languages that are also words
    "BASIC", "FORTRAN", "PASCAL", "LOGO", "FORTH", "SCHEME", "RUST", "SWIFT",
    "JULIA", "ADA", "GO", "LISP", "PROLOG", "EIFFEL", "OBERON", "MODULA",
    "ICON", "SNOBOL", "ELM", "NIM", "CRYSTAL", "RED", "FACTOR", "SELF",
    "CLIPPER", "SIMULA"
  ];

  function freshName(taken) {
    for (var tries = 0; tries < 200; tries++) {
      var n = NAMES[Math.floor(Math.random() * NAMES.length)];
      if (taken.indexOf(n) < 0) { taken.push(n); return n; }
    }
    return "PROC" + Math.floor(Math.random() * 90 + 10);
  }

  // What a fighter is worth at the end of a round. Taking somebody out is
  // worth most; getting a disc past a guard is worth more than answering
  // one, since the arena makes that harder.
  var POINTS = { hits: 3, kills: 5, rings: 2, blocks: 1, dodges: 1 };
  function tally(f) {
    var t = f.stats;
    return t.hits * POINTS.hits + t.kills * POINTS.kills + t.rings * POINTS.rings +
           t.blocks * POINTS.blocks + t.dodges * POINTS.dodges;
  }
  function blankStats() {
    return { throws: 0, hits: 0, blocks: 0, dodges: 0, kills: 0, rings: 0, rounds: 0 };
  }

  function newFighter(team, home, fv) {
    var pd = pads[home];
    return { team: team, home: home, pad: home, foe: -1,
             ring: 0, ang: 0, pos: [pd.cx, pd.cz], fv: fv, move: null, clingRing: -1,
             clingAt: null, willClimb: false, dropFrom: null, clip: "idle", t: rand(0, 1),
             speed: 1, from: null, blend: 1, block: 0, blockTarget: 0, pose: null,
             mode: "stand", mt: 0, yOff: 0, alpha: 1, flip: "side", flipSide: 1,
             high: false, grip: "right", evade: "duck",
             lastAim: -1, lastGuard: -1, lastThrowAim: 1,
             name: "", champion: false, stats: blankStats() };
  }

  // A platform and its four rings. A fighter starts on its own and can end
  // up on a teammate's, so the two are kept apart.
  var pads = [];
  var fs = [], ds = [], ringCircles = [];


  // Lay out a match: two ranks of `n` facing each other across the arena,
  // each fighter on its own platform with its own four rings.
  function buildMatch(n) {
    teamSize = Math.max(1, Math.min(3, n | 0));
    arenaZ = Math.max(5.5, rankGap * (teamSize - 1) / 2 + 3.2);
    pads = []; fs = []; ds = []; ringCircles = [];
    for (var team = 0; team < 2; team++) {
      for (var i = 0; i < teamSize; i++) {
        pads.push({ team: team, rank: i,
                    cx: team === 0 ? -centreX : centreX,
                    cz: (i - (teamSize - 1) / 2) * rankGap,
                    rings: ringRadii.map(function () { return { s: "up" }; }) });
      }
    }
    // One fighter per platform to begin with, in the same order.
    var taken = [];
    pads.forEach(function (pd, i) {
      var f = newFighter(pd.team, i, [pd.team === 0 ? 1 : -1, 0]);
      f.name = freshName(taken);
      fs.push(f);
      ds.push({ state: "back", pos: [0, 0, 0], trail: [], flight: null });
    });
    // Every edge circle of every ring, as [platform, ring, radius].
    for (var g = 0; g < pads.length; g++)
      for (var k = 0; k < ringCount; k++)
        ringRadii[k].forEach(function (r) { if (r > 0) ringCircles.push([g, k, r]); });
    queue = []; wallQueue = []; pieces = []; chains = 0;
    score = [0, 0]; banner = "";
    startBrains();                       // a different match is a different game
    sparkData = [null, null, null, null];
    rebuildLines();
  }

  function alive(p) {
    var m = fs[p].mode;
    return m !== "gone" && m !== "fall" && m !== "derez";
  }
  // Opponents still standing; falls back to any opponent so facing never breaks.
  function foesOf(p) {
    var mine = fs[p].team, live = [], any = [];
    for (var i = 0; i < fs.length; i++) {
      if (fs[i].team === mine) continue;
      any.push(i);
      if (alive(i)) live.push(i);
    }
    return live.length ? live : any;
  }
  function nearestFoe(p) {
    var f = fs[p], best = -1, bd = Infinity;
    foesOf(p).forEach(function (i) {
      var dx = fs[i].pos[0] - f.pos[0], dz = fs[i].pos[1] - f.pos[1], d = dx * dx + dz * dz;
      if (d < bd) { bd = d; best = i; }
    });
    return best;
  }

  var throwSpeed = 1.4;
  function releaseTime() { return Poses.clips.throw.release / Poses.fps / throwSpeed; }

  function sample(name, t) {
    var c = Poses.clips[name], n = c.frames.length, fp = t * Poses.fps;
    if (name === "idle") {                // ping-pong so the stance loops smoothly
      var period = 2 * (n - 1);
      fp = fp % period;
      if (fp > n - 1) fp = period - fp;
    } else {
      fp = Math.min(fp, n - 1);
    }
    var i = Math.floor(fp), k = fp - i, a = c.frames[i], b = c.frames[Math.min(n - 1, i + 1)];
    var out = new Array(a.length);
    for (var j = 0; j < a.length; j++) out[j] = a[j] + (b[j] - a[j]) * k;
    return out;
  }
  function clipLength(name) { return (Poses.clips[name].frames.length - 1) / Poses.fps; }

  function play(p, name, speed) {
    var f = fs[p];
    f.from = f.pose ? f.pose.slice() : null;
    f.blend = 0; f.clip = name; f.t = 0; f.speed = speed || 1;
  }
  function setMode(p, m) { fs[p].mode = m; fs[p].mt = 0; }

  var flipTime = 1.1;                            // fight seconds
  // Dodges in place, and being hit (fight seconds).
  var evadeTime = { duck: 0.9, sweep: 1.0, split: 0.9, hit: 1.2 };
  // Mostly side flips and twists, sometimes a backflip.
  function startFlip(p) {
    var r = Math.random();
    fs[p].flip = r < 0.45 ? "side" : r < 0.8 ? "twist" : "back";
    fs[p].flipSide = Math.random() < 0.5 ? 1 : -1;
    setMode(p, "flip");
  }

  // Move joint j of a pose towards target point q by amount w.
  function pull(pose, j, q, w) {
    for (var c = 0; c < 3; c++) pose[j * 3 + c] += (q[c] - pose[j * 3 + c]) * w;
  }
  function jp(pose, j) { return [pose[j * 3], pose[j * 3 + 1], pose[j * 3 + 2]]; }

  // Local pose (figure facing +x, standing over the origin) for a fighter.
  function localPose(p, dt, realDt) {
    var f = fs[p];
    f.t += dt * f.speed;
    // Flips run on fight time (they dodge discs); drops, falls and the
    // rez stay at real speed so they can be seen.
    f.mt += (f.mode === "flip" || f.mode === "evade" || f.mode === "hit") ? dt : realDt;
    if (f.clip !== "idle" && f.t >= clipLength(f.clip)) play(p, "idle");
    var pose = sample(f.clip, f.t);
    if (f.from && f.blend < 1) {
      f.blend = Math.min(1, f.blend + dt / 0.18);
      for (var j = 0; j < pose.length; j++) pose[j] = f.from[j] + (pose[j] - f.from[j]) * f.blend;
    }

    // The block: the disc held up as a shield, across the chest or
    // overhead against a shot banked off the ceiling; in both hands, or in
    // the left or right alone (f.grip).
    f.block += Math.max(-dt / 0.2, Math.min(dt / 0.1, f.blockTarget - f.block));
    if (f.block > 0) {
      var chest = jp(pose, 9);
      // [shoulder, elbow, wrist, hand] joints of each arm.
      var arms = f.grip === "both" ? [[16, 17, 18, 19], [12, 13, 14, 15]]
               : f.grip === "left" ? [[12, 13, 14, 15]] : [[16, 17, 18, 19]];
      arms.forEach(function (arm) {
        var sh = jp(pose, arm[0]), side = sh[2] - chest[2];
        var two = f.grip === "both";
        if (f.high) {
          // One hand reaches across above the head; two meet over it.
          pull(pose, arm[1], [sh[0] + 0.1, sh[1] + 0.26, sh[2] - side * (two ? 0.1 : 0.2)], f.block);
          pull(pose, arm[2], [sh[0] + 0.16, sh[1] + 0.52, sh[2] - side * (two ? 0.45 : 0.6)], f.block);
          pull(pose, arm[3], [sh[0] + 0.18, sh[1] + 0.62, sh[2] - side * (two ? 0.72 : 0.9)], f.block);
        } else if (two) {
          // Both forearms up, the disc between the hands in front.
          pull(pose, arm[1], [sh[0] + 0.2, sh[1] - 0.16, sh[2] + side * 0.05], f.block);
          pull(pose, arm[2], [chest[0] + 0.4, chest[1] - 0.02, chest[2] + side * 0.5], f.block);
          pull(pose, arm[3], [chest[0] + 0.48, chest[1] + 0.02, chest[2] + side * 0.4], f.block);
        } else {
          pull(pose, arm[1], [sh[0] + 0.24, sh[1] - 0.14, sh[2] - side * 0.2], f.block);
          pull(pose, arm[2], [chest[0] + 0.42, chest[1] - 0.02, chest[2] + side * 0.1], f.block);
          pull(pose, arm[3], [chest[0] + 0.5, chest[1] + 0.02, chest[2] - side * 0.2], f.block);
        }
      });
    }

    if (f.mode === "flip") {
      // Up, tucked, round and down. "side": an aerial, turning about the
      // forward axis and moving sideways out of the disc's line; "twist": a
      // butterfly twist, body tipped nearly flat and spinning about the
      // vertical; "back": a backflip.
      var u = Math.min(1, f.mt / flipTime), s = Math.sin(Math.PI * u), e = ease(u);
      var pv = jp(pose, 0), ch = jp(pose, 9);
      [2, 3, 4, 6, 7, 8].forEach(function (k) { pull(pose, k, pv, (f.flip === "twist" ? 0.25 : 0.5) * s); });
      [13, 14, 15, 17, 18, 19].forEach(function (k) { pull(pose, k, ch, 0.35 * s); });
      var py = pv[1] + 0.1, lift = (f.flip === "twist" ? 1.1 : 1.35) * s;
      for (var q = 0; q < 20; q++) {
        var x = pose[q * 3] - pv[0], y = pose[q * 3 + 1] - py, z = pose[q * 3 + 2] - pv[2], t;
        if (f.flip === "back") {
          var a1 = 2 * Math.PI * e;
          t = x * Math.cos(a1) - y * Math.sin(a1); y = x * Math.sin(a1) + y * Math.cos(a1); x = t;
        } else if (f.flip === "side") {
          var a2 = 2 * Math.PI * e * f.flipSide;
          t = y * Math.cos(a2) - z * Math.sin(a2); z = y * Math.sin(a2) + z * Math.cos(a2); y = t;
        } else {
          var tilt = 1.35 * s, a3 = 2 * Math.PI * e;
          t = y * Math.cos(tilt) - z * Math.sin(tilt); z = y * Math.sin(tilt) + z * Math.cos(tilt); y = t;
          t = x * Math.cos(a3) + z * Math.sin(a3); z = -x * Math.sin(a3) + z * Math.cos(a3); x = t;
        }
        pose[q * 3] = pv[0] + x;
        pose[q * 3 + 1] = py + y + lift;
        pose[q * 3 + 2] = pv[2] + z;
      }
      if (u >= 1) setMode(p, "stand");
    }

    if (f.mode === "evade" || f.mode === "hit") {
      // Blend towards the dodge (or the knock-back) and out again.
      var kind = f.mode === "hit" ? "hit" : f.evade;
      var eu = Math.min(1, f.mt / evadeTime[kind]);
      var ew = eu < 0.2 ? ease(eu / 0.2) : eu > 0.75 ? ease((1 - eu) / 0.25) : 1;
      var tg = evadePose(kind, pose, eu);
      for (var e2 = 0; e2 < pose.length; e2++) pose[e2] += (tg[e2] - pose[e2]) * ew;
      if (kind === "split") {
        var jump = 0.9 * Math.sin(Math.PI * eu);
        for (var jy = 0; jy < 20; jy++) pose[jy * 3 + 1] += jump;
      }
      if (eu >= 1) setMode(p, "stand");
    }

    if (f.mode === "drop" || f.mode === "cling" || f.mode === "fall" || f.mode === "climb") {
      // Hanging by both hands from the ring edge, legs loose; a climb lets
      // go of the pose as it comes up over the edge.
      var hw = f.mode === "climb" ? 1 - ease(Math.min(1, f.mt / 0.6)) : 1;
      [[12, 13, 14, 15], [16, 17, 18, 19]].forEach(function (arm) {
        var s0 = jp(pose, arm[0]);
        pull(pose, arm[1], [s0[0] + 0.04, s0[1] + 0.27, s0[2]], hw);
        pull(pose, arm[2], [s0[0] + 0.06, s0[1] + 0.52, s0[2]], hw);
        pull(pose, arm[3], [s0[0] + 0.07, s0[1] + 0.62, s0[2]], hw);
      });
    }

    f.pose = pose;
    return pose;
  }

  // Full-extent poses for the dodges in place and for being hit, around
  // where the fighter stands (local frame: facing +x, +z its right).
  function evadePose(kind, pose, u) {
    var px = pose[0], pz = pose[2];
    var rs = (pose[16 * 3 + 2] - pose[12 * 3 + 2]) >= 0 ? 1 : -1;
    function P(x, y, z) { return [px + x, y, pz + z * rs]; }
    var J;
    if (kind === "duck") {                            // a deep crouch, head down
      J = [P(0, 0.55, 0), P(0, 0.55, -0.1), P(0.4, 0.6, -0.18), P(0.05, 0.08, -0.2), P(0.2, 0, -0.22),
           P(0, 0.55, 0.1), P(0.35, 0.55, 0.18), P(0, 0.08, 0.2), P(0.15, 0, 0.22),
           P(0.3, 0.95, 0), P(0.4, 1.05, 0), P(0.55, 1.2, 0),
           P(0.3, 0.98, -0.18), P(0.45, 0.75, -0.25), P(0.55, 0.55, -0.2), P(0.6, 0.5, -0.18),
           P(0.3, 0.98, 0.18), P(0.45, 0.75, 0.25), P(0.55, 0.55, 0.2), P(0.6, 0.5, 0.18)];
    } else if (kind === "sweep") {                    // low on the hands, one leg sweeping round
      var th = 2 * Math.PI * ease(u), dx = Math.cos(th), dz = Math.sin(th);
      J = [P(0, 0.45, 0), P(0, 0.45, -0.1), P(0.3, 0.35, -0.25), P(0, 0.05, -0.35), P(0.12, 0, -0.38),
           P(0, 0.45, 0.1), P(dx * 0.45, 0.2, 0.1 + dz * 0.45), P(dx * 0.9, 0.08, 0.1 + dz * 0.9),
           P(dx * 1.05, 0.08, 0.1 + dz * 1.05),
           P(0.1, 0.85, 0.05), P(0.15, 0.95, 0.05), P(0.22, 1.1, 0.05),
           P(0.1, 0.88, -0.18), P(0.2, 0.55, -0.3), P(0.3, 0.15, -0.35), P(0.35, 0.02, -0.35),
           P(0.1, 0.88, 0.18), P(0.25, 0.55, 0.3), P(0.35, 0.2, 0.35), P(0.4, 0.05, 0.35)];
    } else if (kind === "split") {                    // legs out wide, hands to the toes
      J = [P(0, 1.0, 0), P(0, 1.0, -0.1), P(0.15, 1.0, -0.5), P(0.3, 1.0, -0.9), P(0.38, 1.02, -0.95),
           P(0, 1.0, 0.1), P(0.15, 1.0, 0.5), P(0.3, 1.0, 0.9), P(0.38, 1.02, 0.95),
           P(0.12, 1.45, 0), P(0.15, 1.58, 0), P(0.18, 1.78, 0),
           P(0.12, 1.48, -0.18), P(0.2, 1.3, -0.45), P(0.28, 1.12, -0.7), P(0.32, 1.06, -0.8),
           P(0.12, 1.48, 0.18), P(0.2, 1.3, 0.45), P(0.28, 1.12, 0.7), P(0.32, 1.06, 0.8)];
    } else {                                          // hit: thrown back, arms flung wide
      J = [P(-0.12, 0.92, 0), P(-0.12, 0.92, -0.1), P(0.05, 0.5, -0.14), P(0.1, 0.08, -0.16), P(0.25, 0, -0.17),
           P(-0.12, 0.92, 0.1), P(-0.05, 0.5, 0.14), P(-0.1, 0.08, 0.16), P(0.05, 0, 0.17),
           P(-0.35, 1.35, 0), P(-0.42, 1.45, 0), P(-0.5, 1.62, 0),
           P(-0.35, 1.38, -0.2), P(-0.3, 1.55, -0.45), P(-0.15, 1.6, -0.65), P(-0.1, 1.6, -0.72),
           P(-0.35, 1.38, 0.2), P(-0.3, 1.55, 0.45), P(-0.15, 1.6, 0.65), P(-0.1, 1.6, 0.72)];
    }
    var out = [];
    J.forEach(function (j) { out.push(j[0], j[1], j[2]); });
    return out;
  }

  // ── Positions on the rings ────────────────────────────────────────────
  function ringMid(k) { return k === 0 ? 0 : (ringRadii[k][0] + ringRadii[k][1]) / 2; }
  function groundAt(p, r, a) {
    var pd = pads[fs[p].pad];
    return [pd.cx + Math.cos(a) * r, pd.cz + Math.sin(a) * r];
  }
  function intactRingsOn(padIdx) {
    var out = [];
    for (var k = 0; k < ringCount; k++) if (ringUp(padIdx, k)) out.push(k);
    return out;
  }
  function intactRings(p) { return intactRingsOn(fs[p].pad); }

  // A platform with nobody standing on it. A fighter commits to a platform
  // the moment it starts moving, so two cannot claim the same one.
  function occupied(padIdx) {
    for (var i = 0; i < fs.length; i++)
      if (alive(i) && fs[i].pad === padIdx) return true;
    return false;
  }
  // Its own side's platforms next to this one in the rank, standing empty.
  // One is empty because the teammate who had it is out of the round.
  function freeNeighbours(p) {
    var here = pads[fs[p].pad], out = [];
    for (var i = 0; i < pads.length; i++) {
      if (pads[i].team !== here.team) continue;
      if (Math.abs(pads[i].rank - here.rank) !== 1) continue;
      if (occupied(i) || !intactRingsOn(i).length) continue;
      out.push(i);
    }
    return out;
  }

  // Move to ring k of platform `padIdx` at angle a over dur fight-seconds,
  // hopping `hop` metres. Crossing to another platform is further than
  // stepping between rings, so it takes longer and goes higher.
  function relocate(p, padIdx, k, a, dur, hop) {
    var f = fs[p], across = padIdx !== f.pad;
    f.pad = padIdx;                       // claimed from here on
    f.ring = k; f.ang = a;
    f.move = { from: f.pos.slice(), to: groundAt(p, ringMid(k), a), t0: now,
               dur: across ? dur * 1.3 : dur, hop: across ? Math.max(hop, 0.6) : hop };
  }

  // Where a dodge can go: the nearest ring still up that is not this one
  // (across a gap if need be; never off the edge), and round a little.
  // Where a dodge can go, as [platform, ring, angle]: the nearest ring still
  // up that is not this one (across a gap if need be, never off the edge) --
  // or, once a teammate is out and its platform stands empty, across to that
  // instead, landing on the side it came from.
  function dodgeSpot(p) {
    var f = fs[p], best = [];
    intactRings(p).forEach(function (k) {
      if (k === f.ring) return;
      var d = Math.abs(k - f.ring);
      if (!best.length || d < best[0][1]) best = [[k, d]];
      else if (d === best[0][1]) best.push([k, d]);
    });
    var across = freeNeighbours(p);
    // The longer jump is the rarer one: it is only taken about a third of the
    // time it is on offer, and always when there is nowhere else to go.
    if (across.length && (!best.length || Math.random() < 0.35)) {
      var n = across[Math.floor(Math.random() * across.length)];
      var up = intactRingsOn(n);
      var here = pads[f.pad], there = pads[n];
      var facing = Math.atan2(here.cz - there.cz, here.cx - there.cx);
      return [n, up[Math.floor(Math.random() * up.length)], facing + rand(-0.5, 0.5)];
    }
    if (!best.length) return null;
    var k = best[Math.floor(Math.random() * best.length)][0];
    return [f.pad, k, f.ang + (Math.random() < 0.5 ? -1 : 1) * rand(0.6, 1.3)];
  }

  function hangOffset(p) { return 0.03 - Math.max(fs[p].pose[15 * 3 + 1], fs[p].pose[19 * 3 + 1]); }

  // Knocked back off the ring edge with nothing behind: grab ring k's edge
  // at radius r, angle a.
  function slideOff(p, k, r, a) {
    var f = fs[p];
    f.move = null;
    f.clingRing = k;
    f.willClimb = Math.random() < 0.33;
    f.dropFrom = f.pos.slice();
    f.clingAt = groundAt(p, r, a);
    setMode(p, "drop");
  }

  // Hit: slide back a ring, away from the opponent; with no ring there (or
  // it is gone), slide off this one and hang from its edge.
  function knockBack(p) {
    var f = fs[p], pd = pads[f.pad], rel = [f.pos[0] - pd.cx, f.pos[1] - pd.cz];
    var awayOut = rel[0] * -f.fv[0] + rel[1] * -f.fv[1] >= 0 || f.ring === 0;
    var back = awayOut ? f.ring + 1 : f.ring - 1;
    var a = f.ring === 0 ? Math.atan2(-f.fv[1], -f.fv[0]) : f.ang;
    if (back >= 0 && back < ringCount && ringUp(f.pad, back)) {
      setMode(p, "hit");
      relocate(p, f.pad, back, a, 0.45, 0.05);
    } else {
      slideOff(p, f.ring, awayOut ? ringRadii[f.ring][1] : ringRadii[f.ring][0], a);
    }
  }

  function drop(p) {
    var f = fs[p], near = null;
    intactRings(p).forEach(function (k) {
      if (near === null || Math.abs(k - f.ring) < Math.abs(near - f.ring)) near = k;
    });
    f.move = null;
    if (near === null) { setMode(p, "fall"); return false; }
    var edge = near < f.ring ? ringRadii[near][1] : ringRadii[near][0];
    f.clingRing = near;
    f.willClimb = Math.random() < 0.33;                  // one in three pulls itself back up
    f.dropFrom = f.pos.slice();
    f.clingAt = groundAt(p, edge, f.ring === 0 ? rand(0.5, 2.6) : f.ang);
    setMode(p, "drop");
    return true;
  }

  function updateMode(p) {
    var f = fs[p];
    // Facing: always towards the opponent.
    if (f.foe < 0 || !alive(f.foe)) f.foe = nearestFoe(p);
    var o = fs[f.foe >= 0 ? f.foe : p].pos;
    var dx = o[0] - f.pos[0], dz = o[1] - f.pos[1], l = Math.sqrt(dx * dx + dz * dz) || 1;
    if (l < 1e-6) { dx = f.team === 0 ? 1 : -1; dz = 0; l = 1; }
    f.fv = [dx / l, dz / l];
    var hopY = 0;
    if (f.move) {
      var u = Math.min(1, (now - f.move.t0) / f.move.dur);
      f.pos = [f.move.from[0] + (f.move.to[0] - f.move.from[0]) * ease(u),
               f.move.from[1] + (f.move.to[1] - f.move.from[1]) * ease(u)];
      hopY = f.move.hop * Math.sin(Math.PI * u);
      if (u >= 1) f.move = null;
    }
    if (f.mode === "drop") {
      var v = Math.min(1, f.mt / 0.35);
      f.yOff = hangOffset(p) * ease(v);
      f.pos = [f.dropFrom[0] + (f.clingAt[0] - f.dropFrom[0]) * ease(v),
               f.dropFrom[1] + (f.clingAt[1] - f.dropFrom[1]) * ease(v)];
      if (v >= 1) setMode(p, "cling");
    } else if (f.mode === "cling") {
      f.yOff = hangOffset(p) + 0.03 * Math.sin(wall * 2.4);
      if (f.willClimb && f.mt > 0.8) setMode(p, "climb");
      else if (f.mt > 14) {
        // Nobody came to finish it off. Hanging there for the rest of the
        // round is neither much to watch nor survivable: with a ring still
        // under it, it hauls itself up; without one, its grip goes. A round
        // ends when a side is cleared, so this is also what stops two last
        // fighters hanging opposite each other with nobody able to act.
        if (ringUp(f.pad, f.clingRing)) { f.willClimb = true; setMode(p, "climb"); }
        else { setMode(p, "fall"); eliminated(p, 0.9); }   // owns no exchange to pass on
      }
    } else if (f.mode === "climb") {
      // Up and over the edge, onto the ring it was holding.
      var pc = pads[f.pad];
      var c = Math.min(1, f.mt / 0.6), top = groundAt(p, ringMid(f.clingRing), Math.atan2(f.clingAt[1] - pc.cz, f.clingAt[0] - pc.cx));
      f.yOff = hangOffset(p) * (1 - ease(c)) + 0.25 * Math.sin(Math.PI * c);
      f.pos = [f.clingAt[0] + (top[0] - f.clingAt[0]) * ease(c), f.clingAt[1] + (top[1] - f.clingAt[1]) * ease(c)];
      if (c >= 1) {
        f.ring = f.clingRing;
        f.ang = Math.atan2(f.clingAt[1] - pc.cz, f.clingAt[0] - pc.cx);
        f.clingRing = -1;
        f.willClimb = false;
        setMode(p, "stand");
      }
    } else if (f.mode === "fall") {
      f.yOff = Math.min(0, hangOffset(p)) - 4.9 * f.mt * f.mt;
      f.alpha = Math.max(0, 1 - f.mt / 0.9);
      if (f.mt > 0.9) { spark([f.pos[0], f.yOff + 1, f.pos[1]], "#ffffff"); setMode(p, "gone"); }
    } else if (f.mode === "rez") {
      f.yOff = 0;
      f.alpha = Math.min(1, f.mt / 0.8);
      if (f.mt >= 0.8) setMode(p, "stand");
    } else if (f.mode === "stand" || f.mode === "flip" || f.mode === "evade" || f.mode === "hit") {
      f.yOff = hopY; f.alpha = 1;
    }
  }

  // Local pose (facing +x) to the world: placed at the fighter's spot and
  // turned to face the opponent.
  function toWorld(p, local, j) {
    var f = fs[p], lx = local[j * 3], lz = local[j * 3 + 2];
    return [f.pos[0] + f.fv[0] * lx - f.fv[1] * lz, local[j * 3 + 1] + f.yOff, f.pos[1] + f.fv[1] * lx + f.fv[0] * lz];
  }
  function ahead(p, w, d) { return [w[0] + fs[p].fv[0] * d, w[1], w[2] + fs[p].fv[1] * d]; }
  function canAct(p) { return fs[p].mode === "stand"; }

  // ── Discs ─────────────────────────────────────────────────────────────
  // state: "back" (on the fighter's back), "hand", "shield", or "flight".
  var trailLen = 16;

  function handWorld(p) { return toWorld(p, fs[p].pose, 19); }
  function chestWorld(p) { return toWorld(p, fs[p].pose, 9); }
  function backWorld(p) {
    var c = chestWorld(p);
    var b = ahead(p, c, -0.16);
    return [b[0], c[1] - 0.12, b[2]];
  }
  // Where the shield is: in the gripping hand, or between both hands.
  function shieldWorld(p) {
    var f = fs[p];
    var h = f.grip === "both" ? lerp3(toWorld(p, f.pose, 15), toWorld(p, f.pose, 19), 0.5)
          : f.grip === "left" ? toWorld(p, f.pose, 15) : handWorld(p);
    return f.high ? [h[0], h[1] + 0.08, h[2]] : ahead(p, h, 0.1);
  }
  function discHome(p) { return ds[p].state !== "flight"; }

  // A flight: quadratic Beziers through control points; a point may be a
  // function, so a disc flying home follows its owner's moving hand.
  function fly(p, pts, dur, done) {
    ds[p].state = "flight";
    ds[p].trail = [];
    ds[p].flight = { pts: pts, t0: now, dur: dur, done: done };
  }
  function flightPoint(fl, t) {
    var pts = fl.pts.map(function (q) { return typeof q === "function" ? q() : q; });
    var n = (pts.length - 1) / 2, i = Math.min(n - 1, Math.floor(t * n)), u = t * n - i;
    var a = pts[2 * i], c = pts[2 * i + 1], b = pts[2 * i + 2];
    return lerp3(lerp3(a, c, u), lerp3(c, b, u), u);
  }

  var sparkNext = 0;
  var sparkData = [null, null, null, null];
  function spark(w, col) {
    sparkData[sparkNext] = { w: w, born: wall, col: col };
    sparkNext = (sparkNext + 1) % 4;
  }

  // ── Derez debris ──────────────────────────────────────────────────────
  var pieceCount = 100;              // per fighter
  var pieceCap = 320;                // across the arena, however many derez at once
  var pieces = [];

  // Break fighter p into pieces: each limb into six, the head into four.
  function shatter(p) {
    var f = fs[p], Wp = [];
    for (var j = 0; j < 20; j++) Wp.push(toWorld(p, f.pose, j));
    var centre = lerp3(Wp[0], Wp[9], 0.5), col = fs[p].team === 0 ? programHi : sentinelHi;
    var out = [];
    function piece(a, b, thick) {
      var mid = lerp3(a, b, 0.5), half = [(b[0] - a[0]) * 0.45, (b[1] - a[1]) * 0.45, (b[2] - a[2]) * 0.45];
      var dir = norm(sub(mid, centre)), k = rand(0.6, 2.2);
      out.push({ mid: mid, half: half, thick: thick, col: col, born: wall,
                 vel: [dir[0] * k + rand(-0.5, 0.5), rand(0.8, 2.8), dir[2] * k + rand(-0.5, 0.5)],
                 axis: norm([rand(-1, 1), rand(-1, 1), rand(-1, 1)]), spin: rand(-9, 9) });
    }
    limbs.forEach(function (lb) {
      for (var i = 0; i < 6; i++) piece(lerp3(Wp[lb[0]], Wp[lb[1]], i / 6), lerp3(Wp[lb[0]], Wp[lb[1]], (i + 1) / 6), lb[2]);
    });
    var hc = lerp3(Wp[10], Wp[11], 0.55);
    for (var h = 0; h < 4; h++) {
      var a0 = h * Math.PI / 2, a1 = a0 + Math.PI / 2;
      piece([hc[0] + Math.cos(a0) * 0.12, hc[1] + Math.sin(a0) * 0.13, hc[2]],
            [hc[0] + Math.cos(a1) * 0.12, hc[1] + Math.sin(a1) * 0.13, hc[2]], 0.05);
    }
    // Two fighters can go at once in a team match, so clouds stack up rather
    // than replacing each other; the oldest go if there are too many.
    pieces = pieces.concat(out);
    if (pieces.length > pieceCap) pieces = pieces.slice(pieces.length - pieceCap);
  }

  // Rotate v about unit axis k by angle t (Rodrigues).
  function turn(v, k, t) {
    var c = Math.cos(t), s = Math.sin(t), d = dot(k, v), x = cross(k, v);
    return [v[0] * c + x[0] * s + k[0] * d * (1 - c), v[1] * c + x[1] * s + k[1] * d * (1 - c),
            v[2] * c + x[2] * s + k[2] * d * (1 - c)];
  }

  // Tumble the pieces down to the arena floor, bounce, settle and fade.
  function stepPieces(dt) {
    var live = [];
    for (var i = 0; i < pieces.length; i++) {
      var pc = pieces[i];
      var fade = wall - pc.born < 2.2 ? 1 : Math.max(0, 1 - (wall - pc.born - 2.2) / 1.0);
      if (fade <= 0) continue;          // burnt out: drop it
      live.push(pc);
      pc.vel[1] -= 9.8 * dt;
      pc.mid = [pc.mid[0] + pc.vel[0] * dt, pc.mid[1] + pc.vel[1] * dt, pc.mid[2] + pc.vel[2] * dt];
      pc.half = turn(pc.half, pc.axis, pc.spin * dt);
      if (pc.mid[1] < floorY + 0.02) {
        // Hit the floor: bounce low, lose speed, and lie flatter.
        pc.mid[1] = floorY + 0.02;
        pc.vel = [pc.vel[0] * 0.5, -pc.vel[1] * 0.25, pc.vel[2] * 0.5];
        pc.spin *= 0.5;
        pc.half = [pc.half[0], pc.half[1] * 0.4, pc.half[2]];
      }
      var a = project(sub(pc.mid, pc.half));
      var b = project([pc.mid[0] + pc.half[0], pc.mid[1] + pc.half[1], pc.mid[2] + pc.half[2]]);
      seg(1000 - (a[2] + b[2]) * 10, a, b, Math.max(1.5, 0.5 * pc.thick * cam.F / a[2]), pc.col, fade, "round");
    }
    pieces = live;
  }

  // ── Reading the throw ─────────────────────────────────────────────────
  // A throw is aimed high, at the body or low, and each guard answers one
  // of the three: duck a high one, block a body one on the disc, jump a low
  // one. So neither side has a move worth settling on, and the only edge to
  // be had is in reading the other -- which is what the two policies in
  // learn.js are for. Without that file this falls back to choosing at
  // random, which is the game played blind, and still plays.
  var NFEAT = 12;
  var brains = null;
  var HEIGHT = [1.55, 1.12, 0.45];       // where a high, body or low throw passes
  var CONNECT = 0.2;                     // a throw that gets through still has to land

  function startBrains() {
    brains = (window.DiscWarsLearn)
      ? [new window.DiscWarsLearn.Side(NFEAT, 16), new window.DiscWarsLearn.Side(NFEAT, 16)]
      : null;
  }

  // What both policies see: the shape of this exchange, and what this
  // defender did the last time it was thrown at -- the tell an attacker has
  // to read, and the habit a defender has to avoid falling into.
  function situation(att, def) {
    var a = fs[att], d = fs[def];
    return [
      1,
      discHome(def) ? 1 : 0,
      d.ring / (ringCount - 1),
      a.ring / (ringCount - 1),
      d.lastAim === 0 ? 1 : 0, d.lastAim === 1 ? 1 : 0, d.lastAim === 2 ? 1 : 0,
      d.lastGuard === 0 ? 1 : 0, d.lastGuard === 1 ? 1 : 0, d.lastGuard === 2 ? 1 : 0,
      (liveCount(a.team) - liveCount(d.team)) / teamSize,
      teamSize / 3
    ];
  }

  function readThrow(att, def, canBlock) {
    if (!brains) {
      var aim = Math.floor(Math.random() * 3);
      var guards = canBlock ? [0, 1, 2] : [0, 2];
      var guard = guards[Math.floor(Math.random() * guards.length)];
      fs[att].lastThrowAim = aim;
      return { aim: aim, guard: guard, through: guard !== aim };
    }
    var x = situation(att, def);
    var d = window.DiscWarsLearn.decide(brains[fs[att].team], brains[fs[def].team], x, canBlock);
    window.DiscWarsLearn.settle(brains[fs[att].team], brains[fs[def].team], x, d);
    fs[def].lastAim = d.aim;
    fs[def].lastGuard = d.guard;
    return d;
  }

  // ── The duel ──────────────────────────────────────────────────────────
  // Anything listening to the fight -- the sequencer, if it is on. Emitting
  // is guarded so a listener that throws cannot take the fight down with it.
  var listeners = [];
  function emit(kind, info) {
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](kind, info); } catch (e) { /* not the fight's problem */ }
    }
  }

  var queue = [];
  function after(delay, fn) { queue.push({ at: now + delay, fn: fn }); }
  // For what waits on something shown at real speed (a fall, a rez).
  var wallQueue = [];
  function afterWall(delay, fn) { wallQueue.push({ at: wall + delay, fn: fn }); }
  function hot(p) { return fs[p].team === 0 ? programHi : sentinelHi; }

  function flyHome(p, from) {
    var mid = lerp3(from, handWorld(p), 0.5);
    fly(p, [from, [mid[0], mid[1] + rand(0.4, 1.0), mid[2] + rand(-1.2, 1.2)], function () { return handWorld(p); }],
        rand(0.8, 1.0), function () {
          ds[p].state = "hand";
          after(0.3, function () { if (ds[p].state === "hand") ds[p].state = "back"; });
        });
  }

  // Wind up and release; `launch` gets the release point.
  var lastThrow = 0;
  function throwFrom(p, launch) {
    lastThrow = wall;
    play(p, "throw", throwSpeed);
    after(0.12, function () { ds[p].state = "hand"; });
    after(releaseTime(), function () {
      if (canAct(p)) {
        launch(handWorld(p));                 // a body shot picks its aim in here
        fs[p].stats.throws++;
        emit("throw", { team: fs[p].team, aim: fs[p].lastThrowAim });
        return;
      }
      ds[p].state = "back";                           // lost its footing mid-throw
      after(0.4, function () { rally(p); });          // the exchange carries on without it
    });
  }

  // Where a banked shot lands on ring k: under the fighter if it stands on
  // it, else somewhere on the side nearer the camera.
  function ringPoint(q, k) {
    var a = k === fs[q].ring ? fs[q].ang : rand(0.35, 2.8);
    var g = groundAt(q, k === 0 ? 0.15 : ringMid(k), a);
    return [g[0], 0, g[1]];
  }

  // Hold the disc up as a shield (overhead, or across the chest) and let
  // it go again a moment after the hit.
  function raiseShield(p, high) {
    if (!canAct(p) || !discHome(p)) return false;
    fs[p].high = high;
    // Half the time both hands; otherwise the left or the right.
    var r = Math.random();
    fs[p].grip = r < 0.5 ? "both" : r < 0.75 ? "left" : "right";
    fs[p].blockTarget = 1;
    ds[p].state = "shield";
    return true;
  }
  function lowerShield(p) {
    after(0.3, function () {
      fs[p].blockTarget = 0;
      if (ds[p].state === "shield") ds[p].state = "back";
    });
  }

  // Bank a throw off the ceiling onto one of the opponent's rings, often
  // the one it stands on. A defender with its disc at home may catch it
  // overhead instead; a clinging one cannot.
  function bankShot(p, q, k) {
    fs[p].lastThrowAim = 0;                   // off the ceiling: the high register
    throwFrom(p, function (from) {
      var caught = fs[q].mode === "stand" && canAct(q) && discHome(q) && Math.random() < 0.4;
      var over = ahead(q, chestWorld(q), 0.15);
      var to = caught ? [over[0], 2.3, over[2]] : ringPoint(q, k);
      var top = [lerp3(from, to, 0.55)[0], ceilY, rand(-1.2, 1.2)];
      var dur = rand(1.15, 1.35);
      if (caught) after(dur - 0.35, function () { if (!raiseShield(q, true)) caught = false; });
      fly(p, [from, lerp3(from, top, 0.5).map(function (v, i) { return i === 1 ? v + 0.6 : v; }), top,
              lerp3(top, to, 0.5), to], dur, function () {
        spark(to, hot(p));
        flyHome(p, to);
        if (caught) {
          lowerShield(q);
          after(rand(0.3, 0.5), function () { rally(q); });
          return;
        }
        breakRing(fs[q].pad, k);
        fs[p].stats.rings++;
        var f = fs[q];
        if (((f.mode === "cling" || f.mode === "climb") && k === f.clingRing) ||
            (f.mode === "stand" && k === f.ring && !drop(q))) {
          // Nothing left to hold on to.
          setMode(q, "fall");
          // Taking a fighter out does not end the exchange unless it was the
          // last of its side; the thrower carries it on against whoever is left.
          if (!eliminated(q, 2.4, p)) after(rand(0.7, 1.1), function () { rally(p); });
          return;
        }
        // Let a fighter who has just dropped hang there a moment.
        if (f.mode === "stand") after(rand(0.3, 0.5), function () { rally(q); });
        else afterWall(rand(1.1, 1.5), function () { rally(p); });
      });
    });
    // Spark the ceiling as the disc caroms off it.
    after(releaseTime() + 0.47, function () {
      if (ds[p].state === "flight") spark(ds[p].pos, "#ffffff");
    });
  }

  // A throw at the body, aimed high, at the chest or low. The defender
  // answers with one of the three guards; if it picks the one that covers
  // that aim the disc comes off it, and if it picks wrong the disc goes
  // past -- and now and then finds its mark.
  function bodyShot(p, q) {
    throwFrom(p, function (from) {
      var canBlock = discHome(q) && canAct(q);
      var call = readThrow(p, q, canBlock);
      var pass = HEIGHT[call.aim] + rand(-0.08, 0.08);

      if (!call.through && call.guard === 1) {
        // Caught on the disc, held up across the chest.
        var to = ahead(q, chestWorld(q), 0.6);
        to[1] += 0.05;
        var dur = rand(0.85, 1.05), mid = lerp3(from, to, 0.5);
        after(Math.max(0, dur - 0.3), function () { raiseShield(q, false); });
        fly(p, [from, [mid[0], mid[1] + rand(0.1, 0.6), mid[2] + rand(-1.4, 1.4)], to], dur, function () {
          spark(to, hot(p));
          fs[q].stats.blocks++;
          emit("block", { team: fs[q].team, aim: call.aim });
          lowerShield(q);
          flyHome(p, to);
          after(rand(0.25, 0.45), function () { rally(q); });
        });
        return;
      }

      if (call.through && Math.random() < CONNECT) {
        // It found its mark: knocked back a ring and stunned, or derezzed.
        var hitAt = chestWorld(q);
        fly(p, [from, lerp3(from, hitAt, 0.5).map(function (v, i) { return i === 1 ? v + rand(0.1, 0.4) : v; }), hitAt],
            rand(0.85, 1.05), function () {
          spark(hitAt, hot(p));
          fs[p].stats.hits++;
          flyHome(p, hitAt);
          if (canAct(q) && Math.random() < 0.3) {
            shatter(q);
            spark(hitAt, "#ffffff");
            setMode(q, "derez");
            if (!eliminated(q, 3.0, p)) after(rand(0.9, 1.3), function () { rally(p); });
            return;
          }
          if (canAct(q)) knockBack(q);
          after(1.0, function () { rally(p); });
        });
        return;
      }

      // Either the guard covered it and the disc goes by, or the guard was
      // wrong and it goes by anyway: on to the glass behind, and home.
      // The move shown is the one the defender actually chose -- a duck or
      // a sweep kick under a high throw, a split jump over a low one -- and
      // where there is somewhere to go it may instead step or flip clear,
      // which is what carries a fighter onto a fallen teammate's rings.
      if (!call.through) fs[q].stats.dodges++;   // ducked or jumped it clean
      var lateral = call.guard !== 1 && Math.random() < 0.45 && dodgeSpot(q);
      var kind = lateral ? (Math.random() < 0.5 ? "sidestep" : "flip")
               : call.guard === 0 ? (Math.random() < 0.5 ? "duck" : "sweep")
               : call.guard === 2 ? "split"
               : "duck";                                   // blocked with the disc away
      var qp = pads[fs[q].pad];
      var glass = [qp.cx > 0 ? 15.8 : -15.8, pass, qp.cz + rand(-1.0, 1.0)];
      var dur2 = rand(1.25, 1.4);
      var passAt = Math.abs(fs[q].pos[0] - from[0]) / Math.abs(glass[0] - from[0]);
      var lead = kind === "flip" ? 0.45 : kind === "sidestep" ? 0.4 : 0.45 * evadeTime[kind];
      after(Math.max(0, dur2 * passAt - lead), function () {
        if (!canAct(q)) return;
        var spot = lateral ? dodgeSpot(q) : null;
        if (kind === "flip") {
          startFlip(q);
          if (spot) relocate(q, spot[0], spot[1], spot[2], flipTime, 0);
        } else if (kind === "sidestep") {
          play(q, "dodge", 1.3);
          if (spot) relocate(q, spot[0], spot[1], spot[2], 0.5, 0.2);
        } else {
          fs[q].evade = kind;
          setMode(q, "evade");
        }
      });
      var mid2 = lerp3(from, glass, 0.5);
      fly(p, [from, [mid2[0], pass, mid2[2] + rand(-0.6, 0.6)], glass], dur2, function () {
        spark(glass, hot(p));
        flyHome(p, glass);
        after(rand(0.3, 0.5), function () { rally(q); });
      });
    });
  }

  // Both throw together; the discs meet between them and fly home.
  function clash(p, q) {
    var m = lerp3(chestWorld(p), chestWorld(q), 0.5);
    m[1] += rand(0.2, 0.7);
    m[2] += rand(-0.6, 0.6);
    var landed = 0;
    [p, q].forEach(function (who) {
      fs[who].lastThrowAim = 1;               // they meet in the middle
      throwFrom(who, function (from) {
        var mid = lerp3(from, m, 0.5);
        fly(who, [from, [mid[0], mid[1] + 0.3, mid[2] + rand(-0.6, 0.6)], m], 0.65, function () {
          if (++landed < 2) return;
          spark(m, "#ffffff");
          flyHome(p, m); flyHome(q, m);
          after(rand(1.0, 1.4), function () { rally(Math.random() < 0.5 ? p : q); });
        });
      });
    });
  }

  // Which opponent p goes after: finish one that is hanging on, otherwise
  // mostly stay with the one it is already fighting, and now and then turn
  // on someone else.
  function pickFoe(p) {
    var live = foesOf(p).filter(alive);
    if (!live.length) return -1;
    var hanging = live.filter(function (i) { return fs[i].mode === "cling" && !fs[i].willClimb; });
    if (hanging.length && Math.random() < 0.7) return hanging[Math.floor(Math.random() * hanging.length)];
    if (live.indexOf(fs[p].foe) >= 0 && Math.random() < 0.65) return fs[p].foe;
    return live[Math.floor(Math.random() * live.length)];
  }

  // How many exchanges are running at once. Each one is a chain: an attack,
  // and on the way out another attack from whoever it left standing. There
  // is one chain per fighter per side, so a 3v3 keeps three duels going.
  var chains = 0;
  function startChain() {
    var idle = [];
    for (var i = 0; i < fs.length; i++)
      if (alive(i) && canAct(i) && discHome(i) && !fs[i].move) idle.push(i);
    if (!idle.length) return false;
    chains++;
    rally(idle[Math.floor(Math.random() * idle.length)]);
    return true;
  }

  // p's turn to attack.
  function rally(p) {
    if (!alive(p)) {
      // Whoever was carrying this exchange is gone; hand it to a teammate.
      var mates = [];
      for (var i = 0; i < fs.length; i++)
        if (fs[i].team === fs[p].team && alive(i)) mates.push(i);
      if (!mates.length) { chains = Math.max(0, chains - 1); return; }
      p = mates[Math.floor(Math.random() * mates.length)];
    }
    var q = pickFoe(p);
    if (q < 0) { chains = Math.max(0, chains - 1); return; }
    fs[p].foe = q;
    if (!canAct(p)) { after(0.3, function () { rally(q); }); return; }
    if (!discHome(p)) { after(0.2, function () { rally(p); }); return; }
    if (fs[q].mode === "climb" || (fs[q].mode === "cling" && fs[q].willClimb)) {
      afterWall(0.4, function () { rally(p); });                                // let it try
      return;
    }
    if (fs[q].mode === "cling") { bankShot(p, q, fs[q].clingRing); return; }     // finish it
    // Now and then, move to another ring before throwing.
    if (!fs[p].move && Math.random() < 0.3) {
      var spot = dodgeSpot(p);
      if (spot) {
        relocate(p, spot[0], spot[1], spot[2], 0.45, 0.3);
        after(0.5, function () { rally(p); });
        return;
      }
    }
    if (canAct(q) && discHome(q) && Math.random() < 0.15) { clash(p, q); return; }
    if (Math.random() < 0.12) {
      // Bank one off the ceiling: at the ring it stands on, or another.
      var up = intactRings(q);
      bankShot(p, q, Math.random() < 0.55 ? fs[q].ring : up[Math.floor(Math.random() * up.length)]);
      return;
    }
    bodyShot(p, q);
  }

  // ── Rounds ────────────────────────────────────────────────────────────
  // A fighter that goes over the edge is out. Nobody comes back until one
  // side has been cleared off the board entirely; then the whole arena is
  // set up again and the next round begins.
  // Rounds won, and what to say when one is. A match is a fresh scoreline,
  // so changing the match size starts the count again.
  var score = [0, 0];
  var banner = "";
  var SIDE_NAME = ["PROGRAMS", "SENTINELS"];

  function liveCount(team) {
    var n = 0;
    for (var i = 0; i < fs.length; i++) if (fs[i].team === team && alive(i)) n++;
    return n;
  }

  // Called the moment a fighter is out, with how long the fall or the derez
  // still has to play before the arena should be reset. True once that was
  // the last of its side: the round is over and the caller's exchange dies
  // with it, rather than being handed on.
  function eliminated(p, settle, by) {
    if (by != null && by !== p && fs[by]) fs[by].stats.kills++;
    // Called once per fighter per round, so it is what the tempo counts.
    emit("out", { team: fs[p].team, left: liveCount(fs[p].team) });
    if (liveCount(fs[p].team) > 0) return false;   // its side fights on without it
    var winner = 1 - fs[p].team;
    score[winner]++;
    banner = SIDE_NAME[winner] + " WIN";
    afterWall(settle + 1.4, newRound);             // let the last one finish falling
    return true;
  }

  // Everyone back on their platform, every ring up, and the next round on.
  function newRound() {
    emit("round", {});                             // everything back to the top

    // One fighter goes through to the next round, and only one: whoever is
    // still standing with the most to show for it. Everybody else is a new
    // program with a new name and nothing to their name yet, so a champion
    // is the only thing in the arena that accumulates -- and the only one
    // with anything to lose.
    var champ = -1, best = -1;
    for (var c = 0; c < fs.length; c++) {
      if (!alive(c)) continue;
      var pts = tally(fs[c]);
      if (pts > best) { best = pts; champ = c; }
    }
    if (champ >= 0) fs[champ].stats.rounds++;

    var taken = champ >= 0 ? [fs[champ].name] : [];
    for (var n = 0; n < fs.length; n++) {
      fs[n].champion = (n === champ);
      if (n === champ) continue;
      fs[n].name = freshName(taken);               // a new program on that platform
      fs[n].stats = blankStats();
      fs[n].foe = -1;
      fs[n].lastAim = -1; fs[n].lastGuard = -1;
    }

    for (var g = 0; g < pads.length; g++) restoreRings(g);
    for (var i = 0; i < fs.length; i++) {
      var f = fs[i];
      f.pad = f.home;
      f.ring = 0; f.ang = 0; f.pos = [pads[f.home].cx, pads[f.home].cz];
      f.move = null; f.clingRing = -1; f.willClimb = false; f.foe = -1;
      f.blockTarget = 0; f.block = 0;
      setMode(i, "rez");
      f.yOff = 0; f.alpha = 0;
      play(i, "idle");
      ds[i] = { state: "back", pos: [0, 0, 0], trail: [], flight: null };
    }
    // Anything still queued belongs to the round that just ended.
    queue = []; wallQueue = []; chains = 0;
    banner = "";
    for (var j = 0; j < teamSize; j++) afterWall(1.2 + j * 0.35, startChain);
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(realDt) {
    var dt = realDt * pace;
    now += dt;
    wall += realDt;
    var due = queue.filter(function (e) { return e.at <= now; });
    if (due.length) {
      queue = queue.filter(function (e) { return e.at > now; });
      due.forEach(function (e) { e.fn(); });
    }
    var dueWall = wallQueue.filter(function (e) { return e.at <= wall; });
    if (dueWall.length) {
      wallQueue = wallQueue.filter(function (e) { return e.at > wall; });
      dueWall.forEach(function (e) { e.fn(); });
    }
    // Rings that have finished rising are simply up again, and one that has
    // been gone a while starts back on its own.
    pads.forEach(function (pd) {
      var rs = pd.rings;
      rs.forEach(function (r, k) {
        if (r.s === "rising" && wall - r.t > 0.9) rs[k] = { s: "up" };
        else if (r.s === "falling" && wall - r.t > ringBack) rs[k] = { s: "rising", t: wall };
      });
    });
    // Keep as many exchanges going as the match should have.
    if (wall - lastChainCheck > 1.2) {
      lastChainCheck = wall;
      // As the round wears on there are fewer fighters to carry exchanges,
      // so ask for no more than the thinner side can still put up.
      var want = Math.min(teamSize, liveCount(0), liveCount(1));
      // `chains` is a count of exchanges believed to be running, and a bug
      // that loses one without saying so leaves the arena quiet for good. If
      // nothing has been thrown for a while and both sides still have
      // fighters, stop believing the count and start again.
      if (want > 0 && wall - lastThrow > 7) chains = 0;
      while (chains < want && startChain()) { /* fill every slot */ }
    }
    aimCamera(realDt);

    dn = 0;                                    // start this frame's draw list

    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i];
      seg(-1000, project(ln[0]), project(ln[1]), ln[4], ln[3], ln[2]);
    }

    // Rings: project each edge circle once, then lay its segments.
    for (var ci = 0; ci < ringCircles.length; ci++) {
      var cc = ringCircles[ci], look = ringLook(cc[0], cc[1]), pts = [];
      var cxw = pads[cc[0]].cx, czw = pads[cc[0]].cz;
      if (look[1] <= 0.01) continue;
      for (var a = 0; a <= ringSegs; a++) {
        var ang = 2 * Math.PI * a / ringSegs;
        pts.push(project([cxw + Math.cos(ang) * cc[2], look[0], czw + Math.sin(ang) * cc[2]]));
      }
      var outer = cc[2] === ringRadii[cc[1]][1];
      var col = pads[cc[0]].team === 0 ? program : sentinel;
      for (var sg = 0; sg < ringSegs; sg++) {
        seg(1000 - (pts[sg][2] + pts[sg + 1][2]) * 10 - 1, pts[sg], pts[sg + 1],
            outer ? 2 : 1.2, col, look[1] * (outer ? 0.95 : 0.55));
      }
    }

    fs.forEach(function (_f, p) {
      var local = localPose(p, dt, realDt);
      updateMode(p);
      var f = fs[p];
      if (f.mode === "gone" || f.mode === "derez") return;
      var col = f.team === 0 ? program : sentinel, alpha = f.alpha;
      var S = [];
      for (var j = 0; j < 20; j++) S.push(project(toWorld(p, local, j)));
      for (var k = 0; k < limbs.length; k++) {
        var lb = limbs[k], a1 = S[lb[0]], b1 = S[lb[1]], depth = (a1[2] + b1[2]) / 2;
        limb(1000 - depth * 20, a1, b1, Math.max(2, lb[2] * cam.F / depth), col, alpha);
      }
      var hc = project(lerp3(toWorld(p, local, 10), toWorld(p, local, 11), 0.55));
      var hs = 0.24 * cam.F / hc[2];
      var hd = put("head", 1000 - hc[2] * 20 + 1);
      hd.x = hc[0] - hs / 2; hd.y = hc[1] - hs * 0.56;
      hd.w = hs; hd.h = hs * 1.12; hd.c = col; hd.o = alpha;
      // The visor sits on whichever side the fighter faces, as seen on screen.
      var front = project(ahead(p, toWorld(p, local, 11), 0.3));
      hd.vx = front[0] > hc[0] ? hs * 0.45 : hs * 0.05;

      // The name, over the head, with a mark on the one that came through
      // the last round.
      var label = f.champion ? "^" + f.name : f.name;
      nameAt(label, hc[0], hc[1] - hs * 1.75, hs * 0.62,
             f.champion ? (f.team === 0 ? programHi : sentinelHi) : col,
             alpha * (f.champion ? 1 : 0.8), 1000 - hc[2] * 20 + 2);
    });

    // Discs and their trails.
    fs.forEach(function (_d, p) {
      var d = ds[p], f = fs[p];
      if (d.state === "flight") {
        var fl = d.flight, t = Math.min(1, (now - fl.t0) / fl.dur);
        d.pos = flightPoint(fl, t);
        d.trail = [d.pos].concat(d.trail).slice(0, trailLen + 1);
        if (t >= 1) { d.flight = null; d.state = "hand"; fl.done(); }
      } else {
        d.pos = d.state === "hand" ? handWorld(p) : d.state === "shield" ? shieldWorld(p) : backWorld(p);
        d.trail = d.trail.slice(0, Math.max(0, d.trail.length - 3));     // the streak fades after a catch
      }
      if (f.mode === "gone" || f.mode === "derez") return;
      var alpha = d.state === "flight" ? 1 : f.alpha;
      var s = project(d.pos), r = 0.3 * cam.F / s[2], view = norm(sub(d.pos, cam.p));
      var dw, dh;
      if (d.state === "flight") {
        // Flying flat: seen more or less edge-on from the side.
        var squash = Math.max(0.25, Math.abs(view[1]) + 0.15);
        dw = r; dh = r * squash;
      } else if (d.state === "shield") {
        // Held upright facing the enemy: narrow as the camera sees it.
        dw = r * Math.max(0.3, Math.abs(view[0])); dh = r * 1.05;
      } else {
        dw = r; dh = r;
      }
      var di = put("disc", 1000 - s[2] * 20 + (d.state === "back" ? -3 : 3));
      di.x = s[0]; di.y = s[1]; di.w = dw; di.h = dh;
      di.c = f.team === 0 ? program : sentinel;
      di.hot = f.team === 0 ? programHi : sentinelHi;
      di.o = alpha;
      // The trail: segments between successive positions, thinning out.
      var tp = d.trail.map(project);
      for (var g = 0; g + 1 < tp.length && g < trailLen; g++) {
        var tw = Math.max(1, 0.06 * cam.F / tp[g][2] * (1 - g / trailLen));
        seg(1000 - tp[g][2] * 20 - 1, tp[g], tp[g + 1], tw,
            f.team === 0 ? programHi : sentinelHi, 0.85 * (1 - g / trailLen), "round");
      }
    });

    if (pieces.length) stepPieces(realDt);

    for (var n = 0; n < sparkData.length; n++) {
      var sd = sparkData[n];
      if (!sd) continue;
      var age = wall - sd.born;
      if (age >= 0.5) continue;
      var ps = project(sd.w);
      var sp = put("spark", 1500);
      sp.x = ps[0]; sp.y = ps[1];
      sp.size = 0.3 * cam.F / ps[2];
      sp.age = age; sp.c = sd.col;
    }

    ctx.fillStyle = ink;
    ctx.fillRect(0, 0, W, H);
    paint();
  }

  // ── Bootstrap ─────────────────────────────────────────────────────────
  var canvas, last = 0, raf = 0, gen = 0, paused = false, lastChainCheck = 0;

  function resize() {
    var dpr = Math.min(2, window.devicePixelRatio || 1);
    W = canvas.clientWidth;
    H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  // One loop per generation, so a resume can always start a fresh one
  // without ever ending up with two running at once.
  function start() {
    var mine = ++gen;
    last = 0;
    raf = requestAnimationFrame(function loop(ts) {
      if (paused || mine !== gen) return;
      if (!last) last = ts;
      var dt = Math.min(0.05, (ts - last) / 1000);
      last = ts;
      step(dt);
      raf = requestAnimationFrame(loop);
    });
  }

  function setPaused(p) {
    paused = !!p;
    if (!paused) start();
  }

  window.DiscWars = {
    themes: THEMES,
    setTheme: function (key) { if (THEMES[key]) applyPalette(THEMES[key]); },
    // An ENCOM palette straight out of a theme's encom.json, as the desktop
    // hands it over. Anything it leaves out falls back to TRON Legacy, so a
    // partial palette still draws.
    setPalette: function (p) {
      var base = THEMES["tron-legacy"];
      applyPalette({
        name: p.brand || base.name,
        sideA: p.sideA || base.sideA, sideAHi: p.sideAHi || base.sideAHi,
        sideB: p.sideB || base.sideB, sideBHi: p.sideBHi || base.sideBHi,
        accent: p.accent || base.accent, accentHi: p.accentHi || base.accentHi,
        ink: p.ink || base.ink
      });
    },
    setPaused: setPaused,
    // Listen to the fight: ("throw"|"block", { team, aim }).
    on: function (fn) { if (typeof fn === "function") listeners.push(fn); },
    // 1 for the duel, 2 or 3 for a team match. Restarts the fight.
    setTeams: function (n) {
      buildMatch(n);
      for (var i = 0; i < teamSize; i++) after(0.8 + i * 0.35, startChain);
    },
    get teams() { return teamSize; },
    // What the scoreboard needs: the scoreline, who is still standing, and
    // the word on a round just won. Read, never held on to -- the fighters
    // are rebuilt whenever the match size changes.
    state: function () {
      return {
        teams: teamSize,
        score: score.slice(),
        banner: banner,
        sides: SIDE_NAME.slice(),
        fighters: fs.map(function (f, i) {
          return { team: f.team, alive: alive(i), name: f.name,
                   champion: f.champion, points: tally(f), stats: f.stats };
        }),
        // What the two policies have come to, for the readout. Null when
        // learn.js is not loaded and the fight is being played blind.
        learning: brains && brains.map(function (b) {
          return { throws: b.throws, through: b.recent,
                   aims: b.aimMix.slice(), guards: b.guardMix.slice() };
        })
      };
    },
    init: function (el, n) {
      canvas = el;
      ctx = canvas.getContext("2d");
      applyPalette(THEMES["tron-legacy"]);
      buildMatch(n || 1);
      resize();
      window.addEventListener("resize", resize);
      // A hidden tab stops getting animation frames; start a fresh loop on
      // the way back rather than assuming the old one survived.
      document.addEventListener("visibilitychange", function () {
        if (!document.hidden && !paused) start();
      });
      for (var i = 0; i < teamSize; i++) after(0.8 + i * 0.35, startChain);
      start();
    }
  };
})();
