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
//      that flies at the camera and opens onto sheets of board, stacked one
//      behind another: traces, rows of dots, patches of dot matrix, vias and
//      beads of light running along tracks. The camera flies through the
//      stack, panning and spinning, and each sheet sweeps out past the edges
//      of the frame as it passes.
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

  readonly property real cycle: 64          // one full ride, in seconds

  Rectangle { anchors.fill: parent; color: field.ink; z: -100 }

  Repeater {
    id: dim
    model: field.dimCount
    Rectangle { color: field.tint; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: hot
    model: field.hotCount
    Rectangle { color: field.tintHot; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: warm
    model: field.warmCount
    Rectangle { color: field.tintWarm; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: beacon
    model: 18
    Rectangle { color: "#7dffb8"; transformOrigin: Item.Left; antialiasing: true }
  }

  // The band of sky over the horizon, once we are down among it.
  Rectangle {
    id: sky
    width: parent.width
    height: Math.max(34, parent.height * 0.075)
    opacity: 0
    z: -60
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#00160020" }
      GradientStop { position: 0.72; color: "#7d1b93" }
      GradientStop { position: 1.0; color: "#c93ac8" }
    }
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

  property int bi: 0

  // The green beam: a core with a softer sheath either side of it.
  function beamGreen(x, z, y0, y1, alpha) {
    if (alpha <= 0.006) return
    for (var g = 0; g < 3; g++) {
      var d0 = proj(x, y0, z, 0), d1 = proj(x, y1, z, 1)
      if (d0 < 0.2 || d1 < 0.2 || bi >= 18) return
      put(beacon.itemAt(bi++), sc.x0, sc.y0, sc.x1, sc.y1,
          3 + g * 7, alpha * (g === 0 ? 1 : 0.2))
    }
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
    // right = forward × world up. Straight up or down that cross product
    // vanishes, so blend towards one taken against +z as it gets small and
    // the camera keeps a steady basis through the overhead shots.
    var rx = -fz, ry = 0, rz = fx
    var rl = Math.sqrt(rx * rx + ry * ry + rz * rz)
    if (rl > 1e-6) { rx /= rl; ry /= rl; rz /= rl }
    var qx = fy, qy = -fx, qz = 0
    var ql = Math.sqrt(qx * qx + qy * qy + qz * qz)
    if (ql > 1e-6) { qx /= ql; qy /= ql; qz /= ql } else { qx = 1; qy = 0; qz = 0 }
    var mix = Math.max(0, Math.min(1, (rl - 0.06) / 0.22))
    rx = rx * mix + qx * (1 - mix)
    ry = ry * mix + qy * (1 - mix)
    rz = rz * mix + qz * (1 - mix)
    var ml = Math.sqrt(rx * rx + ry * ry + rz * rz) || 1
    rx /= ml; ry /= ml; rz /= ml
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
  property color tintHot: accentHi
  property color tintWarm: contrast
  property int tintTick: -1
  property int palState: -1

  // Each movement's colours. The ride opens and runs in the theme's, and the
  // arrival carries the sequence's own — blue ground, red beams, a green
  // beacon — because that is what the scene is.
  function palette(n) {
    if (palState === n) return
    palState = n
    if (n === 1) { tint = accent; tintHot = accentHi; tintWarm = contrast }
    else if (n === 2) { tint = "#2f6df0"; tintHot = "#d9d4ad"; tintWarm = "#ff3030" }
    else if (n === 3) { tint = "#6dffae"; tintHot = "#c9ffdf"; tintWarm = "#ff3030" }
  }

  function cycleTint(t, u) {
    var tick = Math.floor(t * 6)
    if (tick === tintTick) return
    tintTick = tick
    palState = 0
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
    var cw = width / 1.9, ch = height / 1.45
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
  readonly property int tunnelRings: 18
  readonly property int tunnelSides: 12
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
      // Triangles: each ring's own edges, then two diagonals back to the
      // ring behind, so the wall comes out as bands of triangles rather
      // than a ladder of squares.
      var lean = (k % 2) ? 1 : 0
      for (var e = 0; e < tunnelSides; e++) {
        var n = (e + 1) % tunnelSides
        edge(tvx[e], tvy[e], z, tvx[n], tvy[n], z, 1.5, fade, bright ? 1 : 0)
        if (k > 0) {
          var b1 = (e + lean) % tunnelSides
          var b2 = (e + 1 - lean + tunnelSides) % tunnelSides
          edge(tvx[e], tvy[e], z, twx[b1], twy[b1], z - ringGap, 1.2, fade * 0.6, 0)
          edge(tvx[n], tvy[n], z, twx[b2], twy[b2], z - ringGap, 1.1, fade * 0.45, 0)
        }
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

  // One plate: a tetromino of cells, each ruled into a grid, laid on
  // whatever pair of axes it is handed. The tunnel tumbles them; the clouds
  // lay them flat.
  function plate(ox, oy, oz, ux, uy, uz, vx, vy, vz, cell, shapeIx, rule, alpha, pool) {
    var shape = tetro[shapeIx % tetro.length]
    for (var q = 0; q < shape.length; q++) {
      var gx = (shape[q][0] - 1) * cell, gy = (shape[q][1] - 1.5) * cell
      for (var r = 0; r <= rule + 1; r++) {
        var f = r / (rule + 1)
        var rim = (r === 0 || r === rule + 1)
        var th = rim ? 1.5 : 1
        var a = alpha * (rim ? 1 : 0.5)
        var uA = gx, uB = gx + cell, vA = gy + f * cell
        edge(ox + ux * uA + vx * vA, oy + uy * uA + vy * vA, oz + uz * uA + vz * vA,
             ox + ux * uB + vx * vA, oy + uy * uB + vy * vA, oz + uz * uB + vz * vA,
             th, a, pool)
        var uC = gx + f * cell, vC = gy, vD = gy + cell
        edge(ox + ux * uC + vx * vC, oy + uy * uC + vy * vC, oz + uz * uC + vz * vC,
             ox + ux * uC + vx * vD, oy + uy * uC + vy * vD, oz + uz * uC + vz * vD,
             th, a, pool)
      }
    }
  }

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
      plate(ox, oy, zc, ux, uy, uz, vx, vy, vz, cell, p, plateRule, fade, pool)
    }
  }

  // ── 3. The field ──────────────────────────────────────────────────────
  // Sheets of board, one behind another along the way ahead, flown through
  // rather than over. What a sheet carries is decided by its number, not by
  // chance, so nothing has to be stored and it can run for ever.

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

  // The layers: sheets of board stacked along the way ahead, each with its
  // own scatter of traces, dot rows, dot matrix and vias. The camera flies
  // through them one after another rather than over any one of them, so a
  // sheet's pattern sweeps outward past the edges of the frame as it comes.
  readonly property int layerCount: 9
  readonly property real layerGap: 5.2

  function sheet(t, w, n, zc, fade) {
    for (var f = 0; f < 15; f++) {
      var hx = hash(n * 3 + f, f), hy = hash(f * 7, n - f), hk = hash(n + f * 11, f - n)
      var px = (hx - 0.5) * 34, py = (hy - 0.5) * 21
      var flat = hash(f, n) < 0.5
      if (hk < 0.3) {
        // A trace, or a ladder of them.
        var runs = 1 + Math.floor(hash(n, f * 5) * 4)
        var len = 3 + hash(f * 3, n) * 13
        for (var r = 0; r < runs; r++) {
          var step = r * 0.5
          if (flat) edge(px, py + step, zc, px + len, py + step, zc, 1.3, fade * 0.9, 0)
          else edge(px + step, py, zc, px + step, py + len, zc, 1.3, fade * 0.9, 0)
        }
      } else if (hk < 0.56) {
        // A row of evenly spaced dots.
        var cnt = 8 + Math.floor(hash(f, n * 2) * 8)
        for (var d = 0; d < cnt; d++) {
          if (flat) dot(px + d * 0.45, py, zc, 0.06, fade * 0.85, 0)
          else dot(px, py + d * 0.45, zc, 0.06, fade * 0.85, 0)
        }
      } else if (hk < 0.76) {
        // A patch of dot matrix: the fragments of grid.
        var cols = 4 + Math.floor(hash(n, f) * 3), rows = 3 + Math.floor(hash(f, f + n) * 3)
        for (var cc = 0; cc < cols; cc++)
          for (var rr = 0; rr < rows; rr++)
            dot(px + cc * 0.42, py + rr * 0.42, zc, 0.05,
                fade * (0.45 + 0.5 * hash(cc + f, rr + n)), hash(f + rr, cc) < 0.3 ? 1 : 0)
      } else if (hk < 0.88) {
        // Vias: lone warm dots.
        for (var v = 0; v < 3; v++)
          dot(px + v * 0.8, py + (hash(v, f) - 0.5) * 2, zc, 0.09, fade, 2)
      } else {
        // Beads of light running along a track, with a tail behind them.
        var travel = ((t * 0.5 + hx) % 1) * 9 - 2
        for (var b2 = 0; b2 < 7; b2++) {
          var slide = travel - b2 * 0.3
          var lit = fade * (1 - b2 / 7)
          if (flat) dot(px + slide, py, zc, 0.1, lit, 1)
          else dot(px, py + slide, zc, 0.1, lit, 1)
        }
      }
    }
  }

  function layers(t, w, fly) {
    var first = Math.floor(fly / layerGap) + 1
    for (var l = -1; l < layerCount; l++) {
      var n = first + l
      var zc = n * layerGap
      var near = zc - fly
      // Up as it comes into view, out again as it sweeps past the camera.
      var fade = w * ease((near - 0.6) / 2.5)
                   * Math.max(0, 1 - near / (layerCount * layerGap * 0.9))
      if (fade <= 0.006) continue
      sheet(t, w, n, zc, fade)
    }
  }

  function fieldRide(t, w, age) {
    var fly = t * 7.5
    // Panning and rolling as it crosses the board.
    var yaw = Math.sin(t * 0.17) * 0.32
    var roll = Math.sin(t * 0.11) * 0.55
    var rise = Math.sin(t * 0.13) * 2.2
    var side = Math.sin(t * 0.09) * 2.6
    // Pointed along the stack, panning and spinning as it goes through.
    look(side, rise, fly,
         side + Math.sin(yaw) * 9, rise * 0.4, fly + Math.cos(yaw) * 9, 68, roll)
    layers(t, w, fly)
    // The port: nested squares that fly at the camera and open out.
    if (age < 3.4) {
      var app = 1 - age / 3.4
      for (var n = 0; n < 4; n++) {
        var pz = fly + 0.6 + app * 30 + n * 1.6
        var hs = 2.4 + n * 0.85
        var pa = w * ease(app * 2.2) * (1 - n * 0.15)
        edge(side - hs, rise - hs, pz, side + hs, rise - hs, pz, 1.7, pa, 1)
        edge(side + hs, rise - hs, pz, side + hs, rise + hs, pz, 1.7, pa, 1)
        edge(side + hs, rise + hs, pz, side - hs, rise + hs, pz, 1.7, pa, 1)
        edge(side - hs, rise + hs, pz, side - hs, rise - hs, pz, 1.7, pa, 1)
      }
    }
  }

  // ── 4. The arrival ────────────────────────────────────────────────────
  // Over the planet and down onto it, in one run: high above a triangulated
  // surface with grid plates floating over it and red beams standing off the
  // dark cities; then down through the plates, over ground that rises and
  // falls, towards the one green beam; then over the city of extruded blocks
  // and canyons around the C that throws it; and out through a green
  // kaleidoscope, which hands back to the one the ride opens with.
  //
  // This act carries the colours the sequence itself has — blue ground, red
  // beams, a green beacon, a magenta horizon — rather than the theme's.
  readonly property real arriveFor: 29        // seconds the act runs
  readonly property real flySpeed: 9
  readonly property real curveR: 155          // how fast the surface falls away
  readonly property real cloudAlt: 9.5
  readonly property real beaconZ: 220

  function terrain(x, z) {
    return 1.5 * Math.sin(x * 0.085) * Math.cos(z * 0.062)
         + 1.1 * Math.sin((x + z) * 0.041 + 1.3)
         + 0.7 * Math.sin(x * 0.17 + z * 0.05)
  }

  // Height of the surface, with the curve of the world falling away from
  // wherever the camera is.
  property real curveNow: 155

  function surfaceY(x, z, cx0, cz0, amp) {
    var dx = x - cx0, dz = z - cz0
    return -(dx * dx + dz * dz) / (2 * curveNow) + terrain(x, z) * amp
  }

  readonly property int gCols: 14
  readonly property int gRows: 11
  property var gx0: []
  property var gy0: []
  property var gy1: []

  function arrival(t, w, age) {
    var fly = age * flySpeed
    // Altitude: high over the clouds, dipping through them, then low.
    // High over the clouds, down through them, low across the plain, then
    // up again on the approach so the structure fits in the frame when the
    // camera comes over the top of it.
    var alt = age < 12 ? 24 - age * 0.55
            : age < 15.5 ? 17.4 - (age - 12) * 3
            : age < 20 ? 6.9 - (age - 15.5) * 0.2
            : age < 25 ? 6 + (age - 20) * 2
            : 16 + (age - 25) * 0.6
    var side = Math.sin(age * 0.23) * 3.4
    // From orbit the world is a ball; down among it, it is a plain with a
    // horizon, so the curve slackens as we come down.
    curveNow = 210 + 1100 * ease((age - 11) / 6)
    // Once the beacon is in sight the camera keeps its eye on it, so it tips
    // down and back as it passes over the top of it.
    var track = ease((age - 19) / 4)
    var amp0 = ease((age - 11.5) / 4)
    // The camera rides the ground rather than a fixed height, or the ridges
    // come up through it once we are down low.
    var camY = terrain(side, fly) * amp0 + alt
    var sy0 = surfaceY(0, beaconZ, side, fly, amp0)
    var tx = side * 0.3 * (1 - track)
    var ty = (camY - 3.5) * (1 - track) + sy0 * track
    var tz = (fly + 30) * (1 - track) + beaconZ * track
    look(side, camY, fly, tx, ty, tz, 62, Math.sin(age * 0.2) * 0.07)
    var amp = amp0                             // flat from orbit, ridged low down
    var fade = w

    // The surface: rows across and columns away, with a diagonal in every
    // cell, so the ground is triangles like the film's.
    var r, c
    // Once the camera turns to watch the beacon go by it is looking behind
    // itself, so the ground has to start back there too.
    var back = 75 * ease((age - 19.5) / 4)
    for (c = 0; c <= gCols; c++) gx0[c] = side + (c - gCols / 2) * 15
    for (r = 0; r <= gRows; r++) {
      var z = fly + 4 - back + r * 6 + r * r * 1.9
      var zn = fly + 4 - back + (r + 1) * 6 + (r + 1) * (r + 1) * 1.9
      var far = fade * Math.max(0, 1 - r / (gRows + 1.5))
      if (far <= 0.006) continue
      for (c = 0; c <= gCols; c++) {
        gy1[c] = surfaceY(gx0[c], z, side, fly, amp)
        if (c > 0) edge(gx0[c - 1], gy1[c - 1], z, gx0[c], gy1[c], z, 1.2, far, 0)
      }
      if (r < gRows) {
        for (c = 0; c <= gCols; c++) {
          var yn = surfaceY(gx0[c], zn, side, fly, amp)
          edge(gx0[c], gy1[c], z, gx0[c], yn, zn, 1.1, far * 0.8, 0)
          if (c > 0) edge(gx0[c - 1], gy1[c - 1], z, gx0[c], yn, zn, 1, far * 0.55, 0)
        }
      }
    }

    // Grid plates floating over the surface: the clouds. They are the same
    // shapes the tunnel throws past, laid flat, and they sit still in the
    // world — the camera comes to them rather than them running away.
    var cloudStep = 26
    var firstCloud = Math.floor(fly / cloudStep)
    for (var p2 = 0; p2 < 11; p2++) {
      var ci = firstCloud + p2
      var pz = ci * cloudStep + (hash(ci, 2) - 0.5) * 16
      var px = (hash(ci, 1) - 0.5) * 185
      var py = surfaceY(px, pz, side, fly, amp) + cloudAlt + hash(1, ci) * 7
      var ahead2 = pz - fly
      var pf = fade * ease((ahead2 - 2) / 10) * Math.max(0, 1 - ahead2 / (11 * cloudStep))
      if (pf <= 0.006) continue
      // Far ones keep their outline only; near ones show their ruling.
      plate(px, py, pz, 1, 0, 0, 0, 0, 1,
            5.5 + hash(ci, 7) * 5.5, ci, ahead2 < 80 ? 2 : 0, pf, 1)
    }

    // Red beams standing off the dark cities we pass.
    for (var b = 0; b < 9; b++) {
      var bz = fly + 15 + ((b * 61.7 + age * 9) % 190)
      var bx = side + (hash(b, 9) - 0.5) * 110
      var by = surfaceY(bx, bz, side, fly, amp)
      var bf = fade * Math.max(0, 1 - (bz - fly) / 190)
      edge(bx, by, bz, bx, by + 34, bz, 2.2, bf, 2)
    }

    // The green beam, and the C it comes out of.
    var sy = surfaceY(0, beaconZ, side, fly, amp)
    var bcf = fade * ease((age - 13.5) / 2.5) * Math.max(0, 1 - (beaconZ - fly) / 260)
    beamGreen(0, beaconZ, sy, sy + 95, bcf)
    if (beaconZ - fly < 130 && age > 14) {
      var near = fade * ease((130 - (beaconZ - fly)) / 45) * ease((age - 14) / 2)
      // The C: a ring with a gap in it, walls standing off the ground.
      var segs = 24
      for (var s2 = 0; s2 < segs; s2++) {
        var a0 = s2 / segs * 2 * Math.PI, a1 = (s2 + 1) / segs * 2 * Math.PI
        if (a0 > 5.05 && a0 < 6.05) continue
        var r0 = 7.5, r1 = 10, hgt2 = 3.4
        var x00 = Math.cos(a0) * r0, z00 = beaconZ + Math.sin(a0) * r0
        var x01 = Math.cos(a1) * r0, z01 = beaconZ + Math.sin(a1) * r0
        var x10 = Math.cos(a0) * r1, z10 = beaconZ + Math.sin(a0) * r1
        var x11 = Math.cos(a1) * r1, z11 = beaconZ + Math.sin(a1) * r1
        edge(x00, sy + hgt2, z00, x01, sy + hgt2, z01, 1.5, near, 1)
        edge(x10, sy + hgt2, z10, x11, sy + hgt2, z11, 1.5, near, 1)
        edge(x00, sy + hgt2, z00, x10, sy + hgt2, z10, 1.2, near * 0.7, 1)
        edge(x00, sy, z00, x00, sy + hgt2, z00, 1.2, near * 0.6, 1)
      }
      // The city around it: extruded blocks with canyons between them.
      for (var k2 = 0; k2 < 63; k2++) {
        var gxi = (k2 % 9) - 4, gzi = Math.floor(k2 / 9) - 3
        if (hash(gxi, gzi) < 0.22) continue          // a street, not a block
        var kx = gxi * 8.5 + (hash(gxi, gzi + 5) - 0.5) * 2
        var kz = beaconZ + gzi * 8.5 + (hash(gzi, gxi + 5) - 0.5) * 2
        var fromC = Math.sqrt(kx * kx + (kz - beaconZ) * (kz - beaconZ))
        if (fromC < 12) continue                      // the clearing round the C
        var kw = 1.8 + hash(k2, 6) * 2.2, kd = 1.8 + hash(6, k2) * 2.2
        var kh = 1.4 + hash(k2, k2) * 6.5
        var ky = surfaceY(kx, kz, side, fly, amp)
        var kf = near * (0.5 + 0.5 * hash(k2, 8))
        edge(kx - kw, ky + kh, kz - kd, kx + kw, ky + kh, kz - kd, 1.2, kf, 0)
        edge(kx + kw, ky + kh, kz - kd, kx + kw, ky + kh, kz + kd, 1.2, kf, 0)
        edge(kx + kw, ky + kh, kz + kd, kx - kw, ky + kh, kz + kd, 1.2, kf, 0)
        edge(kx - kw, ky + kh, kz + kd, kx - kw, ky + kh, kz - kd, 1.2, kf, 0)
        edge(kx - kw, ky, kz - kd, kx - kw, ky + kh, kz - kd, 1.1, kf * 0.8, 0)
        edge(kx + kw, ky, kz + kd, kx + kw, ky + kh, kz + kd, 1.1, kf * 0.8, 0)
      }
    }

    // The horizon: where the surface runs out, with the sky's band over it.
    var hd = Math.sqrt(2 * curveNow * Math.max(1, alt))
    var d0 = proj(side, surfaceY(side, fly + hd, side, fly, 0), fly + hd, 0)
    if (d0 > 0.5) {
      sky.y = sc.y0 - sky.height
      sky.opacity = 0.34 * fade
    } else {
      sky.opacity = 0
    }
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(dt) {
    now += dt
    var t = now
    di = 0
    hi = 0
    wi = 0
    bi = 0

    var u = (t / cycle) % 1
    var wKal = weigh(u, 0.01, 0.12, 0.028)
    var wTun = weigh(u, 0.15, 0.32, 0.028)
    var wFld = weigh(u, 0.35, 0.55, 0.022)
    var wArr = weigh(u, 0.545, 0.995, 0.016)
    var open = ease(Math.min(1, t / 2))     // fade up on load

    if (wKal > 0.01) {
      // How far through the movement we are, for the colour cycle.
      cycleTint(t, Math.min(1, Math.max(0, (u - 0.01) / 0.11)))
      kaleidoscope(t, wKal * open)
    } else if (wArr <= 0.01) {
      palette(1)             // the middle of the ride keeps the theme's
    }
    if (wTun > 0.01) tunnel(t, wTun * open)
    if (wFld > 0.01) fieldRide(t, wFld * open, (u - 0.35) * cycle)
    if (wArr > 0.01) {
      var age = (u - 0.545) * cycle
      // Out through a green kaleidoscope, which hands back to the opening.
      var out = ease((age - 24.8) / 2)
      palette(out > 0.12 ? 3 : 2)
      if (out < 1) arrival(t, wArr * open * (1 - out) * (1 - out), age)
      else sky.opacity = 0
      if (out > 0) kaleidoscope(t, Math.min(1, out * 1.6) * wArr * open)
    } else {
      sky.opacity = 0
    }

    for (var z = di; z < diWas; z++) dim.itemAt(z).opacity = 0
    for (var y2 = hi; y2 < hiWas; y2++) hot.itemAt(y2).opacity = 0
    for (var y3 = wi; y3 < wiWas; y3++) warm.itemAt(y3).opacity = 0
    for (var y4 = bi; y4 < 18; y4++) beacon.itemAt(y4).opacity = 0
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
