/* ENCOM light cycles: the arena, the stadium and the cycles, after the light
 * cycle game in Tron: Legacy.
 *
 * Everything here is drawn from code: canvas textures, lines, points and
 * sprites. Nothing is a light source; every glow is a texture that only
 * looks lit, which keeps a small integrated GPU comfortable. The one real
 * light, a sun overhead, is only there to give the black bodies their shine.
 *
 *   EncomArena.build(scene, renderer, R)    floor, barrier, stands, towers
 *   EncomArena.bike(team)                   a cycle (THREE.Object3D, front -Z)
 *   EncomArena.ribbonMaterial(team)         a light ribbon's material
 *   EncomArena.TEAM                         clu (orange) and program (blue-white)
 */
(function () {
  "use strict";

  // The current theme's ENCOM palette (served at /palette.js), with the
  // Tron: Legacy colours standing in when there is none.
  var P = window.encomPalette || {};
  var TEAM = {
    clu:     { name: P.sideBName || "CLU", core: P.sideBHi || "#fff1d6", glow: P.sideB || "#ff8a1c" },
    program: { name: P.sideAName || "PROGRAMS", core: P.sideAHi || "#f2feff", glow: P.sideA || "#8fe3ff" },
  };
  var OUTLINE = P.accentHi || "#bfe9ff";       // stadium linework
  var GRID = P.accent || "#5ab4dc";            // the floor grid

  // "rgba(r,g,b,a)" from a hex colour, for the canvas textures.
  function rgba(hex, a) {
    var c = new THREE.Color(hex)
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," +
           Math.round(c.b * 255) + "," + a + ")";
  }

  // ── Textures, all drawn on canvases at load ─────────────────────────────
  function canvas(w, h, draw) {
    var c = document.createElement("canvas");
    c.width = w; c.height = h;
    draw(c.getContext("2d"), w, h);
    var t = new THREE.Texture(c);
    t.needsUpdate = true;
    return t;
  }

  // The ribbon: colour at the top and bottom edges (a hot, nearly white line
  // at the very top), fading to almost clear through the middle.
  function ribbonTexture(team) {
    return canvas(4, 128, function (g, w, h) {
      var grad = g.createLinearGradient(0, 0, 0, h);
      function stop(at, color, alpha) {
        var c = new THREE.Color(color);
        grad.addColorStop(at, "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," +
                              Math.round(c.b * 255) + "," + alpha + ")");
      }
      stop(0.00, team.core, 1.0);
      stop(0.05, team.core, 1.0);
      stop(0.10, team.glow, 0.95);
      stop(0.30, team.glow, 0.28);
      stop(0.50, team.glow, 0.12);
      stop(0.72, team.glow, 0.28);
      stop(0.90, team.glow, 0.85);
      stop(0.96, team.core, 0.9);
      stop(1.00, team.glow, 0.6);
      g.fillStyle = grad;
      g.fillRect(0, 0, w, h);
    });
  }

  // A soft round glow, white; tinted by the material using it.
  var glowTexture = canvas(64, 64, function (g, w, h) {
    var grad = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    grad.addColorStop(0, "rgba(255,255,255,1)");
    grad.addColorStop(0.25, "rgba(255,255,255,0.55)");
    grad.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = grad;
    g.fillRect(0, 0, w, h);
  });

  // A lamp: a hard bright centre inside the glow.
  var lampTexture = canvas(32, 32, function (g, w, h) {
    var grad = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    grad.addColorStop(0, "rgba(255,255,255,1)");
    grad.addColorStop(0.2, "rgba(255,255,255,0.9)");
    grad.addColorStop(0.45, "rgba(200,240,255,0.25)");
    grad.addColorStop(1, "rgba(200,240,255,0)");
    g.fillStyle = grad;
    g.fillRect(0, 0, w, h);
  });

  var derezTexture = canvas(128, 128, function (g, w, h) {
    [[0.46, 3, 1], [0.36, 2, 0.7], [0.27, 1.5, 0.45]].forEach(function (r) {
      g.strokeStyle = "rgba(255,255,255," + r[2] + ")";
      g.lineWidth = r[1];
      g.beginPath();
      g.arc(w / 2, h / 2, r[0] * w, 0, 2 * Math.PI);
      g.stroke();
    });
  });

  function ribbonMaterial(team) {
    return new THREE.MeshBasicMaterial({
      map: ribbonTexture(team), transparent: true, opacity: 1, depthWrite: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    });
  }

  // ── Cycles ──────────────────────────────────────────────────────────────
  // After the film's cycle: two big wheels joined by a long low body the
  // rider lies along, light rings round the wheels and light lines on the
  // body. Built with X across, Y along (front is +Y) and Z up, then turned
  // so that Y is up and the front faces -Z.
  function ellipsoid(sx, sy, sz, x, y, z) {
    var g = new THREE.SphereGeometry(1, 20, 12);
    g.applyMatrix(new THREE.Matrix4().makeScale(sx, sy, sz));
    g.applyMatrix(new THREE.Matrix4().makeTranslation(x, y, z));
    return g;
  }
  function box(sx, sy, sz, x, y, z) {
    var g = new THREE.BoxGeometry(sx, sy, sz);
    g.applyMatrix(new THREE.Matrix4().makeTranslation(x, y, z));
    return g;
  }
  function merge(list) {
    var g = new THREE.Geometry();
    list.forEach(function (p) { g.merge(p); });
    return g;
  }
  var WHEEL = 0.62, AXLE = 1.05;       // wheel radius, and axle distance from the middle
  function ring(y) {
    var g = new THREE.TorusGeometry(WHEEL, 0.09, 6, 32);
    g.applyMatrix(new THREE.Matrix4().makeRotationY(Math.PI / 2));   // stand it on edge
    g.applyMatrix(new THREE.Matrix4().makeTranslation(0, y, WHEEL));
    return g;
  }
  function hub(y) {
    var g = new THREE.CylinderGeometry(WHEEL - 0.06, WHEEL - 0.06, 0.34, 24);
    g.applyMatrix(new THREE.Matrix4().makeRotationZ(Math.PI / 2));   // axle across
    g.applyMatrix(new THREE.Matrix4().makeTranslation(0, y, WHEEL));
    return g;
  }

  var PARTS = {
    rider: merge([ellipsoid(0.19, 0.55, 0.17, 0, -0.1, 1.2), ellipsoid(0.14, 0.17, 0.14, 0, 0.5, 1.28)]),
    body: merge([ellipsoid(0.27, 1.25, 0.3, 0, 0, 0.95), ellipsoid(0.2, 0.5, 0.25, 0, 0, 0.62),
                 hub(AXLE), hub(-AXLE)]),
    rings: merge([ring(AXLE), ring(-AXLE)]),
    lines: merge([
      box(0.05, 1.5, 0.04, 0, -0.05, 1.25),        // spine
      box(0.04, 1.1, 0.05, 0.28, 0, 0.95),         // flanks
      box(0.04, 1.1, 0.05, -0.28, 0, 0.95),
      box(0.04, 0.5, 0.05, 0.21, 0, 0.6),          // engine
      box(0.04, 0.5, 0.05, -0.21, 0, 0.6),
    ]),
  };

  function glossy(opacity) {
    return new THREE.MeshPhongMaterial({
      color: 0x030405, specular: 0x6f8a99, shininess: 70, emissive: 0x000000,
      transparent: true, opacity: opacity,
    });
  }
  function light(color) {
    return new THREE.MeshBasicMaterial({ color: color, transparent: true, opacity: 1 });
  }


  var UPRIGHT = new THREE.Matrix4().makeRotationX(-Math.PI / 2);
  Object.keys(PARTS).forEach(function (k) { PARTS[k].applyMatrix(UPRIGHT); });

  // A cycle: its four parts (they fly apart separately when it derezzes),
  // the pool of colour it throws on the floor, and a marker that keeps the
  // same size on screen however far back the camera is.
  function bike(team) {
    var root = new THREE.Object3D();
    var parts = [
      new THREE.Mesh(PARTS.rider, glossy(1)),
      new THREE.Mesh(PARTS.body, glossy(1)),
      new THREE.Mesh(PARTS.rings, light(team.glow)),
      new THREE.Mesh(PARTS.lines, light(team.core)),
    ];
    parts.forEach(function (p) { root.add(p); });

    var pool = new THREE.Mesh(
      new THREE.PlaneBufferGeometry(4, 6.5),
      new THREE.MeshBasicMaterial({ map: glowTexture, color: team.glow, transparent: true,
                                    opacity: 0.55, depthWrite: false,
                                    blending: THREE.AdditiveBlending }));
    pool.rotation.x = -Math.PI / 2;
    pool.position.y = 0.04;
    root.add(pool);

    var markerGeometry = new THREE.Geometry();
    markerGeometry.vertices.push(new THREE.Vector3(0, 0.8, 0));
    var marker = new THREE.PointCloud(markerGeometry, new THREE.PointCloudMaterial({
      size: 22, sizeAttenuation: false, map: glowTexture, color: team.glow, transparent: true,
      opacity: 1, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending,
    }));
    root.add(marker);

    root.userData = { parts: parts, pool: pool, marker: marker };
    return root;
  }

  // ── The stadium ─────────────────────────────────────────────────────────
  function build(scene, renderer, R) {
    var group = new THREE.Object3D();
    scene.add(group);

    // The floor: near-black with a faint cyan grid.
    var floorTexture = canvas(128, 128, function (g, w, h) {
      g.fillStyle = "#02060a";
      g.fillRect(0, 0, w, h);
      g.fillStyle = rgba(GRID, 0.22);
      g.fillRect(0, 0, w, 2);
      g.fillRect(0, 0, 2, h);
      g.fillStyle = rgba(GRID, 0.07);
      g.fillRect(0, h / 2, w, 1);
      g.fillRect(w / 2, 0, 1, h);
    });
    floorTexture.wrapS = floorTexture.wrapT = THREE.RepeatWrapping;
    floorTexture.repeat.set(R / 4, R / 4);                // 8-unit cells
    floorTexture.anisotropy = renderer.getMaxAnisotropy();
    var floor = new THREE.Mesh(new THREE.PlaneBufferGeometry(2 * R, 2 * R),
                               new THREE.MeshBasicMaterial({ map: floorTexture }));
    floor.rotation.x = -Math.PI / 2;
    group.add(floor);

    var lineMaterial = new THREE.LineBasicMaterial({ color: OUTLINE, transparent: true, opacity: 0.9 });
    var dimLineMaterial = new THREE.LineBasicMaterial({ color: OUTLINE, transparent: true, opacity: 0.35 });

    // Points around a rounded rectangle of half-size h, corner radius r, at y.
    function roundedRect(h, r, y, perCorner) {
      var pts = [], c = h - r;
      [[c, c, 0], [-c, c, 0.5], [-c, -c, 1], [c, -c, 1.5]].forEach(function (k) {
        for (var i = 0; i <= perCorner; i++) {
          var a = (k[2] + 0.5 * i / perCorner) * Math.PI;
          pts.push(new THREE.Vector3(k[0] + r * Math.cos(a), y, -(k[1] + r * Math.sin(a))));
        }
      });
      pts.push(pts[0].clone());
      return pts;
    }
    function polyline(pts, material) {
      var g = new THREE.Geometry();
      g.vertices = pts;
      group.add(new THREE.Line(g, material));
    }
    function pieces(pairs, material) {
      var g = new THREE.Geometry();
      pairs.forEach(function (p) { g.vertices.push(p[0], p[1]); });
      group.add(new THREE.Line(g, material, THREE.LinePieces));
    }
    // Evenly spaced points along a closed polyline.
    function along(pts, spacing) {
      var out = [], carry = 0;
      for (var i = 1; i < pts.length; i++) {
        var a = pts[i - 1], b = pts[i], len = a.distanceTo(b), t = carry;
        for (; t < len; t += spacing) out.push(a.clone().lerp(b, t / len));
        carry = t - len;
      }
      return out;
    }
    function lamps(points, size, opacity) {
      var g = new THREE.Geometry();
      g.vertices = points;
      group.add(new THREE.PointCloud(g, new THREE.PointCloudMaterial({
        size: size, map: lampTexture, color: 0xdff6ff, transparent: true, opacity: opacity,
        depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true,
      })));
    }

    // The barrier: a low dark wall on the arena's edge, outlined top and foot,
    // with a row of lamps along its top.
    var WALL = 2.5;
    var wallMaterial = new THREE.MeshBasicMaterial({ color: 0x03070b });
    [[0, -R - 0.5, 2 * R + 2, 1], [0, R + 0.5, 2 * R + 2, 1],
     [-R - 0.5, 0, 1, 2 * R + 2], [R + 0.5, 0, 1, 2 * R + 2]].forEach(function (w) {
      var m = new THREE.Mesh(new THREE.BoxGeometry(w[2], WALL, w[3]), wallMaterial);
      m.position.set(w[0], WALL / 2, w[1]);
      group.add(m);
    });
    var edge = roundedRect(R, 0.01, 0.06, 1);
    polyline(edge, lineMaterial);
    polyline(roundedRect(R + 1, 0.01, WALL, 1), lineMaterial);
    polyline(roundedRect(R - 3, 6, 0.05, 6), dimLineMaterial);   // the inner lane line
    lamps(along(roundedRect(R + 1, 0.01, WALL + 0.3, 1), 6), 1.6, 0.9);

    // Tiers of stands stepping up and back, drawn as outlines with ribs
    // between them, and a lamp row on every other tier.
    var tiers = [], TIERS = 6;
    for (var k = 0; k <= TIERS; k++) {
      var h = R + 6 + k * 9, y = WALL + 1 + k * 4.5;
      tiers.push(roundedRect(h, 8 + k * 6, y, 8));
      polyline(tiers[k], k === 0 || k === TIERS ? lineMaterial : dimLineMaterial);
      if (k % 2 === 1) lamps(along(tiers[k], 4.5), 1.1, 0.55);
    }
    var ribs = [];
    for (k = 1; k <= TIERS; k++) {
      var inner = tiers[k - 1], outer = tiers[k];
      for (var i = 0; i < inner.length - 1; i += 2) ribs.push([inner[i], outer[i]]);
    }
    pieces(ribs, dimLineMaterial);
    // Front of the stands, a sheer drop to the barrier.
    pieces(along(tiers[0], 10).map(function (p) {
      return [p, new THREE.Vector3(p.x, WALL, p.z)];
    }), dimLineMaterial);

    // Floodlight towers: a mast, a rack of lamps and a wide soft glow. The
    // glow is a sprite, not a light: it lights nothing, it only looks lit.
    var top = tiers[TIERS], mastBase = WALL + 1 + TIERS * 4.5, MAST = 38;
    var towerAt = [];
    var c = R + 6 + TIERS * 9 - (8 + TIERS * 6) * (1 - Math.SQRT1_2);
    [[1, 1], [-1, 1], [-1, -1], [1, -1]].forEach(function (s) { towerAt.push([s[0] * c, s[1] * c]); });
    [[0, 1], [0, -1], [1, 0], [-1, 0]].forEach(function (s) {
      var d = R + 6 + TIERS * 9;
      towerAt.push([s[0] * d, s[1] * d]);
    });
    var masts = [], rack = [];
    towerAt.forEach(function (t) {
      var foot = new THREE.Vector3(t[0], mastBase, t[1]), head = new THREE.Vector3(t[0], mastBase + MAST, t[1]);
      masts.push([foot, head]);
      // A lamp rack across the mast head, facing the arena.
      var across = new THREE.Vector3(-t[1], 0, t[0]).normalize();
      for (var row = 0; row < 3; row++) {
        for (var col = -3; col <= 3; col++) {
          rack.push(head.clone().add(across.clone().multiplyScalar(col * 1.4)).setY(head.y + row * 1.4));
        }
      }
      var halo = new THREE.Sprite(new THREE.SpriteMaterial({
        map: glowTexture, color: 0xcfefff, transparent: true, opacity: 0.55,
        depthWrite: false, blending: THREE.AdditiveBlending,
      }));
      halo.position.copy(head).setY(head.y + 1.4);
      halo.scale.set(26, 26, 1);
      group.add(halo);
    });
    pieces(masts, lineMaterial);
    lamps(rack, 2.2, 1);

    // The spire on the skyline beyond the far stands.
    var spireBase = new THREE.Vector3(0, 0, -(R + 150)), spireTop = new THREE.Vector3(0, 150, -(R + 150));
    var spire = [];
    [[-14, 0], [14, 0], [0, -14], [0, 14]].forEach(function (o) {
      spire.push([new THREE.Vector3(o[0], 0, spireBase.z + o[1]), spireTop]);
    });
    pieces(spire, dimLineMaterial);
    lamps([spireTop.clone(), spireTop.clone().setY(100), spireTop.clone().setY(60)], 5, 1);
    return group;
  }

  window.EncomArena = {
    TEAM: TEAM, build: build, bike: bike, ribbonMaterial: ribbonMaterial,
    glowTexture: glowTexture, derezTexture: derezTexture,
  };
})();
