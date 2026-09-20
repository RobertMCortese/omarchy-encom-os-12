import QtQuick

// ENCOM OS-12 lock screen, 1982 theme: the transfer.
//
// The ride from the real world into the game world, in four movements, built
// the way the first film's graphics were: wireframe, drawn in perspective,
// nothing shaded and nothing textured.
//
//   1  THE KALEIDOSCOPE  Flat, as it is in the film: a field of short lines
//      reflected across a grid of mirrors, drifting so the tiling folds into
//      a new pattern. It works through a sequence of colours as it goes.
//   2  THE TUNNEL  Real 3D from here on. Rings of a polygon strung along the
//      axis, each turned a little further than the last, with the camera
//      flying down the middle of them.
//   3  THE FIELD  The way out of the tunnel is a port of nested squares
//      that flies at the camera and opens onto a board: traces running away
//      in two directions, rows of dots, patches of dot matrix, and beads of
//      light travelling along the tracks, with the camera panning and
//      rolling as it crosses.
//   4  THE PLANET  A wireframe sphere with slabs standing on its surface and
//      beams cutting across it, the camera falling towards the limb. Only the
//      near face is drawn — the back of the sphere is culled away.
//   5  THE LANDING  Down onto the grid: a lit plane running to the horizon,
//      slabs standing on it, the camera settling as it comes in.
//
// The 3D is hand-rolled — a camera basis and a perspective divide, with
// near-plane clipping — because there is no Qt Quick 3D here and the flat
// vector look wants nothing more. Every edge is one plain QtQuick rectangle,
// taken from a fixed pool so a frame costs the same whatever is on screen,
// and the scene runs at 30 fps, as the sequence it comes from did at 24.
//
// It is a recreation, not a copy: the geometry is generated, not traced, and
// it is drawn in the current theme's colours, which the lock plugin hands
// over. Nothing here touches the password.
Item {
  id: field

  property var encomPalette: ({})
  readonly property color accent: encomPalette.accent || "#b06cff"
  readonly property color accentHi: encomPalette.accentHi || "#e4cdff"
  readonly property color contrast: encomPalette.contrast || "#ffc300"
  readonly property color contrastHi: encomPalette.contrastHi || "#ffdf78"
  readonly property color ink: encomPalette.ink || "#03030a"
  // The lock plugin reads these for the password field's frame.
  readonly property color line: accent
  readonly property color lineHi: accentHi

  property real now: 0
  property bool running: true

  readonly property int dimCount: 900
  readonly property int hotCount: 430
  readonly property int warmCount: 150

  // The vanishing point sits above the password field, not behind it.
  readonly property real cx: width / 2
  readonly property real cy: height * 0.38
  readonly property real reach: Math.min(width * 0.6, height * 0.92)

  readonly property real cycle: 56          // one full ride, in seconds

  Rectangle { anchors.fill: parent; color: field.ink; z: -100 }

  Repeater {
    id: dim
    model: field.dimCount
    Rectangle { color: field.tint; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: hot
    model: field.hotCount
    Rectangle { color: field.accentHi; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: warm
    model: field.warmCount
    Rectangle { color: field.contrast; transformOrigin: Item.Left; antialiasing: true }
  }
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height / 2 + 58
    z: 50
    text: "ENCOM OS-12  ·  SESSION LOCKED"
    color: field.accent
    opacity: 0.7
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 11
    font.letterSpacing: 4
  }

  // ── Drawing ───────────────────────────────────────────────────────────
  property int di: 0
  property int hi: 0
  property int wi: 0
  property int diWas: 0
  property int hiWas: 0
  property int wiWas: 0

  function put(item, x0, y0, x1, y1, thick, alpha) {
    var dx = x1 - x0, dy = y1 - y0
    item.x = x0
    item.y = y0 - thick / 2
    item.width = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    item.height = thick
    item.rotation = Math.atan2(dy, dx) * 180 / Math.PI
    item.opacity = alpha
  }

  // Segments wholly off one side of the screen cost as much as visible ones,
  // so they are dropped here rather than drawn into the void.
  function off(x0, y0, x1, y1) {
    var m = width
    return (x0 < -m && x1 < -m) || (x0 > width + m && x1 > width + m)
        || (y0 < -m && y1 < -m) || (y0 > height + m && y1 > height + m)
  }

  function draw(x0, y0, x1, y1, thick, alpha) {
    if (alpha > 0.005 && di < dimCount && !off(x0, y0, x1, y1))
      put(dim.itemAt(di++), x0, y0, x1, y1, thick, alpha)
  }

  function glow(x0, y0, x1, y1, thick, alpha) {
    if (alpha > 0.005 && hi < hotCount && !off(x0, y0, x1, y1))
      put(hot.itemAt(hi++), x0, y0, x1, y1, thick, alpha)
  }

  function beam(x0, y0, x1, y1, thick, alpha) {
    if (alpha > 0.005 && wi < warmCount && !off(x0, y0, x1, y1))
      put(warm.itemAt(wi++), x0, y0, x1, y1, thick, alpha)
  }

  // A repeatable wobble: one number per (seed, time), no randomness needed.
  function wob(seed, t) {
    return Math.sin(t * (0.23 + seed * 0.029) + seed * 2.39)
         * Math.cos(t * (0.13 + seed * 0.017) + seed * 1.11)
  }

  function ease(x) { return x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x) }

  // A movement's weight: up over `fade`, hold, then down again.
  function weigh(u, from, to, fade) {
    if (u < from - fade || u > to + fade) return 0
    return ease(Math.min((u - (from - fade)) / fade, ((to + fade) - u) / fade))
  }

  // ── The camera ────────────────────────────────────────────────────────
  // A plain JS object, not QML properties: it is read a few thousand times a
  // frame and property reads are the expensive part of this scene.
  readonly property var cam: ({
    px: 0, py: 0, pz: 0,
    fx: 0, fy: 0, fz: 1,
    rx: 1, ry: 0, rz: 0,
    ux: 0, uy: 1, uz: 0,
    f: 800
  })
  readonly property var sc: ({ x0: 0, y0: 0, x1: 0, y1: 0 })

  function look(px, py, pz, tx, ty, tz, fov, roll) {
    var c = cam
    var fx = tx - px, fy = ty - py, fz = tz - pz
    var L = Math.sqrt(fx * fx + fy * fy + fz * fz) || 1
    fx /= L; fy /= L; fz /= L
    // right = forward × world up
    var rx = fy * 0 - fz * 1, ry = fz * 0 - fx * 0, rz = fx * 1 - fy * 0
    var rl = Math.sqrt(rx * rx + ry * ry + rz * rz)
    if (rl < 1e-6) { rx = 1; ry = 0; rz = 0; rl = 1 }
    rx /= rl; ry /= rl; rz /= rl
    // up = right × forward
    c.px = px; c.py = py; c.pz = pz
    c.fx = fx; c.fy = fy; c.fz = fz
    c.rx = rx; c.ry = ry; c.rz = rz
    var ux = ry * fz - rz * fy
    var uy = rz * fx - rx * fz
    var uz = rx * fy - ry * fx
    if (roll) {
      // Turn right and up about the line of sight: the bank.
      var cr = Math.cos(roll), sr = Math.sin(roll)
      c.rx = rx * cr + ux * sr; c.ry = ry * cr + uy * sr; c.rz = rz * cr + uz * sr
      c.ux = ux * cr - rx * sr; c.uy = uy * cr - ry * sr; c.uz = uz * cr - rz * sr
    } else {
      c.ux = ux; c.uy = uy; c.uz = uz
    }
    c.f = (height / 2) / Math.tan(fov / 2 * Math.PI / 180)
  }

  // Projects a world point into the scratch slot (0 = first end, 1 = second)
  // and returns how far in front of the camera it is.
  function proj(x, y, z, slot) {
    var c = cam, s = sc
    var dx = x - c.px, dy = y - c.py, dz = z - c.pz
    var d = dx * c.fx + dy * c.fy + dz * c.fz
    if (d > 0.0001) {
      var k = c.f / d
      if (slot === 0) {
        s.x0 = cx + (dx * c.rx + dy * c.ry + dz * c.rz) * k
        s.y0 = cy - (dx * c.ux + dy * c.uy + dz * c.uz) * k
      } else {
        s.x1 = cx + (dx * c.rx + dy * c.ry + dz * c.rz) * k
        s.y1 = cy - (dx * c.ux + dy * c.uy + dz * c.uz) * k
      }
    }
    return d
  }

  // One wireframe edge, clipped against the near plane.
  function edge(ax, ay, az, bx, by, bz, thick, alpha, pool) {
    if (alpha <= 0.005) return
    var near = 0.2
    var d0 = proj(ax, ay, az, 0)
    var d1 = proj(bx, by, bz, 1)
    if (d0 < near && d1 < near) return
    if (d0 < near) {
      var t = (near - d0) / (d1 - d0)
      proj(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, 0)
    } else if (d1 < near) {
      var t2 = (near - d1) / (d0 - d1)
      proj(bx + (ax - bx) * t2, by + (ay - by) * t2, bz + (az - bz) * t2, 1)
    }
    var s = sc
    if (pool === 1) glow(s.x0, s.y0, s.x1, s.y1, thick, alpha)
    else if (pool === 2) beam(s.x0, s.y0, s.x1, s.y1, thick, alpha)
    else draw(s.x0, s.y0, s.x1, s.y1, thick, alpha)
  }

  // ── 1. The kaleidoscope (flat) ────────────────────────────────────────
  // It works through a sequence of colours rather than holding the theme's,
  // the way the film's does — that one passes from a pale blue-green through
  // steel and indigo to violet. The blue here is measured off it.
  readonly property var tints: [
    [0.21, 0.84, 0.82],   // teal
    [0.97, 0.20, 0.24],   // red
    [0.85, 0.77, 1.00],   // pale violet
    [0.60, 0.30, 1.00],   // purple
    [0.23, 0.44, 0.96]    // blue
  ]
  // The pool's colour is one property standing for nine hundred items, so it
  // moves a few times a second rather than every frame.
  property color tint: accent
  property int tintTick: -1

  function cycleTint(t, u) {
    var tick = Math.floor(t * 6)
    if (tick === tintTick) return
    tintTick = tick
    var n = tints.length
    var f = u * n
    var i = Math.floor(f) % n
    var a = tints[i], b = tints[(i + 1) % n]
    var k = ease(f - Math.floor(f))
    tint = Qt.rgba(a[0] + (b[0] - a[0]) * k,
                   a[1] + (b[1] - a[1]) * k,
                   a[2] + (b[2] - a[2]) * k, 1)
  }

  readonly property int motif: 76
  property var ku0: []
  property var kv0: []
  property var ku1: []
  property var kv1: []
  property var kax: []
  property var kay: []
  property var kbx: []
  property var kby: []
  property var kal: []

  function kaleidoscope(t, w) {
    var cw = width / 2.6, ch = height / 1.85
    var arm = 0.022
    for (var m = 0; m < motif; m++) {
      var s = m * 1.7
      var u0 = 0.5 + 0.46 * wob(s, t)
      var v0 = 0.5 + 0.46 * wob(s + 41, t)
      var ang = wob(s + 83, t * 0.6) * Math.PI
      var len = 0.09 + 0.15 * Math.abs(wob(s + 17, t * 0.5))
      ku0[m] = u0
      kv0[m] = v0
      ku1[m] = u0 + Math.cos(ang) * len
      kv1[m] = v0 + Math.sin(ang) * len * 1.4
      kax[m] = Math.cos(ang + 2.5) * arm
      kay[m] = Math.sin(ang + 2.5) * arm * 1.4
      kbx[m] = Math.cos(ang - 2.5) * arm
      kby[m] = Math.sin(ang - 2.5) * arm * 1.4
      kal[m] = 0.55 + 0.45 * Math.abs(wob(s + 5, t))
    }
    for (var tx = -2; tx <= 2; tx++) {
      var ox = cx + tx * cw
      if (ox > width || ox + cw < 0) continue
      var flipX = ((tx % 2) + 2) % 2
      for (var ty = -2; ty <= 2; ty++) {
        var oy = cy + ty * ch
        if (oy > height || oy + ch < 0) continue
        var flipY = ((ty % 2) + 2) % 2
        var sx = flipX ? -1 : 1, sy = flipY ? -1 : 1
        var bx = flipX ? ox + cw : ox, by = flipY ? oy + ch : oy
        for (var n = 0; n < motif; n++) {
          var x0 = bx + sx * ku0[n] * cw, y0 = by + sy * kv0[n] * ch
          var x1 = bx + sx * ku1[n] * cw, y1 = by + sy * kv1[n] * ch
          draw(x0, y0, x1, y1, n % 4 ? 1.1 : 1.6, w * kal[n])
          if (n % 5 === 0) {
            draw(x1, y1, x1 + sx * kax[n] * cw, y1 + sy * kay[n] * ch, 1.1, w * 0.55)
            draw(x1, y1, x1 + sx * kbx[n] * cw, y1 + sy * kby[n] * ch, 1.1, w * 0.55)
          }
        }
      }
    }
  }

  // ── 2. The tunnel ─────────────────────────────────────────────────────
  // Rings threaded along the axis, each turned further than the last. The
  // camera flies down the middle; rings behind it are recycled ahead, so the
  // flight never ends.
  readonly property int tunnelRings: 22
  readonly property int tunnelSides: 13
  readonly property real ringGap: 2.4

  // Where the tunnel's middle sits at a given distance along it: a long
  // lazy curve, so the flight leans left and right instead of running dead
  // straight.
  function bendX(z) { return 4.2 * Math.sin(z * 0.04) + 1.5 * Math.sin(z * 0.017 + 2) }
  function bendY(z) { return 1.6 * Math.sin(z * 0.028 + 1.1) }

  property var tvx: []
  property var tvy: []
  property var twx: []
  property var twy: []

  function tunnel(t, w) {
    var fly = t * 5.5
    // Fly along the curve, looking up the line of it, banking into the turn.
    var lead = 11
    var bank = (bendX(fly + 7) - bendX(fly - 7)) * -0.075
    look(bendX(fly), bendY(fly), fly,
         bendX(fly + lead), bendY(fly + lead), fly + lead, 62, bank)
    var first = Math.ceil(fly / ringGap)
    for (var k = 0; k < tunnelRings; k++) {
      var z = (first + k) * ringGap
      var ahead = z - fly
      var r = 3.4 + 0.5 * Math.sin(z * 0.12)
      var rot = z * 0.16
      var fade = w * ease(ahead / 3) * Math.max(0, 1 - ahead / (tunnelRings * ringGap * 0.85))
      if (fade <= 0.005) continue
      var mx = bendX(z), my = bendY(z)
      for (var s = 0; s < tunnelSides; s++) {
        var a = rot + s * 2 * Math.PI / tunnelSides
        tvx[s] = mx + Math.cos(a) * r
        tvy[s] = my + Math.sin(a) * r
      }
      var bright = ahead > tunnelRings * ringGap * 0.6
      for (var e = 0; e < tunnelSides; e++) {
        var n = (e + 1) % tunnelSides
        edge(tvx[e], tvy[e], z, tvx[n], tvy[n], z, 1.5, fade, bright ? 1 : 0)
        // Back to the ring behind: the long lines running down the tunnel.
        if (k > 0)
          edge(tvx[e], tvy[e], z, twx[e], twy[e], z - ringGap, 1.2, fade * 0.55, 0)
      }
      for (var q = 0; q < tunnelSides; q++) { twx[q] = tvx[q]; twy[q] = tvy[q] }
    }
    // Chords that skip three rings and half the circumference: the long
    // lines cutting big triangles across the mouth of the tunnel.
    for (var k2 = 3; k2 < tunnelRings - 1; k2 += 2) {
      var za = (first + k2) * ringGap, zb2 = (first + k2 - 3) * ringGap
      var ra = 3.4 + 0.5 * Math.sin(za * 0.12), rb = 3.4 + 0.5 * Math.sin(zb2 * 0.12)
      var rota = za * 0.16, rotb = zb2 * 0.16
      var fadec = w * ease((za - fly) / 4) * Math.max(0, 1 - (za - fly) / (tunnelRings * ringGap))
      for (var e2 = 0; e2 < tunnelSides; e2 += 2) {
        var aa = rota + e2 * 2 * Math.PI / tunnelSides
        var ab = rotb + (e2 + 5) * 2 * Math.PI / tunnelSides
        edge(bendX(za) + Math.cos(aa) * ra, bendY(za) + Math.sin(aa) * ra, za,
             bendX(zb2) + Math.cos(ab) * rb, bendY(zb2) + Math.sin(ab) * rb, zb2,
             1.2, fadec * 0.6, 0)
      }
    }
    // The way out: square frames nested at the end of the tunnel.
    var gz = fly + tunnelRings * ringGap * 0.98
    var gx = bendX(gz), gy = bendY(gz)
    for (var f2 = 0; f2 < 3; f2++) {
      var hs = 2.6 - f2 * 0.75
      edge(gx - hs, gy - hs, gz, gx + hs, gy - hs, gz, 1.6, w * 0.8, 1)
      edge(gx + hs, gy - hs, gz, gx + hs, gy + hs, gz, 1.6, w * 0.8, 1)
      edge(gx + hs, gy + hs, gz, gx - hs, gy + hs, gz, 1.6, w * 0.8, 1)
      edge(gx - hs, gy + hs, gz, gx - hs, gy - hs, gz, 1.6, w * 0.8, 1)
    }
    plates(t, w, fly)
  }

  // Plates: flat panels cut to tetromino shapes and ruled into squares,
  // tumbling past the camera as it flies down the tunnel. In the film these
  // drift through in a colour of their own, so they take the theme's second
  // colour and its bright one, never the tunnel's.
  readonly property var tetro: [
    [[0, 0], [0, 1], [0, 2], [1, 2]],
    [[0, 0], [1, 0], [1, 1], [2, 1]],
    [[0, 0], [1, 0], [2, 0], [1, 1]],
    [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[0, 0], [0, 1], [0, 2], [0, 3]],
    [[0, 1], [1, 1], [1, 0], [2, 0]]
  ]
  readonly property int plateCount: 7
  readonly property int plateRule: 3          // grid lines ruled across a cell

  function plates(t, w, flyZ) {
    var run = 46                              // how far a plate travels
    for (var p = 0; p < plateCount; p++) {
      var along = (t * 10 + p * 6.6) % run
      var zc = flyZ + 38 - along              // from far ahead to behind us
      var cell = 1.05 + 0.5 * Math.abs(wob(p * 7, t * 0.2))
      // Off to one side of the axis, so it sweeps past rather than through.
      var swing = p * 1.9 + t * 0.14
      var rad = 2.2 + 1.9 * Math.sin(p * 2.3 + t * 0.21)
      var ox = bendX(zc) + Math.cos(swing) * rad
      var oy = bendY(zc) + Math.sin(swing) * rad
      // The plane it lies in, tumbling slowly.
      var th = t * 0.3 + p * 1.4, ph = t * 0.19 + p * 2.1
      var st = Math.sin(th), ct = Math.cos(th), sp = Math.sin(ph), cp = Math.cos(ph)
      var nx = st * cp, ny = st * sp, nz = ct
      var ux = -sp, uy = cp, uz = 0
      var vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux
      var ahead = zc - flyZ
      var fade = w * ease((ahead + 6) / 8) * Math.max(0, 1 - ahead / 34)
      if (fade <= 0.006) continue
      var pool = p % 2 ? 2 : 1
      var shape = tetro[p % tetro.length]
      for (var q = 0; q < shape.length; q++) {
        var gx = (shape[q][0] - 1) * cell, gy = (shape[q][1] - 1.5) * cell
        // The cell's four sides, then the lines ruled across it.
        for (var r = 0; r <= plateRule + 1; r++) {
          var f = r / (plateRule + 1)
          var edgeLine = (r === 0 || r === plateRule + 1)
          var thick = edgeLine ? 1.5 : 1
          var a = fade * (edgeLine ? 1 : 0.5)
          // across
          edge(ox + ux * gx + vx * (gy + f * cell) + nx * 0,
               oy + uy * gx + vy * (gy + f * cell),
               zc + uz * gx + vz * (gy + f * cell),
               ox + ux * (gx + cell) + vx * (gy + f * cell),
               oy + uy * (gx + cell) + vy * (gy + f * cell),
               zc + uz * (gx + cell) + vz * (gy + f * cell), thick, a, pool)
          // and down
          edge(ox + ux * (gx + f * cell) + vx * gy,
               oy + uy * (gx + f * cell) + vy * gy,
               zc + uz * (gx + f * cell) + vz * gy,
               ox + ux * (gx + f * cell) + vx * (gy + cell),
               oy + uy * (gx + f * cell) + vy * (gy + cell),
               zc + uz * (gx + f * cell) + vz * (gy + cell), thick, a, pool)
        }
      }
    }
  }

  // ── 3. The field ──────────────────────────────────────────────────────
  // A board laid out in tiles. Which features a tile carries is decided by
  // its coordinates, not by chance, so the board is the same every time the
  // camera passes that spot and it can run for ever without being stored.
  readonly property real tile: 4.6

  function hash(a, b) {
    var v = Math.sin(a * 127.1 + b * 311.7) * 43758.5453
    return v - Math.floor(v)
  }

  // A dot on the board: projected, then drawn as a little square that keeps
  // its size in the world rather than on the screen.
  function dot(x, y, z, size, alpha, pool) {
    var d = proj(x, y, z, 0)
    if (d < 0.35 || alpha <= 0.006) return
    var ss = Math.min(11, Math.max(1.1, size * cam.f / d))
    var sx = sc.x0, sy = sc.y0
    if (pool === 1) glow(sx - ss / 2, sy, sx + ss / 2, sy, ss, alpha)
    else if (pool === 2) beam(sx - ss / 2, sy, sx + ss / 2, sy, ss, alpha)
    else draw(sx - ss / 2, sy, sx + ss / 2, sy, ss, alpha)
  }

  function board(t, w, fly, span) {
    var i0 = Math.floor((fly - 3 * tile) / tile)
    for (var i = 0; i < 18; i++) {
      var zc = (i0 + i) * tile
      var near = zc - fly
      var fade = w * ease((near + 13) / 6) * Math.max(0, 1 - near / (15 * tile))
      if (fade <= 0.006) continue
      for (var j = -span; j <= span; j++) {
        var xc = j * tile
        var h = hash(i0 + i, j)
        var h2 = hash(j, i0 + i)
        var h3 = hash(i0 + i + 31, j - 17)
        // A trace or two through every tile, so the board never thins out.
        var base = (hash(i0 + i + 7, j + 13) - 0.5) * tile * 0.85
        if (h3 < 0.5)
          edge(xc + base, 0, zc, xc + base, 0, zc + tile, 1.2, fade * 0.7, 0)
        else
          edge(xc, 0, zc + base, xc + tile, 0, zc + base, 1.2, fade * 0.7, 0)
        if (h < 0.34) {
          // Traces: long runs, some along the board, some across it.
          var runs = 2 + Math.floor(h2 * 3)
          for (var r = 0; r < runs; r++) {
            var off = (hash(i0 + i + r, j * 3) - 0.5) * tile * 0.8
            var len = tile * (0.45 + hash(j + r, i0 + i) * 0.5)
            var pool = h3 < 0.25 ? 1 : 0
            if (h2 < 0.5)
              edge(xc + off, 0, zc, xc + off, 0, zc + len, 1.3, fade * 0.9, pool)
            else
              edge(xc, 0, zc + off, xc + len, 0, zc + off, 1.3, fade * 0.9, pool)
          }
        } else if (h < 0.62) {
          // A row of dots, evenly spaced, running one way or the other.
          var n = 9 + Math.floor(h3 * 7)
          var gap = tile / n
          var lane = (h2 - 0.5) * tile * 0.7
          for (var k = 0; k < n; k++) {
            if (h2 < 0.5) dot(xc + lane, 0, zc + k * gap, 0.07, fade * 0.8, 0)
            else dot(xc + k * gap, 0, zc + lane, 0.07, fade * 0.8, 0)
          }
        } else if (h < 0.82) {
          // A patch of dot matrix: the fragments of grid on the board.
          var cols = 4 + Math.floor(h2 * 4), rows = 3 + Math.floor(h3 * 4)
          var step = tile * 0.12
          var bxp = xc - cols * step / 2, bzp = zc - rows * step / 2
          for (var cc = 0; cc < cols; cc++)
            for (var rr = 0; rr < rows; rr++)
              dot(bxp + cc * step, 0, bzp + rr * step, 0.055,
                  fade * (0.5 + 0.45 * hash(cc + i, rr + j)), h3 < 0.4 ? 1 : 0)
        } else {
          // Vias: a few lone warm dots.
          for (var v = 0; v < 4; v++)
            dot(xc + (hash(v + i, j) - 0.5) * tile, 0, zc + (hash(j, v + i) - 0.5) * tile,
                0.1, fade, 2)
        }
        // Beads of light, running along a track through the tile.
        if (h2 > 0.78) {
          var beads = 7
          var travel = ((t * 0.45 + h) % 1) * tile * 2 - tile * 0.5
          for (var b2 = 0; b2 < beads; b2++) {
            var slide = travel - b2 * 0.26
            var lit = fade * (1 - b2 / beads)
            if (h3 < 0.5) dot(xc + (h - 0.5) * tile, 0.02, zc + slide, 0.11, lit, 1)
            else dot(xc + slide, 0.02, zc + (h - 0.5) * tile, 0.11, lit, 1)
          }
        }
      }
    }
  }

  function fieldRide(t, w, age) {
    var fly = t * 6.5
    // Panning and rolling as it crosses the board.
    var yaw = Math.sin(t * 0.16) * 0.5
    var roll = Math.sin(t * 0.1) * 0.28
    var hgt = 4.2 + 1.1 * Math.sin(t * 0.13)
    var side = Math.sin(t * 0.08) * 4
    // Aimed down at the board, so it fills the frame rather than running off
    // as a band across the corner.
    look(side, hgt, fly,
         side + Math.sin(yaw) * 4.5, 0, fly + Math.cos(yaw) * 4.5, 66, roll)
    board(t, w, fly, 9)
    // The port: nested squares that fly at the camera and open out.
    if (age < 3.4) {
      var app = 1 - age / 3.4
      for (var n = 0; n < 4; n++) {
        var pz = fly + 0.6 + app * 30 + n * 1.6
        var hs = 2.4 + n * 0.85
        var pa = w * ease(app * 2.2) * (1 - n * 0.15)
        edge(side - hs, hgt - hs, pz, side + hs, hgt - hs, pz, 1.7, pa, 1)
        edge(side + hs, hgt - hs, pz, side + hs, hgt + hs, pz, 1.7, pa, 1)
        edge(side + hs, hgt + hs, pz, side - hs, hgt + hs, pz, 1.7, pa, 1)
        edge(side - hs, hgt + hs, pz, side - hs, hgt - hs, pz, 1.7, pa, 1)
      }
    }
  }

  // ── 4. The planet ─────────────────────────────────────────────────────
  // A wireframe sphere: rings of latitude, meridians of longitude, and slabs
  // standing on the surface. Only the near face is drawn.
  readonly property int lat: 13
  readonly property int lon: 28

  function planet(t, w) {
    var u = (t % cycle) / cycle
    // Falling towards the limb, turning as it comes.
    var swing = t * 0.11
    // Close in on the limb, so the sphere runs off the bottom of the frame
    // and its edge cuts across it, the way the film holds the shot.
    var dist = 2.15 - 0.35 * Math.sin(t * 0.07)
    var camx = Math.cos(swing) * dist, camz = Math.sin(swing) * dist
    var camy = 0.95 + 0.25 * Math.sin(t * 0.09)
    look(camx, camy, camz, 0, -0.42, 0, 58, 0)
    var c = cam
    for (var i = 1; i < lat; i++) {
      var th = i * Math.PI / lat
      var sy = Math.cos(th), sr = Math.sin(th)
      var th2 = (i + 1) * Math.PI / lat
      var sy2 = Math.cos(th2), sr2 = Math.sin(th2)
      for (var j = 0; j < lon; j++) {
        var ph = j * 2 * Math.PI / lon, ph2 = (j + 1) * 2 * Math.PI / lon
        var ax = sr * Math.cos(ph), ay = sy, az = sr * Math.sin(ph)
        // Cull the far side: a point is visible when it faces the camera.
        if ((ax - c.px) * ax + (ay - c.py) * ay + (az - c.pz) * az > 0) continue
        var bx = sr * Math.cos(ph2), by = sy, bz = sr * Math.sin(ph2)
        edge(ax, ay, az, bx, by, bz, 1.2, w * 0.85, 0)          // latitude
        if (i < lat - 1) {
          var mx = sr2 * Math.cos(ph), my = sy2, mz = sr2 * Math.sin(ph)
          edge(ax, ay, az, mx, my, mz, 1.2, w * 0.7, 0)         // meridian
        }
      }
    }
    // Slabs standing on the surface, and beams cutting past them.
    for (var b = 0; b < 14; b++) {
      var la = 0.45 + 0.75 * Math.sin(b * 2.1), lo = b * 0.62 + t * 0.05
      var sr3 = Math.sin(la), cy3 = Math.cos(la)
      var ox = sr3 * Math.cos(lo), oy = cy3, oz = sr3 * Math.sin(lo)
      if ((ox - c.px) * ox + (oy - c.py) * oy + (oz - c.pz) * oz > 0) continue
      var up = 1.09
      // A flat plate just off the surface, drawn as a quad.
      var e1x = -Math.sin(lo), e1z = Math.cos(lo)
      var e2x = cy3 * Math.cos(lo), e2y = -sr3, e2z = cy3 * Math.sin(lo)
      var sz = 0.2 + 0.1 * Math.abs(wob(b * 3, t))
      var px1 = ox * up, py1 = oy * up, pz1 = oz * up
      var ax1 = px1 + (e1x * sz), ay1 = py1, az1 = pz1 + (e1z * sz)
      var ax2 = px1 - (e1x * sz), ay2 = py1, az2 = pz1 - (e1z * sz)
      var bx1 = ax1 + e2x * sz, by1 = ay1 + e2y * sz, bz1 = az1 + e2z * sz
      var bx2 = ax2 + e2x * sz, by2 = ay2 + e2y * sz, bz2 = az2 + e2z * sz
      edge(ax1, ay1, az1, ax2, ay2, az2, 1.4, w, 1)
      edge(bx1, by1, bz1, bx2, by2, bz2, 1.4, w, 1)
      edge(ax1, ay1, az1, bx1, by1, bz1, 1.4, w, 1)
      edge(ax2, ay2, az2, bx2, by2, bz2, 1.4, w, 1)
      // The leg down to the surface.
      edge(px1, py1, pz1, ox, oy, oz, 1.2, w * 0.6, 0)
    }
    // Beams: struck from points on the surface and thrown out past the
    // camera, the one warm thing in the shot.
    for (var g = 0; g < 7; g++) {
      var bl = 0.4 + 0.7 * Math.sin(g * 1.7 + t * 0.05)
      var bo = g * 0.95 + t * 0.19
      var brs = Math.sin(bl)
      var sx3 = brs * Math.cos(bo), sy3 = Math.cos(bl), sz3 = brs * Math.sin(bo)
      if ((sx3 - c.px) * sx3 + (sy3 - c.py) * sy3 + (sz3 - c.pz) * sz3 > 0) continue
      // Aim each beam somewhere near the camera and run it well past, so it
      // cuts right across the shot.
      var tox = c.px - sx3, toy = c.py - sy3, toz = c.pz - sz3
      var tl = Math.sqrt(tox * tox + toy * toy + toz * toz) || 1
      var lean = 0.55 * wob(g * 5, t * 0.4)
      var ex = sx3 + (tox / tl + lean) * 7, ey = sy3 + (toy / tl + lean * 0.4) * 7,
          ez = sz3 + (toz / tl - lean) * 7
      edge(sx3, sy3, sz3, ex, ey, ez, 2.2,
           w * (0.45 + 0.5 * Math.abs(Math.sin(t * 0.7 + g))), 2)
    }
  }

  // ── 5. The landing ────────────────────────────────────────────────────
  // The grid: a lit plane running away to the horizon, slabs on it, the
  // camera coming in low.
  readonly property real gridStep: 3.0

  function landing(t, w) {
    var fly = t * 7
    var drop = 1 + 5 * Math.max(0, 1 - ((t % cycle) / cycle - 0.72) * 9)
    look(Math.sin(t * 0.2) * 1.5, 1.6 + drop * 0.6, fly,
         0, 0.8 + drop * 0.3, fly + 14, 60, 0)
    var first = Math.ceil(fly / gridStep)
    var span = 13
    // Lines across, marching towards the camera.
    for (var k = -1; k < 22; k++) {
      var z = (first + k) * gridStep
      var fade = w * Math.max(0, 1 - (z - fly) / (22 * gridStep))
      edge(-span * gridStep, 0, z, span * gridStep, 0, z, 1.3, fade, 0)
    }
    // Lines running away, converging on the horizon.
    for (var j = -span; j <= span; j++) {
      var x = j * gridStep
      edge(x, 0, fly - gridStep, x, 0, fly + 22 * gridStep, 1.2,
           w * (1 - Math.abs(j) / (span + 3)) * 0.9, 0)
    }
    // The horizon, where the plane runs out.
    edge(-span * gridStep * 3, 0, fly + 22 * gridStep, span * gridStep * 3, 0,
         fly + 22 * gridStep, 2.4, w, 1)
    // Slabs standing on the plane.
    for (var b = 0; b < 9; b++) {
      var bz = first * gridStep + ((b * 7.3 + t * 0.6) % (20 * gridStep))
      var bx = ((b % 5) - 2) * gridStep * 2.6 + wob(b, t) * 2
      var bw = 1.6 + 0.8 * Math.abs(wob(b + 9, t * 0.3))
      var bh = 1.2 + 2.6 * Math.abs(wob(b + 4, t * 0.2))
      var fade2 = w * Math.max(0, 1 - (bz - fly) / (20 * gridStep))
      if (fade2 <= 0.005) continue
      // Four uprights and the top square: a slab, wireframe.
      for (var s2 = 0; s2 < 4; s2++) {
        var sx2 = (s2 === 0 || s2 === 3) ? -bw : bw
        var sz2 = (s2 < 2) ? -bw : bw
        edge(bx + sx2, 0, bz + sz2, bx + sx2, bh, bz + sz2, 1.3, fade2, 0)
      }
      edge(bx - bw, bh, bz - bw, bx + bw, bh, bz - bw, 1.3, fade2, 1)
      edge(bx + bw, bh, bz - bw, bx + bw, bh, bz + bw, 1.3, fade2, 1)
      edge(bx + bw, bh, bz + bw, bx - bw, bh, bz + bw, 1.3, fade2, 1)
      edge(bx - bw, bh, bz + bw, bx - bw, bh, bz - bw, 1.3, fade2, 1)
    }
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(dt) {
    now += dt
    var t = now
    di = 0
    hi = 0
    wi = 0

    var u = (t / cycle) % 1
    var wKal = weigh(u, 0.01, 0.12, 0.028)
    var wTun = weigh(u, 0.15, 0.32, 0.028)
    var wFld = weigh(u, 0.35, 0.55, 0.022)
    var wPla = weigh(u, 0.58, 0.76, 0.022)
    var wLan = weigh(u, 0.79, 0.98, 0.02)
    var open = ease(Math.min(1, t / 2))     // fade up on load

    if (wKal > 0.01) {
      // How far through the movement we are, for the colour cycle.
      cycleTint(t, Math.min(1, Math.max(0, (u - 0.01) / 0.11)))
      kaleidoscope(t, wKal * open)
    } else if (tintTick !== -2) {
      tint = accent          // the rest of the ride keeps the theme's colour
      tintTick = -2
    }
    if (wTun > 0.01) tunnel(t, wTun * open)
    if (wFld > 0.01) fieldRide(t, wFld * open, (u - 0.35) * cycle)
    if (wPla > 0.01) planet(t, wPla * open)
    if (wLan > 0.01) landing(t, wLan * open)

    for (var z = di; z < diWas; z++) dim.itemAt(z).opacity = 0
    for (var y2 = hi; y2 < hiWas; y2++) hot.itemAt(y2).opacity = 0
    for (var y3 = wi; y3 < wiWas; y3++) warm.itemAt(y3).opacity = 0
    diWas = di
    hiWas = hi
    wiWas = wi
  }

  // Thirty frames a second is plenty for this — the sequence it comes from
  // ran at twenty-four — and it halves what the scene costs the machine.
  FrameAnimation {
    property real spare: 0
    running: field.running && field.visible && field.width > 0
    onTriggered: {
      spare += Math.min(frameTime, 0.05)
      if (spare < 1 / 31) return
      field.step(spare)
      spare = 0
    }
  }
}
