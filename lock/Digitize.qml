import QtQuick

// ENCOM OS-12 lock screen, 1982 theme: the digitiser.
//
// An original abstract piece in the spirit of the first film's laser
// transfer: a shape resolving out of the grid. A tunnel of wireframe
// polygons recedes and turns, rings pulse outward from the centre, a field
// of bits lights up in waves, two Lissajous figures trace themselves, and a
// scan sweep passes over everything now and then.
//
// Everything is plain QtQuick items moved each frame (no Canvas repaints, no
// shaders), in the current theme's colours; the lock plugin hands the palette
// over. Nothing here touches the password.
Item {
  id: field

  property var encomPalette: ({})
  readonly property color accent: encomPalette.accent || "#b06cff"
  readonly property color accentHi: encomPalette.accentHi || "#e4cdff"
  readonly property color contrast: encomPalette.contrast || "#ffc300"
  readonly property color ink: encomPalette.ink || "#03030a"
  // The lock plugin reads this for the password field's frame.
  readonly property color line: accent
  readonly property color lineHi: accentHi

  property real now: 0
  property bool running: true

  readonly property int tunnelRings: 8
  readonly property int ringSides: 8
  readonly property int pulseCount: 4
  readonly property int curvePoints: 44
  readonly property int bitCols: 22
  readonly property int bitRows: 12

  Rectangle { anchors.fill: parent; color: field.ink; z: -100 }

  function placeSeg(item, ax, ay, bx, by, thick) {
    var dx = bx - ax, dy = by - ay
    item.x = ax; item.y = ay - thick / 2
    item.width = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    item.height = thick
    item.rotation = Math.atan2(dy, dx) * 180 / Math.PI
  }

  // ── The bit field: squares brightening in slow waves ──────────────────
  Repeater {
    id: bits
    model: field.bitCols * field.bitRows
    Rectangle {
      required property int index
      color: field.accent
      antialiasing: true
    }
  }

  // ── The tunnel: polygons receding towards the middle ──────────────────
  Repeater {
    id: tunnel
    model: field.tunnelRings * field.ringSides
    Rectangle {
      required property int index
      color: field.accent
      transformOrigin: Item.Left
      antialiasing: true
    }
  }

  // ── Pulses: rings thrown outward, fading as they go ───────────────────
  Repeater {
    id: pulses
    model: field.pulseCount * field.ringSides
    Rectangle {
      required property int index
      color: field.accentHi
      transformOrigin: Item.Left
      antialiasing: true
    }
  }

  // ── Two Lissajous figures, slowly changing shape ──────────────────────
  Repeater {
    id: curves
    model: 2 * field.curvePoints
    Rectangle {
      required property int index
      color: index < field.curvePoints ? field.contrast : field.accentHi
      transformOrigin: Item.Left
      antialiasing: true
      opacity: 0.85
    }
  }

  // ── The scan sweep ────────────────────────────────────────────────────
  Rectangle {
    id: sweep
    width: parent.width
    height: 2
    color: field.accentHi
    opacity: 0
  }
  Rectangle {
    id: sweepGlow
    width: parent.width
    height: 26
    color: field.accent
    opacity: 0
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height / 2 + 58
    z: 50
    text: "ENCOM OS-12  ·  SESSION LOCKED"
    color: field.accent
    opacity: 0.75
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 11
    font.letterSpacing: 4
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(dt) {
    now += dt
    var cx = width / 2, cy = height / 2
    var reach = Math.min(width, height) * 0.62

    // Bits: a travelling interference of two waves, squares growing and
    // brightening at the crests.
    var cellW = width / bitCols, cellH = height / bitRows
    for (var b = 0; b < bitCols * bitRows; b++) {
      var col = b % bitCols, row = (b / bitCols) | 0
      var wave = Math.sin(col * 0.5 - now * 1.1) * Math.cos(row * 0.62 + now * 0.7)
      var lit = Math.max(0, wave)
      var size = 2 + lit * Math.min(cellW, cellH) * 0.34
      var it = bits.itemAt(b)
      it.width = size; it.height = size
      it.x = (col + 0.5) * cellW - size / 2
      it.y = (row + 0.5) * cellH - size / 2
      it.opacity = 0.05 + lit * 0.42
      it.radius = size > 6 ? 1 : 0
    }

    // Tunnel: each ring sits at a depth that cycles inward; near ones are
    // wide and faint, far ones small and bright.
    for (var r = 0; r < tunnelRings; r++) {
      var depth = ((now * 0.16 + r / tunnelRings) % 1)
      var radius = reach * (0.06 + depth * depth * 1.15)
      var spin = now * 0.18 + r * 0.22
      var fade = (1 - depth) * 0.8
      for (var s = 0; s < ringSides; s++) {
        var a0 = spin + s * 2 * Math.PI / ringSides
        var a1 = spin + (s + 1) * 2 * Math.PI / ringSides
        var item = tunnel.itemAt(r * ringSides + s)
        placeSeg(item, cx + Math.cos(a0) * radius, cy + Math.sin(a0) * radius * 0.82,
                 cx + Math.cos(a1) * radius, cy + Math.sin(a1) * radius * 0.82, 1 + fade * 2)
        item.opacity = fade
      }
    }

    // Pulses: a ring every second or so, expanding and fading out.
    for (var p = 0; p < pulseCount; p++) {
      var age = (now + p * (2.4 / pulseCount)) % 2.4
      var grow = age / 2.4
      var pr = reach * grow * 1.25
      var alpha = Math.max(0, 1 - grow) * 0.8
      var turn = -now * 0.24 + p
      for (var q = 0; q < ringSides; q++) {
        var b0 = turn + q * 2 * Math.PI / ringSides
        var b1 = turn + (q + 1) * 2 * Math.PI / ringSides
        var pi = pulses.itemAt(p * ringSides + q)
        placeSeg(pi, cx + Math.cos(b0) * pr, cy + Math.sin(b0) * pr * 0.82,
                 cx + Math.cos(b1) * pr, cy + Math.sin(b1) * pr * 0.82, 1.5)
        pi.opacity = alpha
      }
    }

    // Lissajous figures: their frequencies drift, so the shape keeps
    // folding into a new one.
    for (var c = 0; c < 2; c++) {
      var fx = 2 + c + Math.sin(now * 0.05 + c) * 0.6
      var fy = 3 - c + Math.cos(now * 0.043 + c) * 0.6
      var phase = now * (0.5 + c * 0.2)
      // Wide and tall enough to loop around the password field rather than
      // tangle across it.
      var rx = reach * (0.78 - c * 0.12), ry = reach * (0.56 - c * 0.1)
      var prevX = 0, prevY = 0
      for (var k = 0; k <= curvePoints; k++) {
        var t = k / curvePoints * 2 * Math.PI
        var x = cx + Math.sin(fx * t + phase) * rx
        var y = cy + Math.sin(fy * t) * ry
        if (k > 0) {
          var ci = curves.itemAt(c * curvePoints + k - 1)
          placeSeg(ci, prevX, prevY, x, y, 1.6)
        }
        prevX = x; prevY = y
      }
    }

    // Sweep: a bright line crossing every few seconds.
    var cycle = now % 6.5
    if (cycle < 1.3) {
      var travel = cycle / 1.3
      sweep.y = travel * height
      sweepGlow.y = sweep.y - 12
      sweep.opacity = 0.75 * Math.sin(travel * Math.PI)
      sweepGlow.opacity = 0.16 * Math.sin(travel * Math.PI)
    } else {
      sweep.opacity = 0
      sweepGlow.opacity = 0
    }
  }

  FrameAnimation {
    running: field.running && field.visible && field.width > 0
    onTriggered: field.step(Math.min(frameTime, 0.05))
  }
}
