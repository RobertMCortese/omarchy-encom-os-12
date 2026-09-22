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
    var n = Math.floor(ctx.sampleRate * 0.4);
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

  // Degree d of the scale, carrying on into the octave above as it runs out.
  function degree(d) {
    var n = SCALE.length;
    var oct = Math.floor(d / n), i = d - oct * n;
    if (i < 0) { i += n; oct -= 1; }
    return SCALE[i] + 12 * oct;
  }

  function run(t0, e) {
    var beats = e.kind === "block" ? 4 : 2;        // a measure, or half of one
    var n = beats * 2;                             // in eighths
    var base = ROOT + (e.team === 0 ? 12 : 0);
    var from = AIM_STEP[e.aim] || 0;
    var dir = e.kind === "block" ? -1 : 1;         // blocks come back down
    var gain = e.kind === "block" ? 0.16 : 0.13;
    for (var i = 0; i < n; i++) {
      pluck(t0 + i * STEP, base + degree(from + dir * i), STEP * 0.85, e.kind, gain);
    }
    live.push(t0 + n * STEP);
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
      // Anything the fight did since the last slot starts on this one.
      while (pending.length && live.length < MAX_VOICES) run(stepTime, pending.shift());
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
      pending = []; live = [];
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
      else if (kind === "round") wantBpm = BASE_BPM;
    },

    // Called by the fight. Held until the next slot on the grid.
    play: function (kind, info) {
      if (!running || !ctx) return;
      pending.push({ kind: kind, team: (info && info.team) || 0,
                     aim: info && info.aim != null ? info.aim : 1 });
    }
  };
})();
