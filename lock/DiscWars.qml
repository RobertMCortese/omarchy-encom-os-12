import QtQuick
import "poses.js" as Poses

// ENCOM OS-12 lock screen: a disc duel over the void, in the spirit of
// Tron: Legacy's disc games. Two original fighters, a teal program and an
// orange sentinel, each stand on a platform ringed by four concentric rings
// floating high above the arena floor, and move about them as they fight.
//
// They trade discs fast. A throw at the body is blocked on the defender's
// own disc, held up as a shield (only when that disc is home), or dodged
// with a sidestep or a flip (a side flip, a butterfly twist or a backflip)
// that carries it to another ring, never off the edge, and across a gap if
// a ring is gone; or in place with a duck, a sweep kick or a split jump; the
// disc ricochets off the glass. Now and then a throw connects: the fighter
// is knocked back a ring and stunned, or, with no ring behind, slides off
// and grabs the edge. Now and then a throw is
// banked off the ceiling onto one of the opponent's rings, often the one it
// stands on; the defender may catch it on a shield held overhead, or lose
// the ring. Losing its footing, a fighter drops and clings to the edge of
// the nearest ring still up; the next banked throw takes that out and it
// falls and derezzes. The rings rise again, the fighter rezzes back in, and
// the duel goes on.
//
// The movement is motion capture (poses.js, baked from the CMU Graphics Lab
// database: a frisbee throw, a stance, a sidestep); the block, the flip and
// the hang are built on top of it. The scene is 3D through a slowly drifting
// perspective camera, but drawn with plain QtQuick items, projected by hand
// each frame. No Qt Quick 3D, no real lights. Nothing here touches the
// password.
Item {
  id: arena

  readonly property color program: "#6fc3df"
  readonly property color programHi: "#d8f6ff"
  readonly property color sentinel: "#ff8c21"
  readonly property color sentinelHi: "#ffd9a8"
  readonly property color ink: "#010306"

  readonly property real floorY: -3.5          // the arena floor, far below
  readonly property real ceilY: 4.2
  readonly property real centreX: 8.0          // platform centres at -centreX and +centreX
  // Rings per fighter: the platform, then four rings; [inner, outer] radii.
  readonly property var ringRadii: [[0, 0.5], [0.56, 0.96], [1.02, 1.42], [1.48, 1.88], [1.94, 2.34]]
  readonly property int ringCount: ringRadii.length
  readonly property int ringSegs: 24

  // Two clocks: `now` runs the fight at `pace` times real speed; `wall` is
  // real time, for what should stay watchable (camera, sparks, falls).
  readonly property real pace: 2.55
  property real now: 0
  property real wall: 0
  // Off, the scene only moves when step() is called (for rendering previews).
  property bool running: true

  // ── Camera and projection ─────────────────────────────────────────────
  readonly property real fov: 48 * Math.PI / 180
  property var cam: ({ p: [0, 3, 10], f: [0, 0, -1], r: [1, 0, 0], u: [0, 1, 0], F: 1000 })

  function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
  function norm(a) { var l = Math.sqrt(dot(a, a)) || 1; return [a[0] / l, a[1] / l, a[2] / l] }
  function lerp3(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t] }
  function rand(a, b) { return a + Math.random() * (b - a) }
  function ease(u) { return u * u * (3 - 2 * u) }

  function aimCamera() {
    // A slow drift around the front of the arena, rising and falling.
    var yaw = 0.22 * Math.sin(wall * 0.06), dist = 14.6, h = 2.2 + 0.5 * Math.sin(wall * 0.045 + 1)
    var target = [0, 0.7, 0]
    var p = [target[0] + Math.sin(yaw) * dist, h, target[2] + Math.cos(yaw) * dist]
    var f = norm(sub(target, p)), r = norm(cross(f, [0, 1, 0])), u = cross(r, f)
    cam = { p: p, f: f, r: r, u: u, F: (height / 2) / Math.tan(fov / 2) }
  }

  // World point -> [screenX, screenY, depth]
  function project(w) {
    var d = sub(w, cam.p), z = Math.max(0.05, dot(d, cam.f))
    return [width / 2 + cam.F * dot(d, cam.r) / z, height / 2 - cam.F * dot(d, cam.u) / z, z]
  }

  // Place a segment item between two screen points.
  function placeSeg(item, a, b, thick) {
    var dx = b[0] - a[0], dy = b[1] - a[1]
    item.x = a[0]; item.y = a[1] - thick / 2
    item.width = Math.max(1, Math.sqrt(dx * dx + dy * dy))
    item.height = thick
    item.rotation = Math.atan2(dy, dx) * 180 / Math.PI
  }

  Rectangle { anchors.fill: parent; color: arena.ink; z: -2000 }

  // ── Arena: floor far below, the glass back wall, the ceiling edge ─────
  // [from, to, opacity, colour, width]
  readonly property var lines: (function () {
    var L = [], X = 16, Z = 5.5, lo = floorY, hi = ceilY
    for (var x = -X; x <= X; x += 1.5) L.push([[x, lo, -Z], [x, lo, Z], 0.1, "#6fc3df", 1])
    for (var z = -Z; z <= Z + 0.01; z += 1) L.push([[-X, lo, z], [X, lo, z], 0.1, "#6fc3df", 1])
    for (var wx = -X; wx <= X; wx += 4) L.push([[wx, lo, -Z], [wx, hi, -Z], 0.1, "#6fc3df", 1])
    L.push([[-X, 0, -Z], [X, 0, -Z], 0.08, "#6fc3df", 1])
    for (var cx = -X; cx <= X; cx += 4) L.push([[cx, hi, -Z], [cx, hi, 2], 0.12, "#6fc3df", 1])
    L.push([[-X, hi, -Z], [X, hi, -Z], 0.45, "#a8ecff", 1])
    L.push([[-X, lo, -Z], [-X, hi, -Z], 0.45, "#a8ecff", 1])
    L.push([[X, lo, -Z], [X, hi, -Z], 0.45, "#a8ecff", 1])
    return L
  })()

  Repeater {
    id: lineItems
    model: arena.lines.length
    Rectangle {
      required property int index
      color: arena.lines[index][3]
      opacity: arena.lines[index][2]
      transformOrigin: Item.Left
      antialiasing: true
      z: -1000
    }
  }

  // ── Rings ─────────────────────────────────────────────────────────────
  // Every edge circle of every ring, as [fighter, ring, radius]; each is
  // drawn as ringSegs short segments.
  readonly property var ringCircles: (function () {
    var C = []
    for (var p = 0; p < 2; p++)
      for (var k = 0; k < ringCount; k++)
        ringRadii[k].forEach(function (r) { if (r > 0) C.push([p, k, r]) })
    return C
  })()

  Repeater {
    id: ringItems
    model: arena.ringCircles.length * arena.ringSegs
    Rectangle {
      required property int index
      readonly property var circle: arena.ringCircles[Math.floor(index / arena.ringSegs)]
      color: circle[0] === 0 ? arena.program : arena.sentinel
      transformOrigin: Item.Left
      antialiasing: true
    }
  }

  // Per fighter, per ring: state "up", "falling" (t = when it went) or
  // "rising" (t = when it started back).
  property var rings: [0, 1].map(function () { return ringRadii.map(function () { return { s: "up" } }) })

  function ringLook(p, k) {                      // [y offset, opacity]
    var r = rings[p][k]
    if (r.s === "falling") { var a = wall - r.t; return [-4.5 * a * a, Math.max(0, 1 - a / 1.1)] }
    if (r.s === "rising") { var b = Math.min(1, (wall - r.t) / 0.9); return [-1.5 * (1 - ease(b)), b] }
    return [0, 1]
  }

  function breakRing(p, k) {
    var r = rings[p].slice()
    r[k] = { s: "falling", t: wall }
    var all = rings.slice(); all[p] = r; rings = all
  }

  function restoreRings() {
    rings = [0, 1].map(function (p) {
      return rings[p].map(function (r) { return r.s === "up" ? r : { s: "rising", t: wall } })
    })
  }

  function ringUp(p, k) { return rings[p][k].s !== "falling" }

  // ── Fighters ──────────────────────────────────────────────────────────
  // Joints (Poses.joints): 0 pelvis, 1/5 hips, 2/6 knees, 3/7 ankles, 4/8 toes,
  // 9 chest, 10 neck, 11 head top, 12/16 shoulders, 13/17 elbows,
  // 14/18 wrists, 15/19 hands (left/right).
  readonly property var limbs: [
    [1, 2, 0.13], [2, 3, 0.10], [3, 4, 0.07], [5, 6, 0.13], [6, 7, 0.10], [7, 8, 0.07],
    [1, 5, 0.13], [0, 9, 0.25], [9, 10, 0.08], [12, 16, 0.11],
    [12, 13, 0.08], [13, 14, 0.07], [14, 15, 0.06], [16, 17, 0.08], [17, 18, 0.07], [18, 19, 0.06]
  ]

  // A figure: dark capsules edged in its light, and a head with a visor.
  component Fighter: Item {
    id: f
    property color col
    property alias limbItems: limbRep
    property alias head: headItem
    property alias visor: visorItem
    anchors.fill: parent
    Repeater {
      id: limbRep
      model: arena.limbs.length
      Rectangle {
        color: "#03080b"
        border.color: f.col
        border.width: 1.5
        transformOrigin: Item.Left
        antialiasing: true
      }
    }
    Rectangle {
      id: headItem
      color: "#03080b"
      border.color: f.col
      border.width: 1.5
      antialiasing: true
      Rectangle {
        id: visorItem
        height: Math.max(2, parent.height * 0.14); width: parent.width * 0.5
        y: parent.height * 0.42
        color: f.col
        radius: height / 2
      }
    }
  }

  Fighter { id: fighterA; col: arena.program }
  Fighter { id: fighterB; col: arena.sentinel }

  // ── Discs, trails and sparks ──────────────────────────────────────────
  component DiscItem: Item {
    id: di
    property color col
    property color hot
    Rectangle {                          // glow
      anchors.centerIn: parent
      width: parent.width * 1.9; height: parent.height * 1.9; radius: Math.min(width, height) / 2
      color: di.col; opacity: 0.18
    }
    Rectangle {
      anchors.fill: parent; radius: Math.min(width, height) / 2
      color: "#03080b"; border.color: di.hot; border.width: Math.max(2, Math.min(width, height) * 0.12)
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.4; height: parent.height * 0.4; radius: Math.min(width, height) / 2
        color: "transparent"; border.color: di.col; border.width: 1.5
      }
    }
  }

  DiscItem { id: disc0; col: arena.program; hot: arena.programHi }
  DiscItem { id: disc1; col: arena.sentinel; hot: arena.sentinelHi }

  // Light trails: a tapering streak through each disc's recent positions.
  readonly property int trailLen: 16
  Repeater {
    id: trailItems
    model: 2 * arena.trailLen
    Rectangle {
      required property int index
      color: index < arena.trailLen ? arena.programHi : arena.sentinelHi
      opacity: 0.85 * (1 - (index % arena.trailLen) / arena.trailLen)
      transformOrigin: Item.Left
      antialiasing: true
      visible: false
    }
  }

  Repeater {
    id: sparkItems
    model: 4
    Item {
      width: 0; height: 0
      property real age: 1
      property color col: "white"
      property real size: 20
      visible: age < 0.5
      Rectangle {
        anchors.centerIn: parent
        width: parent.size * (1 + parent.age * 8); height: width; radius: width / 2
        color: "transparent"; border.color: parent.col; border.width: 2
        opacity: 1 - parent.age / 0.5
      }
      Rectangle {
        anchors.centerIn: parent
        width: parent.size * 1.8; height: width; radius: width / 2
        color: "white"; opacity: Math.max(0, 0.85 - parent.age * 4)
      }
    }
  }

  // Caption under the password field.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height / 2 + 58
    z: 2000
    text: "ENCOM OS-12  ·  SESSION LOCKED"
    color: arena.program
    opacity: 0.75
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 11
    font.letterSpacing: 4
  }

  // ── Fighter motion ────────────────────────────────────────────────────
  // mode: "stand", "flip", "drop" (falling to the ring edge), "cling",
  // "fall" (into the void), "gone", "rez" (coming back).
  property var fs: [
    { cx: -centreX, ring: 0, ang: 0, pos: [-centreX, 0], fv: [1, 0], move: null, clingRing: -1, clingAt: null, willClimb: false,
      dropFrom: null, clip: "idle", t: rand(0, 1), speed: 1, from: null, blend: 1, block: 0, blockTarget: 0,
      pose: null, mode: "stand", mt: 0, yOff: 0, alpha: 1, flip: "side", flipSide: 1, high: false, grip: "right", evade: "duck" },
    { cx: centreX, ring: 0, ang: 0, pos: [centreX, 0], fv: [-1, 0], move: null, clingRing: -1, clingAt: null, willClimb: false,
      dropFrom: null, clip: "idle", t: rand(0, 1), speed: 1, from: null, blend: 1, block: 0, blockTarget: 0,
      pose: null, mode: "stand", mt: 0, yOff: 0, alpha: 1, flip: "side", flipSide: 1, high: false, grip: "right", evade: "duck" }
  ]

  readonly property real throwSpeed: 1.4
  function releaseTime() { return Poses.clips.throw.release / Poses.fps / throwSpeed }

  function sample(name, t) {
    var c = Poses.clips[name], n = c.frames.length, fp = t * Poses.fps
    if (name === "idle") {                // ping-pong so the stance loops smoothly
      var period = 2 * (n - 1)
      fp = fp % period
      if (fp > n - 1) fp = period - fp
    } else {
      fp = Math.min(fp, n - 1)
    }
    var i = Math.floor(fp), k = fp - i, a = c.frames[i], b = c.frames[Math.min(n - 1, i + 1)]
    var out = new Array(a.length)
    for (var j = 0; j < a.length; j++) out[j] = a[j] + (b[j] - a[j]) * k
    return out
  }

  function clipLength(name) { return (Poses.clips[name].frames.length - 1) / Poses.fps }

  function play(p, name, speed) {
    var f = fs[p]
    f.from = f.pose ? f.pose.slice() : null
    f.blend = 0
    f.clip = name
    f.t = 0
    f.speed = speed || 1
  }

  function setMode(p, m) { fs[p].mode = m; fs[p].mt = 0 }

  readonly property real flipTime: 1.1           // fight seconds
  // Dodges in place, and being hit (fight seconds).
  readonly property var evadeTime: ({ duck: 0.9, sweep: 1.0, split: 0.9, hit: 1.2 })
  // Mostly side flips and twists, sometimes a backflip.
  function startFlip(p) {
    var r = Math.random()
    fs[p].flip = r < 0.45 ? "side" : r < 0.8 ? "twist" : "back"
    fs[p].flipSide = Math.random() < 0.5 ? 1 : -1
    setMode(p, "flip")
  }

  // Move joint j of a pose towards target point q by amount w.
  function pull(pose, j, q, w) {
    for (var c = 0; c < 3; c++) pose[j * 3 + c] += (q[c] - pose[j * 3 + c]) * w
  }
  function jp(pose, j) { return [pose[j * 3], pose[j * 3 + 1], pose[j * 3 + 2]] }

  // Local pose (figure facing +x, standing over the origin) for a fighter.
  function localPose(p, dt, realDt) {
    var f = fs[p]
    f.t += dt * f.speed
    // Flips run on fight time (they dodge discs); drops, falls and the
    // rez stay at real speed so they can be seen.
    f.mt += (f.mode === "flip" || f.mode === "evade" || f.mode === "hit") ? dt : realDt
    if (f.clip !== "idle" && f.t >= clipLength(f.clip)) play(p, "idle")
    var pose = sample(f.clip, f.t)
    if (f.from && f.blend < 1) {
      f.blend = Math.min(1, f.blend + dt / 0.18)
      for (var j = 0; j < pose.length; j++) pose[j] = f.from[j] + (pose[j] - f.from[j]) * f.blend
    }

    // The block: the disc held up as a shield, across the chest or
    // overhead against a shot banked off the ceiling; in both hands, or in
    // the left or right alone (f.grip).
    f.block += Math.max(-dt / 0.2, Math.min(dt / 0.1, f.blockTarget - f.block))
    if (f.block > 0) {
      var chest = jp(pose, 9)
      // [shoulder, elbow, wrist, hand] joints of each arm.
      var arms = f.grip === "both" ? [[16, 17, 18, 19], [12, 13, 14, 15]]
               : f.grip === "left" ? [[12, 13, 14, 15]] : [[16, 17, 18, 19]]
      arms.forEach(function (arm) {
        var sh = jp(pose, arm[0]), side = sh[2] - chest[2]
        var two = f.grip === "both"
        if (f.high) {
          // One hand reaches across above the head; two meet over it.
          pull(pose, arm[1], [sh[0] + 0.1, sh[1] + 0.26, sh[2] - side * (two ? 0.1 : 0.2)], f.block)
          pull(pose, arm[2], [sh[0] + 0.16, sh[1] + 0.52, sh[2] - side * (two ? 0.45 : 0.6)], f.block)
          pull(pose, arm[3], [sh[0] + 0.18, sh[1] + 0.62, sh[2] - side * (two ? 0.72 : 0.9)], f.block)
        } else if (two) {
          // Both forearms up, the disc between the hands in front.
          pull(pose, arm[1], [sh[0] + 0.2, sh[1] - 0.16, sh[2] + side * 0.05], f.block)
          pull(pose, arm[2], [chest[0] + 0.4, chest[1] - 0.02, chest[2] + side * 0.5], f.block)
          pull(pose, arm[3], [chest[0] + 0.48, chest[1] + 0.02, chest[2] + side * 0.4], f.block)
        } else {
          pull(pose, arm[1], [sh[0] + 0.24, sh[1] - 0.14, sh[2] - side * 0.2], f.block)
          pull(pose, arm[2], [chest[0] + 0.42, chest[1] - 0.02, chest[2] + side * 0.1], f.block)
          pull(pose, arm[3], [chest[0] + 0.5, chest[1] + 0.02, chest[2] - side * 0.2], f.block)
        }
      })
    }

    if (f.mode === "flip") {
      // Up, tucked, round and down. "side": an aerial, turning about the
      // forward axis and moving sideways out of the disc's line; "twist": a
      // butterfly twist, body tipped nearly flat and spinning about the
      // vertical; "back": a backflip.
      var u = Math.min(1, f.mt / flipTime), s = Math.sin(Math.PI * u), e = ease(u)
      var pv = jp(pose, 0), ch = jp(pose, 9)
      ;[2, 3, 4, 6, 7, 8].forEach(function (k) { pull(pose, k, pv, (f.flip === "twist" ? 0.25 : 0.5) * s) })
      ;[13, 14, 15, 17, 18, 19].forEach(function (k) { pull(pose, k, ch, 0.35 * s) })
      var py = pv[1] + 0.1, lift = (f.flip === "twist" ? 1.1 : 1.35) * s
      for (var q = 0; q < 20; q++) {
        var x = pose[q * 3] - pv[0], y = pose[q * 3 + 1] - py, z = pose[q * 3 + 2] - pv[2], t
        if (f.flip === "back") {
          var a1 = 2 * Math.PI * e
          t = x * Math.cos(a1) - y * Math.sin(a1); y = x * Math.sin(a1) + y * Math.cos(a1); x = t
        } else if (f.flip === "side") {
          var a2 = 2 * Math.PI * e * f.flipSide
          t = y * Math.cos(a2) - z * Math.sin(a2); z = y * Math.sin(a2) + z * Math.cos(a2); y = t
        } else {
          var tilt = 1.35 * s, a3 = 2 * Math.PI * e
          t = y * Math.cos(tilt) - z * Math.sin(tilt); z = y * Math.sin(tilt) + z * Math.cos(tilt); y = t
          t = x * Math.cos(a3) + z * Math.sin(a3); z = -x * Math.sin(a3) + z * Math.cos(a3); x = t
        }
        pose[q * 3] = pv[0] + x
        pose[q * 3 + 1] = py + y + lift
        pose[q * 3 + 2] = pv[2] + z
      }
      if (u >= 1) setMode(p, "stand")
    }

    if (f.mode === "evade" || f.mode === "hit") {
      // Blend towards the dodge (or the knock-back) and out again.
      var kind = f.mode === "hit" ? "hit" : f.evade
      var eu = Math.min(1, f.mt / evadeTime[kind])
      var ew = eu < 0.2 ? ease(eu / 0.2) : eu > 0.75 ? ease((1 - eu) / 0.25) : 1
      var tg = evadePose(kind, pose, eu)
      for (var e = 0; e < pose.length; e++) pose[e] += (tg[e] - pose[e]) * ew
      if (kind === "split") {
        var jump = 0.9 * Math.sin(Math.PI * eu)
        for (var jy = 0; jy < 20; jy++) pose[jy * 3 + 1] += jump
      }
      if (eu >= 1) setMode(p, "stand")
    }

    if (f.mode === "drop" || f.mode === "cling" || f.mode === "fall" || f.mode === "climb") {
      // Hanging by both hands from the ring edge, legs loose; a climb lets
      // go of the pose as it comes up over the edge.
      var hw = f.mode === "climb" ? 1 - ease(Math.min(1, f.mt / 0.6)) : 1
      ;[[12, 13, 14, 15], [16, 17, 18, 19]].forEach(function (arm) {
        var s0 = jp(pose, arm[0])
        pull(pose, arm[1], [s0[0] + 0.04, s0[1] + 0.27, s0[2]], hw)
        pull(pose, arm[2], [s0[0] + 0.06, s0[1] + 0.52, s0[2]], hw)
        pull(pose, arm[3], [s0[0] + 0.07, s0[1] + 0.62, s0[2]], hw)
      })
    }

    f.pose = pose
    return pose
  }

  // Full-extent poses for the dodges in place and for being hit, around
  // where the fighter stands (local frame: facing +x, +z its right).
  function evadePose(kind, pose, u) {
    var px = pose[0], pz = pose[2]
    var rs = (pose[16 * 3 + 2] - pose[12 * 3 + 2]) >= 0 ? 1 : -1
    function P(x, y, z) { return [px + x, y, pz + z * rs] }
    var J
    if (kind === "duck") {                            // a deep crouch, head down
      J = [P(0, 0.55, 0), P(0, 0.55, -0.1), P(0.4, 0.6, -0.18), P(0.05, 0.08, -0.2), P(0.2, 0, -0.22),
           P(0, 0.55, 0.1), P(0.35, 0.55, 0.18), P(0, 0.08, 0.2), P(0.15, 0, 0.22),
           P(0.3, 0.95, 0), P(0.4, 1.05, 0), P(0.55, 1.2, 0),
           P(0.3, 0.98, -0.18), P(0.45, 0.75, -0.25), P(0.55, 0.55, -0.2), P(0.6, 0.5, -0.18),
           P(0.3, 0.98, 0.18), P(0.45, 0.75, 0.25), P(0.55, 0.55, 0.2), P(0.6, 0.5, 0.18)]
    } else if (kind === "sweep") {                    // low on the hands, one leg sweeping round
      var th = 2 * Math.PI * ease(u), dx = Math.cos(th), dz = Math.sin(th)
      J = [P(0, 0.45, 0), P(0, 0.45, -0.1), P(0.3, 0.35, -0.25), P(0, 0.05, -0.35), P(0.12, 0, -0.38),
           P(0, 0.45, 0.1), P(dx * 0.45, 0.2, 0.1 + dz * 0.45), P(dx * 0.9, 0.08, 0.1 + dz * 0.9),
           P(dx * 1.05, 0.08, 0.1 + dz * 1.05),
           P(0.1, 0.85, 0.05), P(0.15, 0.95, 0.05), P(0.22, 1.1, 0.05),
           P(0.1, 0.88, -0.18), P(0.2, 0.55, -0.3), P(0.3, 0.15, -0.35), P(0.35, 0.02, -0.35),
           P(0.1, 0.88, 0.18), P(0.25, 0.55, 0.3), P(0.35, 0.2, 0.35), P(0.4, 0.05, 0.35)]
    } else if (kind === "split") {                    // legs out wide, hands to the toes
      J = [P(0, 1.0, 0), P(0, 1.0, -0.1), P(0.15, 1.0, -0.5), P(0.3, 1.0, -0.9), P(0.38, 1.02, -0.95),
           P(0, 1.0, 0.1), P(0.15, 1.0, 0.5), P(0.3, 1.0, 0.9), P(0.38, 1.02, 0.95),
           P(0.12, 1.45, 0), P(0.15, 1.58, 0), P(0.18, 1.78, 0),
           P(0.12, 1.48, -0.18), P(0.2, 1.3, -0.45), P(0.28, 1.12, -0.7), P(0.32, 1.06, -0.8),
           P(0.12, 1.48, 0.18), P(0.2, 1.3, 0.45), P(0.28, 1.12, 0.7), P(0.32, 1.06, 0.8)]
    } else {                                          // hit: thrown back, arms flung wide
      J = [P(-0.12, 0.92, 0), P(-0.12, 0.92, -0.1), P(0.05, 0.5, -0.14), P(0.1, 0.08, -0.16), P(0.25, 0, -0.17),
           P(-0.12, 0.92, 0.1), P(-0.05, 0.5, 0.14), P(-0.1, 0.08, 0.16), P(0.05, 0, 0.17),
           P(-0.35, 1.35, 0), P(-0.42, 1.45, 0), P(-0.5, 1.62, 0),
           P(-0.35, 1.38, -0.2), P(-0.3, 1.55, -0.45), P(-0.15, 1.6, -0.65), P(-0.1, 1.6, -0.72),
           P(-0.35, 1.38, 0.2), P(-0.3, 1.55, 0.45), P(-0.15, 1.6, 0.65), P(-0.1, 1.6, 0.72)]
    }
    var out = []
    J.forEach(function (j) { out.push(j[0], j[1], j[2]) })
    return out
  }

  // Hand height (local) in the hanging pose; the drop lowers the figure so
  // the hands meet the ring.
  // ── Positions on the rings ────────────────────────────────────────────
  function ringMid(k) { return k === 0 ? 0 : (ringRadii[k][0] + ringRadii[k][1]) / 2 }
  function groundAt(p, r, a) { return [fs[p].cx + Math.cos(a) * r, Math.sin(a) * r] }
  function intactRings(p) {
    var out = []
    for (var k = 0; k < ringCount; k++) if (ringUp(p, k)) out.push(k)
    return out
  }

  // Move to ring k at angle a over dur fight-seconds, hopping `hop` metres.
  function relocate(p, k, a, dur, hop) {
    var f = fs[p]
    f.ring = k; f.ang = a
    f.move = { from: f.pos.slice(), to: groundAt(p, ringMid(k), a), t0: now, dur: dur, hop: hop }
  }

  // Where a dodge can go: the nearest ring still up that is not this one
  // (across a gap if need be; never off the edge), and round a little.
  function dodgeSpot(p) {
    var f = fs[p], best = []
    intactRings(p).forEach(function (k) {
      if (k === f.ring) return
      var d = Math.abs(k - f.ring)
      if (!best.length || d < best[0][1]) best = [[k, d]]
      else if (d === best[0][1]) best.push([k, d])
    })
    if (!best.length) return null
    var k = best[Math.floor(Math.random() * best.length)][0]
    return [k, f.ang + (Math.random() < 0.5 ? -1 : 1) * rand(0.6, 1.3)]
  }

  function hangOffset(p) { return 0.03 - Math.max(fs[p].pose[15 * 3 + 1], fs[p].pose[19 * 3 + 1]) }

  // Lose footing: drop and hang from the edge of the nearest ring still up,
  // or fall straight away if there is none.
  // Knocked back off the ring edge with nothing behind: grab ring k's edge
  // at radius r, angle a.
  function slideOff(p, k, r, a) {
    var f = fs[p]
    f.move = null
    f.clingRing = k
    f.willClimb = Math.random() < 0.33
    f.dropFrom = f.pos.slice()
    f.clingAt = groundAt(p, r, a)
    setMode(p, "drop")
  }

  // Hit: slide back a ring, away from the opponent; with no ring there (or
  // it is gone), slide off this one and hang from its edge.
  function knockBack(p) {
    var f = fs[p], rel = [f.pos[0] - f.cx, f.pos[1]]
    var awayOut = rel[0] * -f.fv[0] + rel[1] * -f.fv[1] >= 0 || f.ring === 0
    var back = awayOut ? f.ring + 1 : f.ring - 1
    var a = f.ring === 0 ? Math.atan2(-f.fv[1], -f.fv[0]) : f.ang
    if (back >= 0 && back < ringCount && ringUp(p, back)) {
      setMode(p, "hit")
      relocate(p, back, a, 0.45, 0.05)
    } else {
      slideOff(p, f.ring, awayOut ? ringRadii[f.ring][1] : ringRadii[f.ring][0], a)
    }
  }

  function drop(p) {
    var f = fs[p], near = null
    intactRings(p).forEach(function (k) {
      if (near === null || Math.abs(k - f.ring) < Math.abs(near - f.ring)) near = k
    })
    f.move = null
    if (near === null) { setMode(p, "fall"); return false }
    var edge = near < f.ring ? ringRadii[near][1] : ringRadii[near][0]
    f.clingRing = near
    f.willClimb = Math.random() < 0.33                  // one in three pulls itself back up
    f.dropFrom = f.pos.slice()
    f.clingAt = groundAt(p, edge, f.ring === 0 ? rand(0.5, 2.6) : f.ang)
    setMode(p, "drop")
    return true
  }

  function updateMode(p) {
    var f = fs[p]
    // Facing: always towards the opponent.
    var o = fs[1 - p].pos, dx = o[0] - f.pos[0], dz = o[1] - f.pos[1], l = Math.sqrt(dx * dx + dz * dz) || 1
    f.fv = [dx / l, dz / l]
    var hopY = 0
    if (f.move) {
      var u = Math.min(1, (now - f.move.t0) / f.move.dur)
      f.pos = [f.move.from[0] + (f.move.to[0] - f.move.from[0]) * ease(u),
               f.move.from[1] + (f.move.to[1] - f.move.from[1]) * ease(u)]
      hopY = f.move.hop * Math.sin(Math.PI * u)
      if (u >= 1) f.move = null
    }
    if (f.mode === "drop") {
      var v = Math.min(1, f.mt / 0.35)
      f.yOff = hangOffset(p) * ease(v)
      f.pos = [f.dropFrom[0] + (f.clingAt[0] - f.dropFrom[0]) * ease(v),
               f.dropFrom[1] + (f.clingAt[1] - f.dropFrom[1]) * ease(v)]
      if (v >= 1) setMode(p, "cling")
    } else if (f.mode === "cling") {
      f.yOff = hangOffset(p) + 0.03 * Math.sin(wall * 2.4)
      if (f.willClimb && f.mt > 0.8) setMode(p, "climb")
    } else if (f.mode === "climb") {
      // Up and over the edge, onto the ring it was holding.
      var c = Math.min(1, f.mt / 0.6), top = groundAt(p, ringMid(f.clingRing), Math.atan2(f.clingAt[1], f.clingAt[0] - f.cx))
      f.yOff = hangOffset(p) * (1 - ease(c)) + 0.25 * Math.sin(Math.PI * c)
      f.pos = [f.clingAt[0] + (top[0] - f.clingAt[0]) * ease(c), f.clingAt[1] + (top[1] - f.clingAt[1]) * ease(c)]
      if (c >= 1) {
        f.ring = f.clingRing
        f.ang = Math.atan2(f.clingAt[1], f.clingAt[0] - f.cx)
        f.clingRing = -1
        f.willClimb = false
        setMode(p, "stand")
      }
    } else if (f.mode === "fall") {
      f.yOff = Math.min(0, hangOffset(p)) - 4.9 * f.mt * f.mt
      f.alpha = Math.max(0, 1 - f.mt / 0.9)
      if (f.mt > 0.9) { spark([f.pos[0], f.yOff + 1, f.pos[1]], "#ffffff"); setMode(p, "gone") }
    } else if (f.mode === "rez") {
      f.yOff = 0
      f.alpha = Math.min(1, f.mt / 0.8)
      if (f.mt >= 0.8) setMode(p, "stand")
    } else if (f.mode === "stand" || f.mode === "flip" || f.mode === "evade" || f.mode === "hit") {
      f.yOff = hopY; f.alpha = 1
    }
  }

  // Local pose (facing +x) to the world: placed at the fighter's spot and
  // turned to face the opponent.
  function toWorld(p, local, j) {
    var f = fs[p], lx = local[j * 3], lz = local[j * 3 + 2]
    return [f.pos[0] + f.fv[0] * lx - f.fv[1] * lz, local[j * 3 + 1] + f.yOff, f.pos[1] + f.fv[1] * lx + f.fv[0] * lz]
  }
  function ahead(p, w, d) { return [w[0] + fs[p].fv[0] * d, w[1], w[2] + fs[p].fv[1] * d] }

  function canAct(p) { return fs[p].mode === "stand" }

  // ── Discs ─────────────────────────────────────────────────────────────
  // state: "back" (on the fighter's back), "hand", "shield", or "flight".
  property var ds: [
    { state: "back", pos: [0, 0, 0], trail: [], flight: null },
    { state: "back", pos: [0, 0, 0], trail: [], flight: null }
  ]

  function handWorld(p) { return toWorld(p, fs[p].pose, 19) }
  function chestWorld(p) { return toWorld(p, fs[p].pose, 9) }
  function backWorld(p) {
    var c = chestWorld(p)
    var b = ahead(p, c, -0.16)
    return [b[0], c[1] - 0.12, b[2]]
  }
  // Where the shield is: in the gripping hand, or between both hands.
  function shieldWorld(p) {
    var f = fs[p]
    var h = f.grip === "both" ? lerp3(toWorld(p, f.pose, 15), toWorld(p, f.pose, 19), 0.5)
          : f.grip === "left" ? toWorld(p, f.pose, 15) : handWorld(p)
    return f.high ? [h[0], h[1] + 0.08, h[2]] : ahead(p, h, 0.1)
  }
  function discHome(p) { return ds[p].state !== "flight" }

  // A flight: quadratic Béziers through control points; a point may be a
  // function, so a disc flying home follows its owner's moving hand.
  function fly(p, pts, dur, done) {
    ds[p].state = "flight"
    ds[p].trail = []
    ds[p].flight = { pts: pts, t0: now, dur: dur, done: done }
  }

  function flightPoint(fl, t) {
    var pts = fl.pts.map(function (q) { return typeof q === "function" ? q() : q })
    var n = (pts.length - 1) / 2, i = Math.min(n - 1, Math.floor(t * n)), u = t * n - i
    var a = pts[2 * i], c = pts[2 * i + 1], b = pts[2 * i + 2]
    return lerp3(lerp3(a, c, u), lerp3(c, b, u), u)
  }

  property int sparkNext: 0
  property var sparkData: [null, null, null, null]
  function spark(w, col) {
    var s = sparkData.slice()
    s[sparkNext] = { w: w, born: wall, col: String(col) }
    sparkData = s
    sparkNext = (sparkNext + 1) % 4
  }

  // ── The duel ──────────────────────────────────────────────────────────
  property var queue: []
  function after(delay, fn) { queue.push({ at: now + delay, fn: fn }) }
  // For what waits on something shown at real speed (a fall, a rez).
  property var wallQueue: []
  function afterWall(delay, fn) { wallQueue.push({ at: wall + delay, fn: fn }) }
  function hot(p) { return p === 0 ? arena.programHi : arena.sentinelHi }

  function flyHome(p, from) {
    var mid = lerp3(from, handWorld(p), 0.5)
    fly(p, [from, [mid[0], mid[1] + rand(0.4, 1.0), mid[2] + rand(-1.2, 1.2)], function () { return handWorld(p) }],
        rand(0.8, 1.0), function () {
          ds[p].state = "hand"
          after(0.3, function () { if (ds[p].state === "hand") ds[p].state = "back" })
        })
  }

  // Wind up and release; `launch` gets the release point.
  function throwFrom(p, launch) {
    play(p, "throw", throwSpeed)
    after(0.12, function () { ds[p].state = "hand" })
    after(releaseTime(), function () {
      if (canAct(p)) launch(handWorld(p))
      else ds[p].state = "back"                      // lost its footing mid-throw
    })
  }

  // Where a banked shot lands on ring k: under the fighter if it stands on
  // it, else somewhere on the side nearer the camera.
  function ringPoint(q, k) {
    var a = k === fs[q].ring ? fs[q].ang : rand(0.35, 2.8)
    var g = groundAt(q, k === 0 ? 0.15 : ringMid(k), a)
    return [g[0], 0, g[1]]
  }

  // Hold the disc up as a shield (overhead, or across the chest) and let
  // it go again a moment after the hit.
  function raiseShield(p, high) {
    if (!canAct(p) || !discHome(p)) return false
    fs[p].high = high
    // Half the time both hands; otherwise the left or the right.
    var r = Math.random()
    fs[p].grip = r < 0.5 ? "both" : r < 0.75 ? "left" : "right"
    fs[p].blockTarget = 1
    ds[p].state = "shield"
    return true
  }
  function lowerShield(p) {
    after(0.3, function () {
      fs[p].blockTarget = 0
      if (ds[p].state === "shield") ds[p].state = "back"
    })
  }

  // Bank a throw off the ceiling onto one of the opponent's rings, often
  // the one it stands on. A defender with its disc at home may catch it
  // overhead instead; a clinging one cannot.
  function bankShot(p, q, k) {
    throwFrom(p, function (from) {
      var caught = fs[q].mode === "stand" && canAct(q) && discHome(q) && Math.random() < 0.4
      var over = ahead(q, chestWorld(q), 0.15)
      var to = caught ? [over[0], 2.3, over[2]] : ringPoint(q, k)
      var top = [lerp3(from, to, 0.55)[0], ceilY, rand(-1.2, 1.2)]
      var dur = rand(1.15, 1.35)
      if (caught) after(dur - 0.35, function () { if (!raiseShield(q, true)) caught = false })
      fly(p, [from, lerp3(from, top, 0.5).map(function (v, i) { return i === 1 ? v + 0.6 : v }), top,
              lerp3(top, to, 0.5), to], dur, function () {
        spark(to, hot(p))
        flyHome(p, to)
        if (caught) {
          lowerShield(q)
          after(rand(0.3, 0.5), function () { rally(q) })
          return
        }
        breakRing(q, k)
        var f = fs[q]
        if (((f.mode === "cling" || f.mode === "climb") && k === f.clingRing) ||
            (f.mode === "stand" && k === f.ring && !drop(q))) {
          // Nothing left to hold on to.
          setMode(q, "fall")
          afterWall(2.4, function () { newRound(q) })
          return
        }
        // Let a fighter who has just dropped hang there a moment.
        if (f.mode === "stand") after(rand(0.3, 0.5), function () { rally(q) })
        else afterWall(rand(1.1, 1.5), function () { rally(p) })
      })
    })
    // Spark the ceiling as the disc caroms off it.
    after(releaseTime() + 0.47, function () {
      if (ds[p].state === "flight") spark(ds[p].pos, "#ffffff")
    })
  }

  // A throw at the body. Now and then it connects; otherwise it is blocked
  // on the shield, or dodged: a sidestep or a flip carries the defender to
  // another ring; a duck or a sweep kick lets it pass over, a split jump
  // lets it pass under.
  function bodyShot(p, q) {
    throwFrom(p, function (from) {
      var canBlock = discHome(q) && canAct(q)
      var r = Math.random()
      if (canAct(q) && r < 0.12) {
        // A hit: knocked back a ring and stunned.
        var hitAt = chestWorld(q)
        fly(p, [from, lerp3(from, hitAt, 0.5).map(function (v, i) { return i === 1 ? v + rand(0.1, 0.4) : v }), hitAt],
            rand(0.85, 1.05), function () {
          spark(hitAt, hot(p))
          if (canAct(q)) knockBack(q)
          flyHome(p, hitAt)
          after(1.0, function () { rally(p) })
        })
        return
      }
      if (canBlock && r < 0.55) {
        var to = ahead(q, chestWorld(q), 0.6)
        to[1] += 0.05
        var dur = rand(0.85, 1.05), mid = lerp3(from, to, 0.5)
        after(Math.max(0, dur - 0.3), function () { raiseShield(q, false) })
        fly(p, [from, [mid[0], mid[1] + rand(0.1, 0.6), mid[2] + rand(-1.4, 1.4)], to], dur, function () {
          spark(to, hot(p))
          lowerShield(q)
          flyHome(p, to)
          after(rand(0.25, 0.45), function () { rally(q) })
        })
        return
      }
      // Dodged: the disc flies on to the glass behind and ricochets home, at
      // a height to suit the dodge: over a duck or a sweep, under a split.
      var d = Math.random()
      var kind = d < 0.25 ? "sidestep" : d < 0.5 ? "flip" : d < 0.67 ? "duck" : d < 0.83 ? "sweep" : "split"
      var pass = kind === "duck" || kind === "sweep" ? 1.55 : kind === "split" ? 0.45 : rand(1.0, 1.6)
      var wall = [fs[q].cx > 0 ? 15.8 : -15.8, pass, rand(-1.0, 1.0)]
      var dur2 = rand(1.25, 1.4)
      var passAt = Math.abs(fs[q].pos[0] - from[0]) / Math.abs(wall[0] - from[0])
      var lead = kind === "flip" ? 0.45 : kind === "sidestep" ? 0.4 : 0.45 * evadeTime[kind]
      after(Math.max(0, dur2 * passAt - lead), function () {
        if (!canAct(q)) return
        var spot = dodgeSpot(q)
        if (kind === "flip") {
          startFlip(q)
          if (spot) relocate(q, spot[0], spot[1], flipTime, 0)
        } else if (kind === "sidestep") {
          play(q, "dodge", 1.3)
          if (spot) relocate(q, spot[0], spot[1], 0.5, 0.2)
        } else {
          fs[q].evade = kind
          setMode(q, "evade")
        }
      })
      var mid2 = lerp3(from, wall, 0.5)
      fly(p, [from, [mid2[0], pass, mid2[2] + rand(-0.6, 0.6)], wall], dur2, function () {
        spark(wall, hot(p))
        flyHome(p, wall)
        after(rand(0.3, 0.5), function () { rally(q) })
      })
    })
  }

  // Both throw together; the discs meet between them and fly home.
  function clash() {
    var m = [rand(-0.6, 0.6), rand(1.2, 1.9), rand(-1, 1)], landed = 0
    ;[0, 1].forEach(function (p) {
      throwFrom(p, function (from) {
        var mid = lerp3(from, m, 0.5)
        fly(p, [from, [mid[0], mid[1] + 0.3, mid[2] + rand(-0.6, 0.6)], m], 0.65, function () {
          if (++landed < 2) return
          spark(m, "#ffffff")
          flyHome(0, m); flyHome(1, m)
          after(rand(1.0, 1.4), function () { rally(Math.random() < 0.5 ? 0 : 1) })
        })
      })
    })
  }

  // p's turn to attack.
  function rally(p) {
    var q = 1 - p
    if (fs[p].mode === "gone" || fs[q].mode === "gone" || fs[p].mode === "fall" || fs[q].mode === "fall") return
    if (!canAct(p)) { after(0.3, function () { rally(q) }); return }
    if (!discHome(p)) { after(0.2, function () { rally(p) }); return }
    if (fs[q].mode === "climb" || (fs[q].mode === "cling" && fs[q].willClimb)) {
      afterWall(0.4, function () { rally(p) })                                // let it try
      return
    }
    if (fs[q].mode === "cling") { bankShot(p, q, fs[q].clingRing); return }     // finish it
    // Now and then, move to another ring before throwing.
    if (!fs[p].move && Math.random() < 0.3) {
      var spot = dodgeSpot(p)
      if (spot) {
        relocate(p, spot[0], spot[1], 0.45, 0.3)
        after(0.5, function () { rally(p) })
        return
      }
    }
    if (canAct(q) && discHome(q) && Math.random() < 0.15) { clash(); return }
    if (Math.random() < 0.12) {
      // Bank one off the ceiling: at the ring it stands on, or another.
      var up = intactRings(q)
      bankShot(p, q, Math.random() < 0.55 ? fs[q].ring : up[Math.floor(Math.random() * up.length)])
      return
    }
    bodyShot(p, q)
  }

  // After a fall: the rings rise again, the fighter rezzes back in at the
  // centre.
  function newRound(fallen) {
    restoreRings()
    var f = fs[fallen]
    f.ring = 0; f.ang = 0; f.pos = [f.cx, 0]; f.move = null; f.clingRing = -1
    setMode(fallen, "rez")
    f.yOff = 0; f.alpha = 0
    play(fallen, "idle")
    ds[fallen] = { state: "back", pos: [0, 0, 0], trail: [], flight: null }
    afterWall(1.2, function () { rally(1 - fallen) })
  }

  // ── Frame ─────────────────────────────────────────────────────────────
  function step(realDt) {
    var dt = realDt * pace
    now += dt
    wall += realDt
    var due = queue.filter(function (e) { return e.at <= now })
    if (due.length) {
      queue = queue.filter(function (e) { return e.at > now })
      due.forEach(function (e) { e.fn() })
    }
    var dueWall = wallQueue.filter(function (e) { return e.at <= wall })
    if (dueWall.length) {
      wallQueue = wallQueue.filter(function (e) { return e.at > wall })
      dueWall.forEach(function (e) { e.fn() })
    }
    // Rings that have finished rising are simply up again.
    rings.forEach(function (rs) {
      rs.forEach(function (r, k) { if (r.s === "rising" && wall - r.t > 0.9) rs[k] = { s: "up" } })
    })
    aimCamera()

    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i]
      placeSeg(lineItems.itemAt(i), project(ln[0]), project(ln[1]), ln[4])
    }

    // Rings: project each edge circle once, then lay its segments.
    for (var ci = 0; ci < ringCircles.length; ci++) {
      var cc = ringCircles[ci], look = ringLook(cc[0], cc[1]), cxw = fs[cc[0]].cx, pts = []
      for (var a = 0; a <= ringSegs; a++) {
        var ang = 2 * Math.PI * a / ringSegs
        pts.push(project([cxw + Math.cos(ang) * cc[2], look[0], Math.sin(ang) * cc[2]]))
      }
      var outer = cc[2] === ringRadii[cc[1]][1]
      for (var sg = 0; sg < ringSegs; sg++) {
        var it = ringItems.itemAt(ci * ringSegs + sg)
        placeSeg(it, pts[sg], pts[sg + 1], outer ? 2 : 1.2)
        it.opacity = look[1] * (outer ? 0.95 : 0.55)
        it.visible = look[1] > 0.01
        it.z = 1000 - (pts[sg][2] + pts[sg + 1][2]) * 10 - 1    // depth * 20, as the figures (sum of two depths * 10)
      }
    }

    ;[fighterA, fighterB].forEach(function (fi, p) {
      var local = localPose(p, dt, realDt)
      updateMode(p)
      fi.opacity = fs[p].alpha
      fi.visible = fs[p].mode !== "gone"
      var S = []
      for (var j = 0; j < 20; j++) S.push(project(toWorld(p, local, j)))
      for (var k = 0; k < limbs.length; k++) {
        var lb = limbs[k], a1 = S[lb[0]], b1 = S[lb[1]], depth = (a1[2] + b1[2]) / 2
        var thick = Math.max(2, lb[2] * cam.F / depth)
        var li = fi.limbItems.itemAt(k)
        placeSeg(li, a1, b1, thick)
        // Rounded capsules that overlap at the joints like a body.
        var rad = li.rotation * Math.PI / 180
        li.radius = thick / 2
        li.x -= thick / 2 * Math.cos(rad)
        li.y -= thick / 2 * Math.sin(rad)
        li.width += thick
        li.z = 1000 - depth * 20
      }
      var hc = project(lerp3(toWorld(p, local, 10), toWorld(p, local, 11), 0.55))
      var hs = 0.24 * cam.F / hc[2]
      fi.head.width = hs; fi.head.height = hs * 1.12; fi.head.radius = hs / 2
      fi.head.x = hc[0] - hs / 2; fi.head.y = hc[1] - hs * 0.56
      fi.head.z = 1000 - hc[2] * 20 + 1
      // The visor sits on whichever side the fighter faces, as seen on screen.
      var front = project(ahead(p, toWorld(p, local, 11), 0.3))
      fi.visor.x = front[0] > hc[0] ? hs * 0.45 : hs * 0.05
    })

    // Discs and their trails.
    ;[disc0, disc1].forEach(function (di, p) {
      var d = ds[p]
      if (d.state === "flight") {
        var fl = d.flight, t = Math.min(1, (now - fl.t0) / fl.dur)
        d.pos = flightPoint(fl, t)
        d.trail = [d.pos].concat(d.trail).slice(0, trailLen + 1)
        if (t >= 1) { d.flight = null; d.state = "hand"; fl.done() }
      } else {
        d.pos = d.state === "hand" ? handWorld(p) : d.state === "shield" ? shieldWorld(p) : backWorld(p)
        d.trail = d.trail.slice(0, Math.max(0, d.trail.length - 3))     // the streak fades after a catch
      }
      di.visible = fs[p].mode !== "gone"
      di.opacity = d.state === "flight" ? 1 : fs[p].alpha
      var s = project(d.pos), r = 0.3 * cam.F / s[2], view = norm(sub(d.pos, cam.p))
      if (d.state === "flight") {
        // Flying flat: seen more or less edge-on from the side.
        var squash = Math.max(0.25, Math.abs(view[1]) + 0.15)
        di.width = r; di.height = r * squash
      } else if (d.state === "shield") {
        // Held upright facing the enemy: narrow as the camera sees it.
        di.width = r * Math.max(0.3, Math.abs(view[0])); di.height = r * 1.05
      } else {
        di.width = r; di.height = r
      }
      di.x = s[0] - di.width / 2; di.y = s[1] - di.height / 2
      di.z = 1000 - s[2] * 20 + (d.state === "back" ? -3 : 3)
      // The trail: segments between successive positions, thinning out.
      var tp = d.trail.map(project)
      for (var g = 0; g < trailLen; g++) {
        var ti = trailItems.itemAt(p * trailLen + g)
        ti.visible = fs[p].mode !== "gone" && g + 1 < tp.length
        if (!ti.visible) continue
        var tw = Math.max(1, 0.06 * cam.F / tp[g][2] * (1 - g / trailLen))
        placeSeg(ti, tp[g], tp[g + 1], tw)
        ti.radius = tw / 2
        ti.z = 1000 - tp[g][2] * 20 - 1
      }
    })

    for (var n = 0; n < sparkData.length; n++) {
      var sp = sparkItems.itemAt(n), sd = sparkData[n]
      if (!sd) continue
      var ps = project(sd.w)
      sp.age = wall - sd.born
      sp.col = sd.col
      sp.size = 0.3 * cam.F / ps[2]
      sp.x = ps[0]; sp.y = ps[1]
      sp.z = 1500
    }
  }

  FrameAnimation {
    running: arena.running && arena.visible && arena.width > 0
    onTriggered: arena.step(Math.min(frameTime, 0.05))
  }

  Component.onCompleted: after(0.8, function () { rally(0) })
}
