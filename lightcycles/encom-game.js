/* ENCOM light cycles: a three-on-three light cycle match, played by AI, for
 * the ENCOM screensaver. Clu's three orange cycles against three programs.
 *
 * The arena is a grid of 2-unit cells. Cycles run from cell centre to cell
 * centre and turn only at centres; every cell a cycle enters is marked with
 * its id, and a cycle that runs into a marked cell or the barrier derezzes.
 * Its ribbon fades and its cells are freed, as in the film. A round ends when
 * one side (or nobody) is left, and the next starts a few seconds later.
 *
 * The AI measures, for each way it could go, how much of the arena it could
 * still reach (a flood fill over the grid), so it does not wind itself into a
 * pocket; once it is in one, it hugs the walls to use the space it has. With
 * room to spare, it hunts: it steers to cut across the nearest enemy's path.
 *
 * One overhead camera follows the closest duel, panning, zooming and turning
 * slowly to keep it in frame; each cycle carries a marker that stays the same
 * size on screen, so the others are never lost.
 *
 * #screensaver in the URL: no cursor, and the first real input asks the
 * local server to close the window.
 */
(function () {
  "use strict";

  var A = EncomArena, TEAM = A.TEAM;
  var R = 100, CELL = 2, N = 2 * R / CELL;   // arena half-size, cell size, cells per side
  var SPEED = 24;                       // units per second
  var H = 1.6, W = 0.2;                 // ribbon height and width
  var STEP = [[0, -1], [1, 0], [0, 1], [-1, 0]];   // N, E, S, W; right turn = +1
  var screensaver = /^#screensaver/.test(location.hash);

  // ── Scene ───────────────────────────────────────────────────────────────
  var renderer = new THREE.WebGLRenderer();
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setClearColor(0x010306);
  document.body.appendChild(renderer.domElement);
  var scene = new THREE.Scene();
  var sun = new THREE.DirectionalLight(0xffffff, 1);   // highlights on the black bodies
  sun.position.set(-1000, 5000, 1000);
  scene.add(sun);
  A.build(scene, renderer, R);

  // ── Grid ────────────────────────────────────────────────────────────────
  var grid = new Uint8Array(N * N);     // 0 = open, else cycle id + 1
  function inside(cx, cz) { return cx >= 0 && cz >= 0 && cx < N && cz < N; }
  function open(cx, cz) { return inside(cx, cz) && !grid[cz * N + cx]; }
  function centre(c) { return (c + 0.5) * CELL - R; }
  function cellOf(v) { return Math.floor((v + R) / CELL); }

  // Flood fill: how many open cells can be reached from (cx, cz), up to cap.
  var stamp = new Int32Array(N * N), stampNo = 0, queue = new Int32Array(N * N);
  function reach(cx, cz, cap) {
    if (!open(cx, cz)) return 0;
    stampNo++;
    var head = 0, tail = 0, count = 0;
    queue[tail++] = cz * N + cx;
    stamp[cz * N + cx] = stampNo;
    while (head < tail && count < cap) {
      var k = queue[head++], x = k % N, z = (k / N) | 0;
      count++;
      if (x > 0) visit(k - 1);
      if (x < N - 1) visit(k + 1);
      if (z > 0) visit(k - N);
      if (z < N - 1) visit(k + N);
    }
    return count;
    function visit(n) {
      if (stamp[n] !== stampNo && !grid[n]) { stamp[n] = stampNo; queue[tail++] = n; }
    }
  }

  function run(cx, cz, h, max) {
    for (var i = 1; i <= max; i++) if (!open(cx + STEP[h][0] * i, cz + STEP[h][1] * i)) return i - 1;
    return max;
  }

  // ── Ribbons ─────────────────────────────────────────────────────────────
  // Each finished stretch of a ribbon is three quads (two faces and the top
  // edge) written into one buffer per cycle, so a whole ribbon is one draw.
  // The stretch still being laid is a separate mesh, stretched every frame.
  var MAX_STRETCHES = 800, TOP_V = 0.93;

  function ribbonGeometry(stretches) {
    var g = new THREE.BufferGeometry();
    var index = new Uint16Array(stretches * 18);
    for (var s = 0; s < stretches * 3; s++) {
      index.set([0, 1, 2, 0, 2, 3].map(function (i) { return s * 4 + i; }), s * 6);
    }
    g.addAttribute("index", new THREE.BufferAttribute(index, 1));
    g.addAttribute("position", new THREE.BufferAttribute(new Float32Array(stretches * 36), 3));
    g.addAttribute("uv", new THREE.BufferAttribute(new Float32Array(stretches * 24), 2));
    return g;
  }

  // Write the stretch from a to b into slot s of a ribbon geometry.
  function writeStretch(g, s, ax, az, bx, bz) {
    var dx = bx - ax, dz = bz - az, len = Math.sqrt(dx * dx + dz * dz) || 1;
    dx /= len; dz /= len;
    var px = -dz * W / 2, pz = dx * W / 2;
    var pos = g.attributes.position.array, uv = g.attributes.uv.array;
    var quads = [
      [[ax + px, 0, az + pz], [bx + px, 0, bz + pz], [bx + px, H, bz + pz], [ax + px, H, az + pz], false],
      [[ax - px, 0, az - pz], [bx - px, 0, bz - pz], [bx - px, H, bz - pz], [ax - px, H, az - pz], false],
      [[ax + px, H, az + pz], [bx + px, H, bz + pz], [bx - px, H, bz - pz], [ax - px, H, az - pz], true],
    ];
    quads.forEach(function (q, i) {
      var v = (s * 3 + i) * 4;
      for (var j = 0; j < 4; j++) {
        pos.set(q[j], (v + j) * 3);
        uv[(v + j) * 2] = j === 1 || j === 2 ? 1 : 0;
        uv[(v + j) * 2 + 1] = q[4] ? TOP_V : (j >= 2 ? 1 : 0);
      }
    });
    g.attributes.position.needsUpdate = g.attributes.uv.needsUpdate = true;
  }

  // ── Cycles ──────────────────────────────────────────────────────────────
  var cycles = [];
  function Cycle(id, team) {
    this.id = id;
    this.team = team;
    this.root = A.bike(team);
    scene.add(this.root);
    this.material = A.ribbonMaterial(team);
    this.trail = new THREE.Mesh(ribbonGeometry(MAX_STRETCHES), this.material);
    this.trail.frustumCulled = false;
    scene.add(this.trail);
    var liveGeometry = ribbonGeometry(1);
    writeStretch(liveGeometry, 0, 0, 0, 0, -1);        // unit length, pointing -Z
    this.live = new THREE.Mesh(liveGeometry, this.material);
    scene.add(this.live);
    this.ring = sprite(A.derezTexture, team.glow);
    this.flare = sprite(A.glowTexture, team.core);
  }

  function sprite(map, color) {
    var s = new THREE.Sprite(new THREE.SpriteMaterial({
      map: map, color: color, transparent: true, opacity: 0, depthTest: false, depthWrite: false,
      blending: THREE.AdditiveBlending,
    }));
    s.visible = false;
    scene.add(s);
    return s;
  }

  Cycle.prototype.spawn = function (cx, cz, h) {
    this.cx = cx; this.cz = cz; this.h = h; this.t = 0;
    this.alive = true;
    this.derez = null;
    this.stretches = 0;
    this.from = [centre(cx), centre(cz)];
    this.aggression = 0.3 + Math.random() * 0.7;
    this.wander = 1 + Math.random() * 3;
    this.yaw = -h * Math.PI / 2;
    grid[cz * N + cx] = this.id + 1;
    var pos = this.trail.geometry.attributes.position;
    for (var i = 0; i < pos.array.length; i++) pos.array[i] = 0;
    pos.needsUpdate = true;
    this.material.opacity = 1;
    this.trail.visible = this.live.visible = this.root.visible = true;
    var d = this.root.userData;
    d.parts.forEach(function (p) {
      p.position.set(0, 0, 0);
      p.rotation.set(0, 0, 0);
      p.material.opacity = 1;
    });
    d.pool.visible = d.marker.visible = true;
    this.ring.visible = this.flare.visible = false;
    this.decide();
    this.reserve();
  };

  Cycle.prototype.x = function () { return centre(this.cx) + STEP[this.h][0] * this.t * CELL; };
  Cycle.prototype.z = function () { return centre(this.cz) + STEP[this.h][1] * this.t * CELL; };

  // Claim the next cell ahead, or derez if it is taken.
  Cycle.prototype.reserve = function () {
    var nx = this.cx + STEP[this.h][0], nz = this.cz + STEP[this.h][1];
    if (!open(nx, nz)) return this.crash();
    grid[nz * N + nx] = this.id + 1;
  };

  Cycle.prototype.turnTo = function (h) {
    if (h === this.h) return;
    var x = centre(this.cx), z = centre(this.cz);
    // Finish the stretch at this corner, overlapping half a width so the
    // corner closes.
    var d = STEP[this.h];
    if (this.stretches < MAX_STRETCHES) {
      writeStretch(this.trail.geometry, this.stretches++, this.from[0], this.from[1],
                   x + d[0] * W / 2, z + d[1] * W / 2);
    }
    this.from = [x, z];
    this.h = h;
  };

  Cycle.prototype.move = function (dt) {
    this.t += SPEED * dt / CELL;
    while (this.alive && this.t >= 1) {
      this.t -= 1;
      this.cx += STEP[this.h][0];
      this.cz += STEP[this.h][1];
      this.wander -= CELL / SPEED;
      this.decide();
      this.reserve();
    }
    if (!this.alive) this.t = 0.25;       // stopped against the obstacle
  };

  // ── AI ──────────────────────────────────────────────────────────────────
  var CAP = 1500, POCKET = 450;

  function nearestEnemy(c) {
    var best = null, bestD = Infinity;
    cycles.forEach(function (o) {
      if (!o.alive || o.team === c.team) return;
      var d = Math.abs(o.x() - c.x()) + Math.abs(o.z() - c.z());
      if (d < bestD) { bestD = d; best = o; }
    });
    return best;
  }

  function walls(cx, cz) {
    return (open(cx + 1, cz) ? 0 : 1) + (open(cx - 1, cz) ? 0 : 1) +
           (open(cx, cz + 1) ? 0 : 1) + (open(cx, cz - 1) ? 0 : 1);
  }

  // Called at every cell centre, before the next cell is claimed.
  Cycle.prototype.decide = function () {
    var c = this;
    if (c.champion && c.duel()) return;
    var ahead = run(c.cx, c.cz, c.h, 8);
    // Clear road and nothing to reconsider: keep going (no flood fill).
    if (ahead >= 5 && c.wander > 0) return;
    if (c.wander <= 0) c.wander = 0.6 + Math.random() * 2.4;

    var options = [];
    [c.h, (c.h + 3) % 4, (c.h + 1) % 4].forEach(function (h) {
      var nx = c.cx + STEP[h][0], nz = c.cz + STEP[h][1];
      if (!open(nx, nz)) return;
      options.push({ h: h, nx: nx, nz: nz, area: reach(nx, nz, CAP) });
    });
    if (!options.length) return;                       // boxed in: derez ahead
    var most = Math.max.apply(null, options.map(function (o) { return o.area; }));
    var safe = options.filter(function (o) { return o.area >= most * 0.9 || o.area >= CAP; });

    var pick;
    if (most < POCKET) {
      // In a pocket: follow the walls, which fills the space it has left
      // instead of cutting it in two.
      safe.forEach(function (o) {
        o.score = walls(o.nx, o.nz) * 10 + (o.h === c.h ? 1 : 0) + o.area / most;
      });
    } else {
      var enemy = nearestEnemy(c), tx = 0, tz = 0;
      if (enemy) {
        // Aim at the stretch of arena just ahead of the enemy.
        var lead = 10 + Math.random() * 10;
        tx = enemy.x() + STEP[enemy.h][0] * lead;
        tz = enemy.z() + STEP[enemy.h][1] * lead;
      }
      safe.forEach(function (o) {
        var score = (o.h === c.h ? 8 : 0) + Math.random() * 16;
        if (enemy) {
          var px = centre(o.nx) + STEP[o.h][0] * 6, pz = centre(o.nz) + STEP[o.h][1] * 6;
          score -= c.aggression * 0.9 * (Math.abs(px - tx) + Math.abs(pz - tz));
        }
        if (ahead < 3 && o.h === c.h) score -= 40;       // do not drive at the wall
        o.score = score;
      });
    }
    safe.sort(function (a, b) { return b.score - a.score; });
    pick = safe[0];
    c.turnTo(pick.h);
  };

  // ── Champions ───────────────────────────────────────────────────────────
  // One rider per side looks ahead. Near an enemy it plays the duel as a
  // game: a minimax search over its own moves and that enemy's, alternating,
  // pruned with alpha-beta, a few moves deep. Positions are scored by
  // territory: every open cell belongs to whichever rider can reach it first
  // (a Voronoi split of the arena, with every other rider competing for cells
  // from where it is now), and the score is the champion's share minus that
  // enemy's, so it steers to wall the enemy into the smaller share. It
  // deepens the search while time allows (a few milliseconds per decision).
  // Once no enemy can reach it any more, the round is decided by who lasts
  // longest in the space they have, so it fills its space: every move keeps
  // the most room it can still reach (counted exactly), hugging the walls so
  // it does not cut its own space in two. Otherwise it rides like the others.
  var DUEL_RANGE = 30, SEARCH_MS = 4, VORONOI_RANGE = 18, WIN = 100000, TIGHT = 1200;
  var bystanders = [];                                 // other riders' head cells
  var vStamp = new Int32Array(N * N), vNo = 0;
  var vOwner = new Int8Array(N * N), vDist = new Int16Array(N * N), vQueue = new Int32Array(N * N);
  var voronoiMet = false;

  // Cells nearer to a than to anyone, minus those nearer to b than to
  // anyone, within maxDist steps. Bystanders take cells but do not score.
  function voronoi(ax, az, bx, bz, maxDist) {
    vNo++;
    var head = 0, tail = 0, score = 0;
    voronoiMet = false;
    function seed(x, z, o) {
      var k = z * N + x;
      vStamp[k] = vNo; vOwner[k] = o; vDist[k] = 0;
      vQueue[tail++] = k;
    }
    seed(ax, az, 1);
    seed(bx, bz, 2);
    for (var s = 0; s < bystanders.length; s++) {
      if (vStamp[bystanders[s]] !== vNo) seed(bystanders[s] % N, (bystanders[s] / N) | 0, 3);
    }
    while (head < tail) {
      var k = vQueue[head++], d = vDist[k] + 1, o = vOwner[k];
      if (d > maxDist) continue;
      var x = k % N;
      for (var i = 0; i < 4; i++) {
        var n;
        if (i === 0) { if (x === 0) continue; n = k - 1; }
        else if (i === 1) { if (x === N - 1) continue; n = k + 1; }
        else if (i === 2) { if (k < N) continue; n = k - N; }
        else { if (k >= N * (N - 1)) continue; n = k + N; }
        if (grid[n]) continue;
        if (vStamp[n] !== vNo) {
          vStamp[n] = vNo; vOwner[n] = o; vDist[n] = d;
          vQueue[tail++] = n;
          score += o === 1 ? 1 : o === 2 ? -1 : 0;
        } else if (vOwner[n] !== o && o !== 0) {
          if (o + vOwner[n] === 3) voronoiMet = true;      // champion meets enemy
          if (vDist[n] === d && vOwner[n] !== 0) {        // a tie: nobody's
            score -= vOwner[n] === 1 ? 1 : vOwner[n] === 2 ? -1 : 0;
            vOwner[n] = 0;
          }
        }
      }
    }
    return score;
  }

  var deadline = 0, aborted = false;
  var searchStats = window.encomSearchStats = { searches: 0, ms: 0 };
  var MARK = 255;

  function minimax(mx, mz, ox, oz, depth, alpha, beta, mine) {
    if (performance.now() > deadline) { aborted = true; return 0; }
    if (depth === 0) return voronoi(mx, mz, ox, oz, VORONOI_RANGE);
    var any = false, best = mine ? -Infinity : Infinity;
    for (var h = 0; h < 4; h++) {
      var x = (mine ? mx : ox) + STEP[h][0], z = (mine ? mz : oz) + STEP[h][1];
      if (!open(x, z)) continue;
      any = true;
      var k = z * N + x;
      grid[k] = MARK;
      var v = mine ? minimax(x, z, ox, oz, depth - 1, alpha, beta, false)
                   : minimax(mx, mz, x, z, depth - 1, alpha, beta, true);
      grid[k] = 0;
      if (aborted) return 0;
      if (mine) { if (v > best) best = v; if (best > alpha) alpha = best; }
      else { if (v < best) best = v; if (best < beta) beta = best; }
      if (alpha >= beta) break;
    }
    // No way out: sooner is worse for whoever is stuck.
    if (!any) return mine ? -WIN - depth : WIN + depth;
    return best;
  }

  // Returns true if the duel search chose this cycle's move.
  Cycle.prototype.duel = function () {
    var c = this, enemy = nearestEnemy(c);
    if (!enemy) return c.fill();                       // the victory lap
    // The enemy's head is the cell it has already claimed.
    var ex = enemy.cx + STEP[enemy.h][0], ez = enemy.cz + STEP[enemy.h][1];
    bystanders = cycles.filter(function (o) { return o.alive && o !== c && o !== enemy; })
      .map(function (o) { return (o.cz + STEP[o.h][1]) * N + o.cx + STEP[o.h][0]; })
      .filter(function (k) { return k >= 0 && k < N * N; });
    voronoi(c.cx, c.cz, ex, ez, 2 * N);
    if (!voronoiMet) return c.fill();                  // walled apart: make it last
    if (Math.abs(ex - c.cx) + Math.abs(ez - c.cz) > DUEL_RANGE) {
      // No duel yet: ride like the others, unless room is getting short.
      return reach(c.cx + STEP[c.h][0], c.cz + STEP[c.h][1], TIGHT) < TIGHT ? c.fill() : false;
    }

    var moves = [c.h, (c.h + 3) % 4, (c.h + 1) % 4].filter(function (h) {
      return open(c.cx + STEP[h][0], c.cz + STEP[h][1]);
    });
    if (!moves.length) return false;
    var started = performance.now();
    deadline = started + SEARCH_MS;
    var chosen = null;
    for (var depth = 1; depth <= 9; depth += 2) {      // ends on the enemy's reply
      aborted = false;
      var bestH = null, bestV = -Infinity;
      for (var i = 0; i < moves.length; i++) {
        var h = moves[i], x = c.cx + STEP[h][0], z = c.cz + STEP[h][1], k = z * N + x;
        grid[k] = MARK;
        var v = minimax(x, z, ex, ez, depth, -Infinity, Infinity, false);
        grid[k] = 0;
        if (aborted) break;
        // Beside the enemy's head, it could take the same cell at the same
        // moment: a head-on crash the alternating search cannot see.
        if (Math.abs(x - ex) + Math.abs(z - ez) === 1) v -= WIN / 2;
        if (h === c.h) v += 0.5;                        // ties: keep going
        if (v > bestV) { bestV = v; bestH = h; }
      }
      if (aborted) break;
      chosen = bestH;
      c.searchDepth = depth + 1;
      moves.sort(function (a, b) { return (b === chosen) - (a === chosen); });   // best first next time
    }
    searchStats.searches++;
    searchStats.ms += performance.now() - started;
    if (chosen === null) return false;
    c.turnTo(chosen);
    return true;
  };

  Cycle.prototype.fill = function () {
    var c = this, best = null;
    [c.h, (c.h + 3) % 4, (c.h + 1) % 4].forEach(function (h) {
      var x = c.cx + STEP[h][0], z = c.cz + STEP[h][1];
      if (!open(x, z)) return;
      var o = { h: h, area: reach(x, z, N * N), walls: walls(x, z) };
      if (!best || o.area > best.area || (o.area === best.area && o.walls > best.walls)) best = o;
    });
    if (!best) return false;
    c.turnTo(best.h);
    return true;
  };

  // ── Derezzing ───────────────────────────────────────────────────────────
  var crashes = [];                                    // recent, for the camera

  Cycle.prototype.crash = function () {
    this.alive = false;
    this.derez = { t: 0, spin: this.root.userData.parts.map(function () {
      return {
        v: new THREE.Vector3((Math.random() - 0.5) * 8, 3 + Math.random() * 4, (Math.random() - 0.5) * 8),
        r: new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).multiplyScalar(8),
      };
    }) };
    this.root.userData.pool.visible = this.root.userData.marker.visible = false;
    this.ring.visible = this.flare.visible = true;
    crashes.push({ x: this.x(), z: this.z(), until: now + 2500 });
    endRoundIfDecided();
  };

  Cycle.prototype.animateDerez = function (dt) {
    var d = this.derez;
    d.t += dt;
    this.root.userData.parts.forEach(function (p, i) {
      var s = d.spin[i];
      s.v.y -= 9 * dt;
      p.position.addScaledVector ? p.position.addScaledVector(s.v, dt)
                                 : p.position.add(s.v.clone().multiplyScalar(dt));
      p.rotation.x += s.r.x * dt; p.rotation.y += s.r.y * dt; p.rotation.z += s.r.z * dt;
      p.material.opacity = Math.max(0, 1 - d.t / 1.2);
    });
    var at = new THREE.Vector3(this.x(), 1, this.z());
    this.ring.position.copy(at);
    this.flare.position.copy(at);
    var r = Math.min(1, d.t / 0.9);
    this.ring.scale.set(4 + r * 30, 4 + r * 30, 1);
    this.ring.material.opacity = 1 - r;
    var f = Math.min(1, d.t / 0.5);
    this.flare.scale.set(3 + f * 22, 3 + f * 22, 1);
    this.flare.material.opacity = 0.9 * (1 - f);
    // The ribbon lingers, then fades, and its cells are open again.
    this.material.opacity = Math.max(0, 1 - Math.max(0, d.t - 0.8) / 1.2);
    if (d.t > 2 && this.trail.visible) {
      this.trail.visible = this.live.visible = this.root.visible = false;
      this.ring.visible = this.flare.visible = false;
      var mark = this.id + 1;
      for (var k = 0; k < grid.length; k++) if (grid[k] === mark) grid[k] = 0;
    }
  };

  // ── Rounds ──────────────────────────────────────────────────────────────
  var score = { clu: 0, program: 0 }, roundOver = 0, now = 0, banner = "";

  function sides() {
    var alive = {};
    cycles.forEach(function (c) { if (c.alive) alive[c.side] = true; });
    return Object.keys(alive);
  }

  function endRoundIfDecided() {
    if (roundOver) return;
    var left = sides();
    if (left.length > 1) return;
    roundOver = now + 4000;
    if (left.length === 1) {
      score[left[0]]++;
      banner = TEAM[left[0]].name + (left[0] === "clu" ? " WINS" : " WIN");
    } else {
      banner = "ALL DEREZZED";
    }
  }

  function newRound() {
    grid.fill(0);
    roundOver = 0;
    banner = "";
    crashes.length = 0;
    // Clu's side starts at the south end heading north, the programs at the
    // north end heading south, in staggered lanes.
    var lanes = [-40, -5, 30], jitter = function () { return (Math.random() - 0.5) * 8; };
    // Lanes are dealt out afresh each round, so no rider keeps an edge.
    var deal = { clu: [0, 1, 2], program: [0, 1, 2] };
    Object.keys(deal).forEach(function (side) { deal[side].sort(function () { return Math.random() - 0.5; }); });
    cycles.forEach(function (c) {
      var k = deal[c.side].pop(), south = c.side === "clu";
      var x = (south ? lanes[k] : -lanes[k]) + jitter();
      c.spawn(cellOf(x), cellOf(south ? 80 : -80), south ? 0 : 2);
    });
    focusUntil = 0;
  }

  ["clu", "clu", "clu", "program", "program", "program"].forEach(function (side, i) {
    var c = new Cycle(i, TEAM[side]);
    c.side = side;
    c.champion = i % 3 === 0;                          // one per side
    cycles.push(c);
  });

  // ── Camera ──────────────────────────────────────────────────────────────
  var camera = new THREE.PerspectiveCamera(40, window.innerWidth / window.innerHeight, 1, 3000);
  var ELEVATION = 0.98;                 // about 56 degrees above the horizon
  var MIN_DIST = 32, MAX_DIST = 120, PAD = 10, LEAD = 1.0;
  var view = { yaw: 0, x: 0, z: 0, dist: 150 }, focus = [], focusUntil = 0;

  // Pick what to watch: the closest pair of enemies and anyone near them;
  // once a round is decided, the survivors. Held a few seconds at a time so
  // the camera is not pulled about.
  function chooseFocus() {
    var alive = cycles.filter(function (c) { return c.alive; });
    if (!alive.length) return [];
    var best = null, bestD = Infinity;
    alive.forEach(function (a) {
      alive.forEach(function (b) {
        if (a.side === b.side) return;
        var d = Math.hypot(a.x() - b.x(), a.z() - b.z());
        if (d < bestD) { bestD = d; best = [a, b]; }
      });
    });
    if (!best) return alive;
    var mx = (best[0].x() + best[1].x()) / 2, mz = (best[0].z() + best[1].z()) / 2;
    return alive.filter(function (c) {
      return c === best[0] || c === best[1] || Math.hypot(c.x() - mx, c.z() - mz) < 45;
    });
  }

  // The shot that fits a set of points: its centre and camera distance.
  function fit(pts, yaw) {
    var ax = Math.cos(yaw), az = -Math.sin(yaw);          // screen right
    var ix = -Math.sin(yaw), iz = -Math.cos(yaw);         // screen up (into the scene)
    var lo = [1e9, 1e9], hi = [-1e9, -1e9];
    pts.forEach(function (p) {
      var a = p[0] * ax + p[1] * az, i = p[0] * ix + p[1] * iz;
      lo[0] = Math.min(lo[0], a); hi[0] = Math.max(hi[0], a);
      lo[1] = Math.min(lo[1], i); hi[1] = Math.max(hi[1], i);
    });
    var ca = (lo[0] + hi[0]) / 2, ci = (lo[1] + hi[1]) / 2;
    var halfA = (hi[0] - lo[0]) / 2 + PAD, halfI = (hi[1] - lo[1]) / 2 + PAD;
    var vt = Math.tan(camera.fov * Math.PI / 360), ht = vt * camera.aspect;
    var dist = Math.max(halfA / ht, halfI * Math.sin(ELEVATION) / vt);
    return { x: ca * ax + ci * ix, z: ca * az + ci * iz, dist: Math.max(MIN_DIST, dist) };
  }

  // Frame the focus, closest to the current view first, taking in each
  // further cycle only while the shot still fits within MAX_DIST. When the
  // duel is too spread out to show whole, the camera stays with one side
  // of it rather than showing the empty ground between.
  function frame(yaw) {
    var subjects = focus.filter(function (c) { return c.alive; }).map(function (c) {
      var v = SPEED * LEAD;
      return [[c.x(), c.z()], [c.x() + STEP[c.h][0] * v, c.z() + STEP[c.h][1] * v]];
    });
    crashes.forEach(function (k) { if (k.until > now) subjects.push([[k.x, k.z]]); });
    if (!subjects.length) return null;
    subjects.sort(function (a, b) {
      return Math.hypot(a[0][0] - view.x, a[0][1] - view.z) - Math.hypot(b[0][0] - view.x, b[0][1] - view.z);
    });
    var pts = subjects[0].slice(), shot = fit(pts, yaw);
    for (var i = 1; i < subjects.length; i++) {
      var wider = fit(pts.concat(subjects[i]), yaw);
      if (wider.dist > MAX_DIST) continue;
      pts = pts.concat(subjects[i]);
      shot = wider;
    }
    shot.dist = Math.min(MAX_DIST, shot.dist);
    return shot;
  }

  function aim(dt) {
    var lost = focus.some(function (c) { return !c.alive; });
    if (now > focusUntil || lost || !focus.length) {
      focus = chooseFocus();
      focusUntil = now + 3000;
    }
    view.yaw += dt * 0.025;                               // a slow turn
    var want = frame(view.yaw);
    if (!want) return;
    var follow = 1 - Math.exp(-dt * 1.4);
    // Pull back quickly so nothing leaves the frame; close in gently.
    var zoom = 1 - Math.exp(-dt * (want.dist > view.dist ? 2.5 : 0.6));
    view.x += (want.x - view.x) * follow;
    view.z += (want.z - view.z) * follow;
    view.dist += (want.dist - view.dist) * zoom;
  }

  function place() {
    var e = view.elevation || ELEVATION, back = view.dist * Math.cos(e);
    camera.position.set(view.x + Math.sin(view.yaw) * back, view.dist * Math.sin(e),
                        view.z + Math.cos(view.yaw) * back);
    camera.lookAt(new THREE.Vector3(view.x, 0, view.z));
  }

  // For tuning from a console: set hold, x, z, dist, yaw or elevation.
  window.encomView = function () { return view; };
  window.encomCycles = cycles;

  // ── Scoreboard ──────────────────────────────────────────────────────────
  var board = document.getElementById("board");
  function drawBoard() {
    if (!board) return;
    function pips(side) {
      return cycles.filter(function (c) { return c.side === side; }).map(function (c) {
        return '<i class="' + side + (c.champion ? " champ" : "") + (c.alive ? "" : " out") + '"></i>';
      }).join("");
    }
    board.innerHTML =
      '<span class="clu">' + TEAM.clu.name + "</span>" + pips("clu") +
      '<b>' + score.clu + " : " + score.program + "</b>" +
      pips("program") + '<span class="program">' + TEAM.program.name + "</span>" +
      (banner ? '<div class="banner">' + banner + "</div>" : "");
  }

  // ── Loop ────────────────────────────────────────────────────────────────
  var clock = new THREE.Clock(), boardKey = "";

  function update(dt) {
    now += dt * 1000;
    cycles.forEach(function (c) { if (c.alive) c.move(dt); });
    cycles.forEach(function (c) {
      var d = c.root.userData;
      if (c.alive || !c.derez) {
        // Swing the body round on turns rather than snapping.
        var want = -c.h * Math.PI / 2, diff = Math.atan2(Math.sin(want - c.yaw), Math.cos(want - c.yaw));
        c.yaw += diff * Math.min(1, dt * 22);
        c.root.rotation.y = c.yaw;
        c.root.position.set(c.x(), 0, c.z());
        // The stretch being laid runs from the last corner to the rear wheel.
        var len = Math.max(0, Math.abs(c.x() - c.from[0]) + Math.abs(c.z() - c.from[1]) - 1);
        c.live.position.set(c.from[0], 0, c.from[1]);
        c.live.rotation.y = -c.h * Math.PI / 2;
        c.live.scale.set(1, 1, Math.max(0.001, len));
      } else {
        c.animateDerez(dt);
      }
    });
    if (roundOver && now > roundOver) newRound();
    if (!view.hold) aim(dt);
    place();
    var key = score.clu + "/" + score.program + "/" + banner + "/" +
              cycles.map(function (c) { return c.alive ? 1 : 0; }).join("");
    if (key !== boardKey) { boardKey = key; drawBoard(); }
  }

  function loop() {
    requestAnimationFrame(loop);
    update(Math.min(clock.getDelta(), 0.05));
    renderer.render(scene, camera);
  }

  window.addEventListener("resize", function () {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
  });

  // For testing from a console: run the match n frames ahead without drawing.
  window.encomStep = function (n) { for (var i = 0; i < n; i++) update(1 / 60); };
  window.encomPeek = function (cx, cz) { return grid[cz * N + cx]; };

  newRound();
  loop();

  // ── Screensaver ─────────────────────────────────────────────────────────
  if (!screensaver) return;
  document.documentElement.classList.add("screensaver");

  var dismissed = false;
  function dismiss() {
    if (dismissed) return;
    dismissed = true;
    fetch("/dismiss", { method: "POST", keepalive: true }).catch(function () {});
  }
  // A window appearing under a stationary pointer can emit a synthetic
  // mousemove, so ignore input for a moment and require a real movement.
  var armedAt = Date.now() + 1500, origin = null;
  function armed() { return Date.now() > armedAt; }
  ["keydown", "mousedown", "wheel", "touchstart", "contextmenu"].forEach(function (type) {
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
