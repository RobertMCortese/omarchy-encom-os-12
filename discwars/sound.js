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
  // One line a side, and the side is busy until its figure has finished.
  // Naming the speaker was not enough on its own: a figure runs about five
  // seconds and a fighter throws oftener than that, so the same program was
  // laying figures over its own.
  var voiceUntil = [0, 0];
  // Who speaks for the sentinels, what their last throw was aimed at, and
  // whether there is still a round on. The bassline runs off these rather
  // than off a throw, so it keeps going while they are only defending.
  var bassName = "", bassAim = 1, fighting = false;

  var ctx = null, master = null, notes = null, comp = null, noise = null;
  var sounding = [];               // every melodic voice currently ringing
  var step = 0, stepTime = 0, timer = null;
  var pending = [];                // events waiting for their slot
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
  // one a carom gets is not random: the fight says. The first thing a disc
  // hits is the high tom, the second -- or a shield turning it away -- the
  // middle one, and the last, including its arrival back in the hand, the
  // low one. A throw off a wall, past its target, off the glass and home
  // comes out as a descending fill that follows the disc.
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
  // Everything melodic is registered here, because a note that has been
  // scheduled is otherwise beyond reach: the web audio graph will play it
  // whatever happens next, and what happens next may be that the fight it
  // belonged to ended.
  function keep(g, os, end) {
    sounding.push({ g: g, os: os, end: end });
    if (sounding.length > 128) {
      var now = ctx.currentTime;
      sounding = sounding.filter(function (v) { return v.end > now; });
    }
  }

  // Silence, now. A round is over the moment the last of a side falls, and a
  // run still ringing over the result is a fight carrying on after it has
  // been decided. Everything scheduled goes with it, including the notes
  // that had not started yet. The kit plays on: it is the clock, not the
  // argument, and a round should not cost the track its pulse.
  function cutAll() {
    if (!ctx) return;
    var t = ctx.currentTime;
    for (var i = 0; i < sounding.length; i++) {
      var v = sounding[i];
      try {
        v.g.gain.cancelScheduledValues(t);
        v.g.gain.setValueAtTime(Math.max(0.0001, v.g.gain.value), t);
        v.g.gain.linearRampToValueAtTime(0.0001, t + 0.02);   // 20ms, so it does not click
        for (var k = 0; k < v.os.length; k++) {
          try { v.os[k].stop(t + 0.03); } catch (e) { /* already stopped */ }
        }
      } catch (e) { /* node already finished */ }
    }
    sounding = [];
    pending = [];
    voiceUntil = [0, 0];
    hanging = {};
  }

  // ── Six voices ────────────────────────────────────────────────────────
  // A name picks a timbre the same way it picks a figure, so a program
  // sounds like itself for as long as it is in the arena, and a champion
  // that survives into the next round is recognisable before you have read
  // its name. What separates these is mostly how they begin and how they let
  // go rather than which waveform they run on: a bell is a bell because it
  // is struck and then abandoned, and strings are strings because they are
  // never struck at all.
  //
  // Attack, body, release, in all of them. What was here before was an
  // attack of six milliseconds straight into a decay, with the lowpass
  // closing over the same span, so every note was a pluck however long it
  // was told to last and a long note was only a longer beep.
  var VOICES = ["saw", "square", "sine", "strings", "piano", "bell"];

  function cents(f, c) { return f * Math.pow(2, c / 1200); }

  function pluck(t, midi, dur, kind, gain, voice) {
    var f0 = mtof(midi);
    var g = ctx.createGain();
    g.connect(notes);
    var os = [], i;
    var endAt = t + dur;                            // when this note is actually finished

    if (voice === "strings") {
      // Bowed: it arrives rather than starts. Three saws a few cents apart,
      // so the pitch never quite settles, and the filter opens as it swells.
      var atk = Math.min(0.2, dur * 0.5), rel = Math.min(0.55, dur * 0.55);
      var lp = ctx.createBiquadFilter();
      lp.type = "lowpass"; lp.Q.value = 0.9;
      lp.frequency.setValueAtTime(Math.max(f0 * 1.8, 180), t);
      lp.frequency.linearRampToValueAtTime(Math.min(f0 * 6, 5200), t + atk);
      lp.connect(g);
      for (i = 0; i < 3; i++) {
        var so = ctx.createOscillator();
        so.type = "sawtooth";
        so.frequency.value = cents(f0, [-7, 0, 8][i]);
        so.connect(lp); os.push(so);
      }
      var slvl = gain * 0.36;                     // three saws summed: a third each
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(slvl, t + atk);
      g.gain.setValueAtTime(slvl, t + Math.max(atk, dur - rel));
      endAt = t + dur + rel * 0.5;                // and a long tail
      g.gain.exponentialRampToValueAtTime(0.0001, endAt);

    } else if (voice === "piano") {
      // Struck and let go: three partials, the upper ones shorter, so the
      // tone darkens as it falls away the way a struck string does.
      var pg = [1, 0.4, 0.17], pd = [1, 0.55, 0.3];
      for (i = 0; i < 3; i++) {
        var po = ctx.createOscillator(), pgn = ctx.createGain();
        po.type = i === 0 ? "triangle" : "sine";
        po.frequency.value = f0 * (i + 1);
        pgn.gain.setValueAtTime(0.0001, t);
        pgn.gain.exponentialRampToValueAtTime(pg[i], t + 0.004);
        pgn.gain.exponentialRampToValueAtTime(0.0001, t + dur * pd[i] + 0.05);
        endAt = Math.max(endAt, t + dur * pd[i] + 0.05);
        po.connect(pgn); pgn.connect(g); os.push(po);
      }
      g.gain.setValueAtTime(gain * 0.62, t);    // partials sum to about 1.6

    } else if (voice === "bell") {
      // Frequency modulation at an interval that belongs to no scale, which
      // is what makes metal sound like metal. The modulation dies away
      // faster than the note, so it rings clean after it has been hit.
      var car = ctx.createOscillator(), mod = ctx.createOscillator();
      var mg = ctx.createGain();
      car.type = "sine"; car.frequency.value = f0;
      mod.type = "sine"; mod.frequency.value = f0 * 3.47;     // inharmonic on purpose
      mg.gain.setValueAtTime(f0 * 5, t);
      mg.gain.exponentialRampToValueAtTime(f0 * 0.25, t + Math.min(0.5, dur * 0.7));
      mod.connect(mg); mg.connect(car.frequency);
      car.connect(g); os.push(car); os.push(mod);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain * 0.9, t + 0.004);
      endAt = t + dur + 0.25;                     // metal rings on after it is hit
      g.gain.exponentialRampToValueAtTime(0.0001, endAt);

    } else {
      // The three simple ones: a saw to buzz, a square to sound hollow, a
      // sine with nothing in it at all. A body between the attack and the
      // release, and a filter that stays open across it instead of shutting
      // the moment the note is struck.
      var atk2 = 0.006, rel2 = Math.min(0.3, dur * 0.35);
      var body = Math.max(0.004, dur - atk2 - rel2);
      var sus = dur > 0.3 ? 0.8 : 0.4;              // a held note keeps its level; a stab does not
      var o = ctx.createOscillator();
      o.type = voice === "sine" ? "sine" : voice === "square" ? "square" : "sawtooth";
      o.frequency.value = f0;
      if (voice === "sine") {
        o.connect(g);                               // nothing to filter out
      } else {
        var f = ctx.createBiquadFilter();
        f.type = "lowpass"; f.Q.value = 9;
        f.frequency.setValueAtTime(Math.min(f0 * 7, 9000), t);
        f.frequency.exponentialRampToValueAtTime(Math.max(f0 * 2.4, 170), t + atk2 + body);
        f.frequency.exponentialRampToValueAtTime(Math.max(f0 * 1.3, 110), t + dur);
        o.connect(f); f.connect(g);
      }
      os.push(o);
      var lvl = gain * (voice === "sine" ? 1.25 : 1);   // a sine carries less, so lift it
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(lvl, t + atk2);
      g.gain.exponentialRampToValueAtTime(lvl * sus, t + atk2 + body);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    }

    var off = endAt + 0.03;
    for (i = 0; i < os.length; i++) { os[i].start(t); os[i].stop(off); }
    keep(g, os, off);
  }

  // Programs sit an octave above sentinels, so who is doing what is audible.
  // Where a throw is aimed sets which degree its run starts on, and a block
  // answers by walking back down: the line follows the fight rather than
  // decorating it.
  //
  // D# natural minor, all seven. The six originally asked for left out A#,
  // which is the fifth, and a riff of this kind is built on its root and its
  // fifth before anything else -- the textbook acid ostinato is two notes and
  // they are those two. Without one there was nothing for a line to lean on
  // and nowhere for it to come to rest. Take the 7 back out of SCALE to have
  // the six again; everything below is written in degrees and will follow.
  var ROOT = 27;                                   // D#1
  var SCALE = [0, 2, 3, 5, 7, 8, 10];              // D# E# F# G# A# B C#

  // Where each side's notes are allowed to sit. A run walks as far as its
  // figure takes it, and a long one walks a long way -- a thirteen-note
  // block descending from D#1 ended up under 5 Hz, which is ten of its
  // thirteen notes spent below anything anyone can hear. Folding by octaves
  // keeps the shape of the line and puts it back in the room.
  // The figures repeat, because a name always gives the same one. So the
  // ground they stand on moves instead: every throw shifts the whole figure,
  // up or down at random, never further than two either way, and every
  // fourth throw drops it back where it started.
  //
  // It shifts by a DEGREE of the scale, not by a semitone. A semitone was
  // the obvious reading and it was wrong: move a minor scale a semitone and
  // every note of it lands outside the key, and with several fighters at
  // different offsets at once the arena was playing all twelve pitch classes
  // at roughly even weight. There was no key left to hear. A degree moves
  // the figure the same distance to the ear and keeps every note in D# minor,
  // so three fighters going at once still agree about what key they are in.
  // Only the notes move -- the kit is where it was, and a drum that followed
  // the key around would stop sounding like a drum.
  var TRANS_MAX = 2, TRANS_EVERY = 4;
  var trans = 0, transStep = 0;
  function stepKey() {
    if (transStep >= TRANS_EVERY) { trans = 0; transStep = 0; return; }
    var dir = Math.random() < 0.5 ? -1 : 1;
    if (trans + dir > TRANS_MAX || trans + dir < -TRANS_MAX) dir = -dir;
    trans += dir;
    transStep++;
  }

  // Programs carry the tune and sentinels carry the bass, so they are given
  // separate ground to stand on rather than the same figure an octave apart.
  // The two windows do not touch, so nothing either side plays can be mistaken
  // for the other -- and neither can hide inside the other's register.
  // The bass floor is A1 and not the D#1 the root suggests, because a laptop
  // speaker does not reproduce 39Hz and a bassline nobody can hear is not a
  // bassline.
  var RANGE = [[52, 79], [33, 51]];                // programs: melody, sentinels: bass

  // How many octaves a figure has to move to sit inside its side's window.
  // This is worked out ONCE for a whole figure and applied to every note of
  // it. Folding each note where it fell was the last thing making these read
  // as random: a figure straddling the edge of the window had some of its
  // notes shifted an octave and the rest left alone, so a rise came out as a
  // fall and the line was turned inside out mid-phrase. The widest interval
  // inside a cell is a fifth, yet minor sixths were the second commonest
  // thing being played -- there was nowhere else they could have come from.
  function foldShift(m, team) {
    var r = RANGE[team] || RANGE[1], k = 0;
    while (m + k < r[0]) k += 12;
    while (m + k > r[1]) k -= 12;
    return k;
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
  //
  // The pitches are a four-degree cell repeated for the length of the run,
  // and they are absolute degrees rather than steps from wherever the last
  // note happened to land. What was there before added a step each note, so
  // a thirteen-note run was thirteen additions deep by the end and had drifted
  // somewhere unrelated to where it started -- a random walk, which measures
  // out as one: the intervals came out 68% leaps wider than a major third,
  // spread flat across every size. Melodies are mostly steps and they come
  // back. Every cell here starts on the root and leans on the fifth (degree
  // 4) and the third (degree 2), and because it repeats inside the run there
  // is something to recognise the second time it comes round.
  var LENGTHS = [7, 9, 11, 13];
  var CELLS = [                                    // degrees of the scale, repeated
    [0, 0, 4, 2],                                  // root, root, fifth, third
    [0, 4, 3, 2],
    [0, 2, 4, 2],
    [4, 2, 0, 2],
    [0, 0, 2, 0],                                  // insistent on the root
    [0, 1, 2, 4],                                  // stepwise up to the fifth
    [4, 4, 2, 0],
    [0, 2, 0, 4]                                  // root, third, root, fifth
  ];
  // Onsets were averaging 1.63 sixteenths apart, which is about eleven notes
  // to the bar before a second fighter is even counted, and each note rang
  // for 0.59 of the space before the next -- so there was a silence between
  // every pair of them and nothing ever overlapped. Twice the room now, and
  // the notes that matter ring into the ones that follow.
  // A bassline is not a tune in a lower register. It holds the root and
  // answers it, so its cells are mostly root with the fifth for relief, and
  // it stays on instruments that keep their shape down there -- strings, a
  // piano and a bell all turn to mud below A1.
  var BASS_CELLS = [
    [0, 0, 0, 4],
    [0, 0, 4, 0],
    [0, 0, 0, 0],                                  // just the root, driving
    [0, 4, 0, 2],
    [0, 0, 2, 0],
    [0, 4, 4, 0]
  ];
  var BASS_VOICES = ["saw", "square", "sine"];

  var GAPS = [2, 4, 3, 4, 2, 6, 3, 4];             // sixteenths from one onset to the next
  var HOLDS = [0.7, 1.1, 0.8, 1.3];                // a passing tone: struck and gone
  var SUSTAIN = [3, 5, 4, 7, 6, 4];                // an anchor: rings on over what follows
  var OCTS = [0, 0, 0, 0, 7, 0];                   // every nth note up an octave, 0 for never
  var figures = {};

  function figure(name, team) {
    var key = team + "|" + (name || "");
    if (figures[key]) return figures[key];
    var h = 2166136261;
    for (var i = 0; i < key.length; i++) {
      h ^= key.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    h = h >>> 0;
    var bass = team === 1;
    var pool = bass ? BASS_CELLS : CELLS;
    var kit = bass ? BASS_VOICES : VOICES;
    var cell = pool[(h >>> 5) % pool.length], gaps = [], holds = [];
    for (var m = 0; m < 3; m++) gaps.push(GAPS[(h >>> (2 + m * 5)) % GAPS.length]);
    for (var q = 0; q < 3; q++) holds.push(HOLDS[(h >>> (7 + q * 4)) % HOLDS.length]);
    var f = { n: LENGTHS[h % LENGTHS.length], cell: cell, gaps: gaps, holds: holds,
              sus: SUSTAIN[(h >>> 21) % SUSTAIN.length],
              voice: kit[(h >>> 24) % kit.length], bass: bass,
              oct: OCTS[(h >>> 17) % OCTS.length] };
    figures[key] = f;
    return f;
  }

  function run(t0, e) {
    var fig = figure(e.name, e.team);
    var six = STEP / 2;                            // the sixteenth everything is measured in
    var base = ROOT + (e.team === 0 ? 12 : 0);
    // A melodic block answers an octave below the throw it turns away. A bass
    // one stays where it is: there is no octave under a bassline to drop to.
    var lift = (e.kind === "block" && !fig.bass) ? -7 : 0;
    var gain = e.kind === "block" ? 0.15 : 0.12;
    var rot = e.aim || 0;                          // aim enters the cell at a different note
    var t = t0;
    // Placed by its lowest note, so nothing in the figure drops out of hearing.
    var low = Math.min.apply(null, fig.cell) + lift + trans;
    var off = foldShift(base + degree(low), e.team);
    // A bassline has to come round WITH the drums. Its gaps do not divide
    // into a bar, so left alone the loop would walk away from the kick a
    // little further every time round. It is given whole half bars -- and
    // what is left over is held by the last note rather than left as rest,
    // because a floor with holes in it is not one.
    var endSix = 0;
    if (fig.bass) {
      var spanSix = 2;                             // the breath after the third note
      for (var j = 0; j < fig.n; j++) spanSix += fig.gaps[j % fig.gaps.length];
      endSix = Math.ceil(spanSix / 8) * 8;
    }
    for (var i = 0; i < fig.n; i++) {
      if (i === 3) t += six * 2;                   // three, a breath, then the rest
      var deg = fig.cell[(i + rot) % fig.cell.length];
      var gap = fig.gaps[i % fig.gaps.length];
      // The root and the fifth are what the figure is built on, so they are
      // what rings -- held over the notes that follow them. The degrees
      // between are passing and stay short. Every note being the same length
      // is most of what made these read as a machine rather than a part.
      var anchor = (deg === 0 || deg === 4);
      var hold = anchor ? Math.min(fig.sus, gap + 3) : fig.holds[i % fig.holds.length];
      // A bassline is monophonic. Notes of different pitch ringing over each
      // other down there is mud rather than harmony, so a bass note lasts
      // exactly up to the next one: joined up, never stacked. Its lengths
      // still vary, because the gaps do.
      if (fig.bass) {
        hold = gap * 0.98;
        // The last note holds out to the half bar, so the loop is seamless.
        if (i === fig.n - 1) hold = Math.max(hold, endSix - (t - t0) / six);
      }
      // A note that has had room before it lands harder, which is what puts
      // the emphasis somewhere different each time round rather than on the
      // beat every time. A held note comes in softer, because it is going to
      // be there a while and there may be two more over the top of it.
      var hit = gain * (gap >= 3 ? 1.18 : 0.88) * (anchor ? 0.78 : 1);
      var up = (!fig.bass && fig.oct && (i + 1) % fig.oct === 0) ? 12 : 0;
      var d = deg + lift + trans;
      pluck(t, base + degree(d) + off + up, six * hold, e.kind, hit, fig.voice);
      t += six * gap;
    }
    voiceUntil[e.team] = fig.bass ? t0 + endSix * six : t;
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
    var fig = figure(who.name, who.team);
    var start = fig.cell[0] + trans;                // the degree its figure begins on
    var step3 = [0, 2, 4][k % 3];                   // the note, its third, its fifth
    var base = ROOT + (who.team === 0 ? 12 : 0);
    var m = base + degree(start + step3) + foldShift(base + degree(start), who.team);
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
    o.connect(lp); lp.connect(g); g.connect(notes);
    o.start(t); o.stop(t + 0.24);
    keep(g, [o], t + 0.24);
  }

  // ── The clock ─────────────────────────────────────────────────────────
  function schedule() {
    var now = ctx.currentTime;
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
          // Only the fighter speaking for its side is heard. Everything the
          // others do still lands on the kit -- the drums are the arena, not
          // anybody's part -- so a fight with six in it still sounds like a
          // fight with six in it, while only two of them carry a line.
          if (e.lead && e.team === 1) bassAim = e.aim;   // steers the loop, does not start it
          if (e.lead && e.team === 0 && stepTime >= voiceUntil[e.team]) {
            if (e.kind === "throw") stepKey();     // a block stays in the key it answers
            run(stepTime, e);
          }
          if (e.kind === "block") tom(stepTime, e.tom);
        } else if (e.kind === "bounce" || e.kind === "home") {
          tom(stepTime, e.tom);
        } else if (e.kind === "ring") {
          crash(stepTime);
        } else if (e.kind === "derez") {
          ride(stepTime);
        }
      }
      // The bassline never stops while there is a round on: the moment the
      // sentinels' figure runs out it goes round again. It is the floor the
      // rest of it stands on, and a floor with holes in it is not one.
      // On a beat, always. The loop's period is a whole number of half bars,
      // so it keeps whatever footing it started on -- start it off the beat
      // once and it stays off the beat for the rest of the round.
      if (fighting && bassName && onBeat && stepTime >= voiceUntil[1]) {
        run(stepTime, { kind: "throw", team: 1, aim: bassAim, name: bassName, lead: true });
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
        // The runs go through a bus of their own, apart from the kit. It is
        // where they can be balanced against the drums, and it is the one
        // place that knows what counts as a note rather than a hit.
        notes = ctx.createGain();
        notes.gain.value = 1;
        notes.connect(master);
        noise = makeNoise();
      }
      wake();
      step = 0;
      bpm = wantBpm = BASE_BPM;
      STEP = 60 / bpm / 2;
      stepTime = ctx.currentTime + 0.08;
      pending = []; voiceUntil = [0, 0]; hanging = {}; hangN = 0;
      bassName = ""; bassAim = 1; fighting = true;   // the first round counts too
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
      if (kind === "over") { fighting = false; cutAll(); return; }  // the last of a side is down
      if (kind === "lead") {                       // this side's voice has changed hands
        if (info.team === 1) bassName = info.name || "";
        return;
      }
      if (kind === "hang") {
        if (!info.lead) return;                    // only a side's own voice is heard hanging
        hanging[info.name] = { name: info.name, team: info.team };
        return;
      }
      if (kind === "unhang") { delete hanging[info.name]; return; }
      if (kind === "round") {                       // nobody hanging, back to the root
        hanging = {}; trans = 0; transStep = 0;
        bassName = ""; bassAim = 1; fighting = true;
        return;
      }
      pending.push({ kind: kind, team: (info && info.team) || 0,
                     lead: !!(info && info.lead),
                     aim: info && info.aim != null ? info.aim : 1,
                     name: (info && info.name) || "",
                     tom: info && info.tom != null ? info.tom : 1 });   // which drum, and whose figure
    }
  };
})();
