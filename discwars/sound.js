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

  var BPM = 120;
  var SPB = 60 / BPM;              // seconds per beat: 0.5
  var STEP = SPB / 2;              // the grid everything snaps to: eighths
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
  // Where a throw is aimed sets where its run starts, and a block answers by
  // walking back down: the line follows the fight rather than decorating it.
  var ROOT = 33;                                   // A1
  var AIM_STEP = [7, 3, 0];                        // high, body, low

  function run(t0, e) {
    var beats = e.kind === "block" ? 4 : 2;        // a measure, or half of one
    var n = beats * 2;                             // in eighths
    var base = ROOT + (e.team === 0 ? 12 : 0) + (AIM_STEP[e.aim] || 0);
    var dir = e.kind === "block" ? -1 : 1;         // blocks come back down
    var gain = e.kind === "block" ? 0.16 : 0.13;
    for (var i = 0; i < n; i++) {
      pluck(t0 + i * STEP, base + dir * i, STEP * 0.85, e.kind, gain);
    }
    live.push(t0 + n * STEP);
  }

  // ── The clock ─────────────────────────────────────────────────────────
  function schedule() {
    var now = ctx.currentTime;
    while (live.length && live[0] < now) live.shift();
    while (stepTime < now + LOOKAHEAD) {
      var eighth = step % 8;                       // two beats to the bar here
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

  window.DiscWarsSound = {
    get on() { return running; },
    bpm: BPM,

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
      if (ctx.state === "suspended") ctx.resume();
      step = 0;
      stepTime = ctx.currentTime + 0.08;
      pending = []; live = [];
      running = true;
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

    // Called by the fight. Held until the next slot on the grid.
    play: function (kind, info) {
      if (!running || !ctx) return;
      pending.push({ kind: kind, team: (info && info.team) || 0,
                     aim: info && info.aim != null ? info.aim : 1 });
    }
  };
})();
