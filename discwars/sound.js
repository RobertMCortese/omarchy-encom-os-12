// The fight, as a sequencer.
//
// A four-on-the-floor kick with a snare on two and four holds 120 BPM under
// everything. On top of that the fight plays itself: every throw fires a
// chromatic run half a measure long, every block a whole one. Nothing is
// composed -- the arrangement is whatever the fighters happen to do, and a
// 3v3 with three exchanges in the air sounds like a busier bar than a duel
// does.
//
// The one thing that makes this music rather than clatter is that events do
// not play when they happen. A throw lands wherever it lands, and its run is
// held until the next eighth-note on the grid, so it falls on the beat. At
// 120 BPM that wait is never more than a quarter second, which reads as
// tight rather than late, and the disc is still in the air either way.
//
// Everything is made from oscillators and one buffer of noise: no samples,
// nothing fetched, a few hundred lines. Times come from the audio clock and
// are scheduled ahead of playback -- setTimeout is far too loose to sequence
// from, and would swing every beat audibly.
(function () {
  "use strict";

  var BASE_BPM = 120;
  var PER_LOSS = 10;               // every fighter out winds it up this much
  var MAX_BPM = 200;
  // The tempo is not fixed: each fighter knocked out of the round takes it up
  // ten, and a new round drops it back. A 3v3 worn down to a win runs 120 to
  // as much as 170, so the last exchanges are the fastest, and then it starts
  // over. A change waits for the top of a bar rather than landing wherever
  // the fight happens to put it -- stepping tempo mid-phrase smears the run
  // that is already playing, and a bar line is where a tempo change belongs.
  var bpm = BASE_BPM, wantBpm = BASE_BPM;
  var STEP = 60 / BASE_BPM / 2;    // the grid everything snaps to: eighths
  var LOOKAHEAD = 0.12;            // seconds of audio scheduled in advance
  var TICK = 25;                   // ms between runs of the scheduler
  var MAX_VOICES = 5;              // runs in the air at once, before dropping

  var ctx = null, master = null, comp = null, noise = null;
  var step = 0, stepTime = 0, timer = null;
  var pending = [];                // events waiting for their slot
  var live = [];                   // end times of runs currently sounding
  var running = false;

  function mtof(m) { return 440 * Math.pow(2, (m - 69) / 12); }

  function makeNoise() {
    var n = Math.floor(ctx.sampleRate * 2.0);   // long enough for a crash to ring out
    var buf = ctx.createBuffer(1, n, ctx.sampleRate);
    var d = buf.getChannelData(0);
    for (var i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    return buf;
  }

  // ── The kit ───────────────────────────────────────────────────────────
  function kick(t) {
    var o = ctx.createOscillator(), g = ctx.createGain();
    o.type = "sine";
    o.frequency.setValueAtTime(150, t);
    o.frequency.exponentialRampToValueAtTime(44, t + 0.09);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.95, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.30);
    o.connect(g); g.connect(master);
    o.start(t); o.stop(t + 0.32);
  }

  function snare(t) {
    // Noise for the rattle, a short tuned body under it.
    var s = ctx.createBufferSource(), hp = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = noise;
    hp.type = "highpass"; hp.frequency.value = 1500;
    g.gain.setValueAtTime(0.45, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.17);
    s.connect(hp); hp.connect(g); g.connect(master);
    s.start(t); s.stop(t + 0.2);

    var o = ctx.createOscillator(), g2 = ctx.createGain();
    o.type = "triangle";
    o.frequency.setValueAtTime(200, t);
    o.frequency.exponentialRampToValueAtTime(150, t + 0.08);
    g2.gain.setValueAtTime(0.32, t);
    g2.gain.exponentialRampToValueAtTime(0.0001, t + 0.11);
    o.connect(g2); g2.connect(master);
    o.start(t); o.stop(t + 0.13);
  }

  // Three toms, tuned low to high, each falling a little as it goes. Which
  // one a block or a bounce gets is picked at random, so a rally comes out
  // as a fill rather than the same note over and over.
  var TOMS = [[168, 96], [232, 134], [316, 188]];
  function tom(t, which) {
    var f = TOMS[which % TOMS.length];
    var o = ctx.createOscillator(), g = ctx.createGain();
    o.type = "triangle";
    o.frequency.setValueAtTime(f[0], t);
    o.frequency.exponentialRampToValueAtTime(f[1], t + 0.2);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.42, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.4);
    o.connect(g); g.connect(master);
    o.start(t); o.stop(t + 0.42);
  }

  // A crash, for a ring going out from under somebody: wide, bright, and
  // left to ring for a bar and a half.
  function crash(t) {
    var s = ctx.createBufferSource(), hp = ctx.createBiquadFilter(),
        bp = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = noise;
    hp.type = "highpass"; hp.frequency.value = 3800;
    bp.type = "bandpass"; bp.frequency.value = 7600; bp.Q.value = 0.55;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.40, t + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 1.5);
    s.connect(hp); hp.connect(bp); bp.connect(g); g.connect(master);
    s.start(t); s.stop(t + 1.55);
  }

  // A ride, for a fighter broken up: tighter than the crash, and metallic
  // rather than white -- a stack of squares at no sensible interval to each
  // other, which is how a cymbal was got out of an analogue box and is still
  // the cheapest way to make metal out of oscillators.
  var RIDE = [1047, 1481, 1899, 2411, 2917, 3413];
  function ride(t) {
    var hp = ctx.createBiquadFilter(), g = ctx.createGain();
    hp.type = "highpass"; hp.frequency.value = 5600;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.26, t + 0.003);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 1.0);
    hp.connect(g); g.connect(master);
    for (var i = 0; i < RIDE.length; i++) {
      var o = ctx.createOscillator();
      o.type = "square";
      o.frequency.value = RIDE[i];
      o.connect(hp);
      o.start(t); o.stop(t + 1.02);
    }
    var s = ctx.createBufferSource();          // a little air over the metal
    s.buffer = noise;
    s.connect(hp);
    s.start(t); s.stop(t + 1.02);
  }

  // ── The runs ──────────────────────────────────────────────────────────
  // One plucked note: a saw through a filter that closes as it decays, which
  // is most of what makes a line like this sound the way it does.
  function pluck(t, midi, dur, kind, gain) {
    var f0 = mtof(midi);
    var o = ctx.createOscillator(), lp = ctx.createBiquadFilter(), g = ctx.createGain();
    o.type = kind === "block" ? "square" : "sawtooth";
    o.frequency.value = f0;
    lp.type = "lowpass";
    lp.Q.value = 9;
    lp.frequency.setValueAtTime(Math.min(f0 * 7, 9000), t);
    lp.frequency.exponentialRampToValueAtTime(Math.max(f0 * 1.4, 120), t + dur * 0.9);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain, t + 0.006);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(lp); lp.connect(g); g.connect(master);
    o.start(t); o.stop(t + dur + 0.02);
  }

  // Programs sit an octave above sentinels, so who is doing what is audible.
  // Where a throw is aimed sets which degree its run starts on, and a block
  // answers by walking back down: the line follows the fight rather than
  // decorating it.
  //
  // D# natural minor, less its fifth: D# E# F# G# B C#. Runs step through
  // these rather than through semitones, so a line stays in key however many
  // of them are going at once -- which matters here, because in a 3v3 there
  // are often three.
  var ROOT = 27;                                   // D#1
  var SCALE = [0, 2, 3, 5, 8, 10];                 // D# E# F# G# B C#
  var AIM_STEP = [4, 2, 0];                        // high, body, low: which degree to start on

  // Where each side's notes are allowed to sit. A run walks as far as its
  // figure takes it, and a long one walks a long way -- a thirteen-note
  // block descending from D#1 ended up under 5 Hz, which is ten of its
  // thirteen notes spent below anything anyone can hear. Folding by octaves
  // keeps the shape of the line and puts it back in the room.
  // The figures repeat, because a name always gives the same one. So the
  // ground they stand on moves instead: every throw shifts the key a
  // semitone, up or down at random, never further than two either way, and
  // every fourth throw drops it back to where it started. Four throws is
  // about a bar or two of fighting, so the colour keeps changing without
  // ever wandering off. Only the notes move -- the kit is where it was, and
  // a drum that followed the key around would stop sounding like a drum.
  var TRANS_MAX = 2, TRANS_EVERY = 4;
  var trans = 0, transStep = 0;
  function stepKey() {
    if (transStep >= TRANS_EVERY) { trans = 0; transStep = 0; return; }
    var dir = Math.random() < 0.5 ? -1 : 1;
    if (trans + dir > TRANS_MAX || trans + dir < -TRANS_MAX) dir = -dir;
    trans += dir;
    transStep++;
  }

  var RANGE = [[45, 78], [31, 64]];                // programs, sentinels
  function fold(m, team) {
    var r = RANGE[team] || RANGE[1];
    while (m < r[0]) m += 12;
    while (m > r[1]) m -= 12;
    return m;
  }

  // Degree d of the scale, carrying on into the octave above as it runs out.
  function degree(d) {
    var n = SCALE.length;
    var oct = Math.floor(d / n), i = d - oct * n;
    if (i < 0) { i += n; oct -= 1; }
    return SCALE[i] + 12 * oct;
  }

  // ── A fighter's figure ────────────────────────────────────────────────
  // Every run is an odd number of notes -- 7, 9, 11 or 13 -- played three,
  // a breath, then the rest. Which length, the walk through the scale, and
  // the rhythm all come from the fighter's own name, so GREP throws the same
  // figure every time and a name that comes back in a later round brings its
  // sound with it. Nothing is stored: the name is hashed and the figure falls
  // out of the bits, so the same name always gives the same phrase.
  //
  // The rhythm is not an even run of sixteenths, because an even run of
  // sixteenths is the one thing this style never does. Writing about Daft
  // Punk's parts, Attack Magazine puts the hallmark as almost every
  // consecutive note having a different length, with the emphasis moving
  // around the sixteenths of the bar rather than sitting on the same ones,
  // and gaps left on purpose. So a figure carries three cells -- where the
  // notes fall, how long each rings, and where it steps to -- of lengths
  // 4, 3 and 3, which come back into phase only every twelve notes. Nothing
  // here is anybody's melody; it is a way of spacing notes.
  var LENGTHS = [7, 9, 11, 13];
  var MOVES = [1, 1, 2, -1, 1, 2, -2, 3];          // degree steps to choose between
  var GAPS = [1, 2, 1, 1, 3, 2, 1, 2];             // sixteenths from one onset to the next
  var HOLDS = [0.55, 1.35, 0.8, 0.5, 1.7, 0.9];    // how long each note rings, in sixteenths
  var OCTS = [0, 0, 4, 3, 5, 0];                   // every nth note up an octave, 0 for never
  var figures = {};

  function figure(name) {
    var key = name || "";
    if (figures[key]) return figures[key];
    var h = 2166136261;
    for (var i = 0; i < key.length; i++) {
      h ^= key.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    h = h >>> 0;
    var cell = [], gaps = [], holds = [];
    for (var k = 0; k < 3; k++) cell.push(MOVES[(h >>> (5 + k * 3)) % MOVES.length]);
    for (var m = 0; m < 4; m++) gaps.push(GAPS[(h >>> (2 + m * 5)) % GAPS.length]);
    for (var q = 0; q < 3; q++) holds.push(HOLDS[(h >>> (7 + q * 4)) % HOLDS.length]);
    var f = { n: LENGTHS[h % LENGTHS.length], cell: cell, gaps: gaps, holds: holds,
              oct: OCTS[(h >>> 17) % OCTS.length] };
    figures[key] = f;
    return f;
  }

  function run(t0, e) {
    var fig = figure(e.name);
    var six = STEP / 2;                            // the sixteenth everything is measured in
    var base = ROOT + (e.team === 0 ? 12 : 0);
    var dir = e.kind === "block" ? -1 : 1;         // blocks come back down
    var gain = e.kind === "block" ? 0.15 : 0.12;
    var d = AIM_STEP[e.aim] || 0;
    var t = t0;
    for (var i = 0; i < fig.n; i++) {
      if (i === 3) t += six * 2;                   // three, a breath, then the rest
      var gap = fig.gaps[i % fig.gaps.length];
      var hold = fig.holds[i % fig.holds.length];
      // A note that has had room before it lands harder, which is what puts
      // the emphasis somewhere different each time round rather than on the
      // beat every time.
      var hit = gain * (gap >= 2 ? 1.18 : 0.88);
      var up = (fig.oct && (i + 1) % fig.oct === 0) ? 12 : 0;
      pluck(t, fold(base + degree(d), e.team) + up + trans, six * hold, e.kind, hit);
      d += dir * fig.cell[i % fig.cell.length];
      t += six * gap;
    }
    live.push(t);
  }

  // ── Hanging on ────────────────────────────────────────────────────────
  // A fighter over the edge holds on until it climbs back or is finished
  // off, and for as long as it does its figure's first note is arpeggiated
  // underneath everything: the note, its octave, and the degree between
  // them, quietly, once an eighth. It is the one sound in the arena that is
  // held rather than struck, so it reads as somebody still out there.
  var hanging = {};
  var hangN = 0;

  function hangNote(t, who, k) {
    var fig = figure(who.name);
    var start = AIM_STEP[1];                        // where its figure begins
    var step3 = [0, 3, 6][k % 3];                   // the note, a third up, its octave
    var base = ROOT + (who.team === 0 ? 12 : 0);
    var m = fold(base + degree(start + step3), who.team) + trans;
    var o = ctx.createOscillator(), lp = ctx.createBiquadFilter(), g = ctx.createGain();
    var f0 = mtof(m);
    o.type = "triangle";                            // softer than the runs, so it sits under
    o.frequency.value = f0;
    lp.type = "lowpass"; lp.Q.value = 4;
    lp.frequency.setValueAtTime(Math.min(f0 * 5, 7000), t);
    lp.frequency.exponentialRampToValueAtTime(Math.max(f0 * 1.6, 140), t + 0.16);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.075, t + 0.006);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
    o.connect(lp); lp.connect(g); g.connect(master);
    o.start(t); o.stop(t + 0.24);
  }

  // ── The clock ─────────────────────────────────────────────────────────
  function schedule() {
    var now = ctx.currentTime;
    while (live.length && live[0] < now) live.shift();
    while (stepTime < now + LOOKAHEAD) {
      var eighth = step % 8;                       // eight eighths to the bar
      if (eighth === 0 && wantBpm !== bpm) {       // tempo moves on the bar line
        bpm = wantBpm;
        STEP = 60 / bpm / 2;
      }
      if (eighth % 2 === 0) {
        kick(stepTime);                            // every beat: the pulse
        var b = eighth / 2;
        if (b === 1 || b === 3) snare(stepTime);   // two and four
      }
      // Anybody still hanging holds their note under everything else.
      for (var w in hanging) if (hanging.hasOwnProperty(w)) hangNote(stepTime, hanging[w], hangN);
      hangN++;

      // Where a thing is allowed to come in. A throw waits for a beat and a
      // block for a half bar, so a line never starts in the middle of one --
      // that is the difference between a part and a pile of events. The kit
      // stays on the eighths, where it can answer off the beat.
      var onBeat = (step % 2) === 0;
      var onHalf = (step % 4) === 0;
      var fired = 0;
      for (var pi = 0; pi < pending.length && fired < 8; ) {
        var e = pending[pi];
        var due = e.kind === "throw" ? onBeat : e.kind === "block" ? onHalf : true;
        if (!due) { pi++; continue; }
        pending.splice(pi, 1);
        fired++;
        if (e.kind === "throw" || e.kind === "block") {
          if (e.kind === "throw") stepKey();       // a block stays in the key it answers
          if (live.length < MAX_VOICES) run(stepTime, e);
          if (e.kind === "block") tom(stepTime, Math.floor(Math.random() * 3));
        } else if (e.kind === "bounce") {
          tom(stepTime, Math.floor(Math.random() * 3));
        } else if (e.kind === "ring") {
          crash(stepTime);
        } else if (e.kind === "derez") {
          ride(stepTime);
        }
      }
      if (pending.length > 24) pending.length = 0; // a pile-up is not music
      step++;
      stepTime += STEP;
    }
  }

  // A browser will not resume an audio context in a background tab, and only
  // resumes one at all off a real interaction. Rather than deciding after a
  // fixed wait that it has refused -- resume is asynchronous, and that wait
  // can easily be the shorter of the two -- keep asking: whenever the tab
  // comes to the front, and on the next click anywhere. Once it takes, these
  // do nothing.
  function wake() {
    if (!ctx || ctx.state === "running") return;
    try {
      var r = ctx.resume();
      if (r && r.catch) r.catch(function () { /* still refused; we try again */ });
    } catch (e) { /* same */ }
  }

  var watching = false;
  function watchForPermission() {
    if (watching) return;
    watching = true;
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden && running) wake();
    });
    window.addEventListener("pointerdown", function () { if (running) wake(); }, true);
    window.addEventListener("keydown", function () { if (running) wake(); }, true);
  }

  window.DiscWarsSound = {
    get on() { return running; },
    get bpm() { return bpm; },
    // Whether anything is actually coming out. A browser will not resume an
    // audio context except off a real click, and does not resume one in a
    // background tab at all, so wanting sound and having it are two
    // different questions and a control that conflates them lies.
    get live() { return running && !!ctx && ctx.state === "running"; },

    start: function () {
      var AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      if (!ctx) {
        ctx = new AC();
        comp = ctx.createDynamicsCompressor();     // glue, and a lid on pile-ups
        comp.threshold.value = -14;
        comp.ratio.value = 6;
        comp.attack.value = 0.004;
        comp.release.value = 0.12;
        master = ctx.createGain();
        master.gain.value = 0.55;
        master.connect(comp); comp.connect(ctx.destination);
        noise = makeNoise();
      }
      wake();
      step = 0;
      bpm = wantBpm = BASE_BPM;
      STEP = 60 / bpm / 2;
      stepTime = ctx.currentTime + 0.08;
      pending = []; live = []; hanging = {}; hangN = 0;
      trans = 0; transStep = 0;
      running = true;
      watchForPermission();
      if (timer) clearInterval(timer);
      timer = setInterval(schedule, TICK);
      schedule();
      return true;
    },

    stop: function () {
      running = false;
      if (timer) { clearInterval(timer); timer = null; }
      pending = [];
      if (ctx && ctx.state === "running") ctx.suspend();
    },

    // What the fight has done to the shape of the round, rather than a note:
    // a fighter out winds the tempo up, a new round puts it back.
    mark: function (kind) {
      if (kind === "out") wantBpm = Math.min(MAX_BPM, wantBpm + PER_LOSS);
      else if (kind === "round") { wantBpm = BASE_BPM; hanging = {}; }
    },

    // Called by the fight. Held until the next slot on the grid.
    play: function (kind, info) {
      if (!running || !ctx) return;
      if (kind === "hang") {
        hanging[info.name] = { name: info.name, team: info.team };
        return;
      }
      if (kind === "unhang") { delete hanging[info.name]; return; }
      if (kind === "round") {                       // nobody hanging, back to the root
        hanging = {}; trans = 0; transStep = 0;
        return;
      }
      pending.push({ kind: kind, team: (info && info.team) || 0,
                     aim: info && info.aim != null ? info.aim : 1,
                     name: (info && info.name) || "" });   // whose figure to play
    }
  };
})();
