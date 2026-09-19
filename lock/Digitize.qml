import QtQuick

// ENCOM OS-12 lock screen, 1982 theme: the transfer.
//
// Our own take on the transition Robert Abel & Associates animated for the
// first film — the ride from the real world into the game world. Working
// from the published storyboard frames, the language there is: kaleidoscope.
// Dense quilts of fine straight lines, mirrored twelve ways and folding into
// a new figure every few seconds; a bright rosette turning at the middle of
// them; funnels of lines converging on a vanishing point; soft beams washing
// outward; and one warm cluster of fragments — the traveller — tumbling
// through the centre of it all, the only thing in frame that isn't the
// grid's own colour.
//
// Nothing is traced or copied from the film. Every figure is generated: a
// path of a few points across one wedge, mirrored into twenty-four, drifting
// with time so the pattern never repeats exactly. Each path starts on the
// wedge's mirror line and ends on its border, so the copies join up and the
// whole frame reads as one lattice. Four movements come round in turn — the
// web, the dive, the wash and the mandala — cross-fading into each other.
//
// Plain QtQuick rectangles moved each frame (no Canvas repaints, no shaders),
// in the current theme's colours; the lock plugin hands the palette over.
// Nothing here touches the password.
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

  // Twelve sectors, each mirrored: twenty-four ways round the figure.
  readonly property int sectors: 12
  readonly property int perSector: 8      // mesh nodes across one sector
  readonly property int levels: 5         // rings of nodes, innermost first
  readonly property int beamCount: 10
  readonly property int pieceCount: 44

  readonly property int arms: sectors * 2
  readonly property int nodes: sectors * perSector
  // A tangential segment on every ring but the first, and one diagonal per
  // node: enough to close the mesh into cells without doubling every edge.
  readonly property int webCount: nodes * (levels - 1) * 2
  // The two innermost rings are drawn in the bright colour, the rest in the
  // accent: the boards layer a hot core over a cooler web.
  readonly property int webInner: nodes * 2

  // The figure sits above the password field rather than behind it, the way
  // the boards keep the vanishing point off the middle of the frame.
  readonly property real cx: width / 2
  readonly property real cy: height * 0.38
  readonly property real reach: Math.min(width * 0.62, height * 0.95)

  Rectangle { anchors.fill: parent; color: field.ink; z: -100 }

  // ── One segment, in polar coordinates around the figure's centre ───────
  function ray(item, r0, a0, r1, a1, thick, alpha) {
    if (alpha <= 0.004) { item.opacity = 0; return }
    var ax = cx + Math.cos(a0) * r0, ay = cy + Math.sin(a0) * r0
    var bx = cx + Math.cos(a1) * r1, by = cy + Math.sin(a1) * r1
    var dx = bx - ax, dy = by - ay
    item.x = ax
    item.y = ay - thick / 2
    item.width = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    item.height = thick
    item.rotation = Math.atan2(dy, dx) * 180 / Math.PI
    item.opacity = alpha
  }

  // A repeatable wobble: one number per (seed, time), no randomness needed.
  function wob(seed, t) {
    return Math.sin(t * (0.19 + seed * 0.031) + seed * 2.39)
         * Math.cos(t * (0.11 + seed * 0.017) + seed * 1.11)
  }

  function ease(x) { return x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x) }

  // How strongly a movement is playing, given its slot in the cycle.
  function beat(phase, from, to) {
    var d = phase - (from + to) / 2
    if (d < -0.5) d += 1
    if (d > 0.5) d -= 1
    return ease(1 - Math.abs(d) / ((to - from) / 2 + 0.16))
  }

  // The lattice, the funnel, the rosette, the wash, the traveller.
  Repeater {
    id: webIn
    model: field.webInner
    Rectangle { color: field.accentHi; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: web
    model: field.webCount - field.webInner
    Rectangle { color: field.accent; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: funnel
    model: field.arms * 2
    Rectangle { color: field.accent; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: rose
    model: field.arms * 4
    Rectangle { color: field.accentHi; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: beams
    model: field.beamCount * 3
    Rectangle { color: field.accentHi; transformOrigin: Item.Left; antialiasing: true }
  }
  Repeater {
    id: pieces
    model: field.pieceCount
    Rectangle {
      required property int index
      color: index % 5 === 0 ? field.contrastHi : field.contrast
      antialiasing: true
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

  // The mesh: `nodes` points around each of `levels` rings. A node's radius
  // and angle wander with time, but only by how far it sits into its sector
  // and which side of the sector's mirror line it is on, so all twenty-four
  // copies stay in step and the figure keeps its symmetry while it folds.
  property var mx: []
  property var my: []

  function mesh(t, swell) {
    var R = reach
    var step2 = 2 * Math.PI / nodes
    var half = perSector / 2
    for (var k = 0; k < levels; k++) {
      var baseR = R * (0.1 + 1.15 * Math.pow(k / (levels - 1), 1.35))
      for (var a = 0; a < nodes; a++) {
        var p = a % perSector
        var side = p < half ? -1 : 1
        var j = p < half ? p : perSector - 1 - p      // mirrored position
        var seed = k * 5 + j * 3
        var rad = baseR * swell * (1 + 0.13 * wob(seed, t))
        var ang = a * step2 + side * step2 * 0.55 * wob(seed + 9, t * 0.9)
        var i = k * nodes + a
        mx[i] = cx + Math.cos(ang) * rad
        my[i] = cy + Math.sin(ang) * rad
      }
    }
  }

  // A segment between two mesh nodes.
  function link(item, i0, i1, thick, alpha) {
    if (alpha <= 0.004) { item.opacity = 0; return }
    var dx = mx[i1] - mx[i0], dy = my[i1] - my[i0]
    item.x = mx[i0]
    item.y = my[i0] - thick / 2
    item.width = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    item.height = thick
    item.rotation = Math.atan2(dy, dx) * 180 / Math.PI
    item.opacity = alpha
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(dt) {
    now += dt
    var t = now
    var R = reach
    var wedge = Math.PI / sectors
    var spin = t * 0.07

    var phase = (t / 26) % 1
    var wWeb = beat(phase, 0.00, 0.25)
    var wDive = beat(phase, 0.25, 0.50)
    var wWash = beat(phase, 0.50, 0.72)
    var wRose = beat(phase, 0.72, 1.00)
    var open = ease(Math.min(1, t / 2.5))   // fade the figure up on load

    // The lattice: rings of nodes joined round and across. It swells and
    // rushes outward through the dive, as though the camera were flying in.
    var swell = 1 + 0.06 * Math.sin(t * 0.4) + 0.5 * wDive * (((t * 0.5) % 1))
    mesh(t, swell)
    var idx = 0, inner = 0
    var lit = (0.5 + 0.32 * wWeb + 0.3 * wRose - 0.22 * wWash) * open
    for (var k = 0; k < levels - 1; k++) {
      var near = 1 - k * 0.09                  // inner rings read brighter
      for (var a = 0; a < nodes; a++) {
        var nxt = (a + 1) % nodes
        // Round the ring.
        var hot = k < 1
        link(hot ? webIn.itemAt(inner++) : web.itemAt(idx++),
             (k + 1) * nodes + a, (k + 1) * nodes + nxt,
             hot ? 1.3 : 1, lit * near * (hot ? 0.8 : 1))
        // And across to the next ring, leaning one way then the other so the
        // cells come out as triangles rather than a plain grid.
        var lean = ((a + k) % 2) ? nxt : (a + nodes - 1) % nodes
        link(hot ? webIn.itemAt(inner++) : web.itemAt(idx++),
             k * nodes + a, (k + 1) * nodes + lean,
             hot ? 1.2 : 1, lit * near * (hot ? 0.65 : 0.8))
      }
    }

    // Funnel: rays running in from beyond the frame to the vanishing point,
    // twisted a little, with two rings rushing outward past the camera.
    var rush = (t * 0.5) % 1
    for (var f = 0; f < arms; f++) {
      var fa = -spin * 1.5 + f * 2 * Math.PI / arms
      for (var g = 0; g < 2; g++) {
        var grow = (rush + g * 0.5) % 1
        var rr = R * (0.06 + grow * grow * 1.5)
        ray(funnel.itemAt(arms * g + f), rr, fa, rr, fa + 2 * Math.PI / arms,
            1 + 1.8 * grow, (1 - grow) * 0.75 * wDive * open)
      }
    }

    // Rosette: the bright figure at the centre, breathing and turning against
    // the lattice — spokes, two rings of chords, and a ring of fine teeth.
    var breathe = 1 + 0.06 * Math.sin(t * 0.9)
    var rIn = R * 0.115 * breathe, rMid = R * 0.155 * breathe, rOut = R * 0.2 * breathe
    var glow = (0.4 + 0.5 * wRose + 0.25 * wDive) * open
    for (var p = 0; p < arms; p++) {
      var pa1 = -spin * 2.1 + p * 2 * Math.PI / arms
      var pb1 = pa1 + 2 * Math.PI / arms
      ray(rose.itemAt(p), rIn, pa1, rOut, pa1, 1.3, glow)
      ray(rose.itemAt(arms + p), rIn, pa1, rIn, pb1, 1.2, glow * 0.75)
      ray(rose.itemAt(arms * 2 + p), rOut, pa1, rOut, pb1, 1.5, glow)
      // Teeth: short spikes outside the ring, every other arm.
      ray(rose.itemAt(arms * 3 + p), rOut, pa1 + wedge / 2,
          rOut + R * (0.035 + 0.02 * Math.sin(t * 1.4 + p)), pa1 + wedge / 2,
          1.4, glow * (p % 2 ? 0.9 : 0.4))
      if (p === 0) continue
      ray(rose.itemAt(arms + p), rMid, pa1, rMid, pb1, 1.1, glow * 0.6)
    }

    // Wash: pale beams thrown outward in a burst.
    for (var bm = 0; bm < beamCount; bm++) {
      var ba = spin * 0.6 + bm * 2 * Math.PI / beamCount + 0.25 * Math.sin(t * 0.2 + bm)
      var far = R * (1.15 + 0.25 * Math.sin(t * 0.4 + bm))
      var wide = 6 + 20 * Math.abs(Math.sin(t * 0.3 + bm))
      for (var pl = 0; pl < 3; pl++) {
        ray(beams.itemAt(bm * 3 + pl), R * 0.16, ba, far, ba,
            wide * (1 - pl * 0.33), (0.06 + pl * 0.06) * wWash * open)
      }
    }

    // The traveller: fragments tumbling at the vanishing point, thrown wide
    // during the dive and the wash, drawing together again for the mandala.
    var spread = 0.5 + 1.7 * wDive + 1.3 * wWash
    for (var i2 = 0; i2 < pieceCount; i2++) {
      var seed = i2 * 1.618
      var orbit = t * (0.45 + 0.5 * ((i2 % 7) / 7)) + seed * 3.1
      var rad = R * (0.02 + 0.05 * ((i2 % 11) / 11)) * spread * (1 + 0.3 * wob(seed, t))
      var lift = R * 0.04 * spread * Math.sin(t * 0.8 + seed)
      var size = 3 + 4 * ((i2 % 5) / 5) * (1 + 0.4 * Math.sin(t * 2 + seed))
      var it = pieces.itemAt(i2)
      it.width = size
      it.height = size * (0.6 + 0.6 * Math.abs(Math.cos(t * 1.7 + seed)))
      it.x = cx + Math.cos(orbit) * rad - size / 2
      it.y = cy + Math.sin(orbit) * rad * 0.8 + lift - size / 2
      it.rotation = (t * 40 + i2 * 33) % 360
      it.opacity = (0.45 + 0.5 * Math.abs(Math.sin(t * 1.3 + seed))) * open
    }
  }

  FrameAnimation {
    running: field.running && field.visible && field.width > 0
    onTriggered: field.step(Math.min(frameTime, 0.05))
  }
}
