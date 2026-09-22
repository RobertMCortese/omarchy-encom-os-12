// A small policy network, and the two it takes to fight with one.
//
// The duel is a guessing game. A throw is aimed high, at the body, or low;
// the defender ducks it, blocks it on its disc, or jumps it. Each guard
// answers exactly one aim:
//
//        aimed HIGH   aimed MID    aimed LOW
//   DUCK    covered      through     through
//   BLOCK   through      covered     through
//   JUMP    through      through     covered
//
// Nothing beats anything else outright, so there is no move to settle on:
// the only way to do better than chance is to read what the opponent tends
// to do and answer that, while not being read in return. Played perfectly
// both sides throw and guard at random and neither gains -- which is the
// point. Anything less than perfect is worth exploiting, and that is what
// these learn to do.
//
// Each side carries two policies, one for attacking and one for defending,
// shared by its fighters so a team learns from every exchange it has. They
// train against each other as the fight runs: one sample per throw, from
// whether the guard matched the aim, by REINFORCE with a running baseline.
// An entropy term keeps a policy from collapsing onto one answer, which
// would be both duller to watch and immediately exploitable.
//
// Plain arrays and loops, a few hundred weights: it costs nothing next to
// drawing the scene, and needs no library.
(function () {
  "use strict";

  var AIMS = ["high", "mid", "low"];
  var GUARDS = ["duck", "block", "jump"];     // guard i answers aim i

  function zeros(n) { var a = new Array(n); for (var i = 0; i < n; i++) a[i] = 0; return a; }

  // One hidden layer, tanh, softmax out. Small enough that the whole thing
  // is a few hundred numbers.
  function Net(nIn, nHid, nOut) {
    this.nIn = nIn; this.nHid = nHid; this.nOut = nOut;
    this.W1 = []; this.b1 = zeros(nHid);
    this.W2 = []; this.b2 = zeros(nOut);
    var scale = 1 / Math.sqrt(nIn);
    for (var j = 0; j < nHid; j++) {
      var row = new Array(nIn);
      for (var i = 0; i < nIn; i++) row[i] = (Math.random() * 2 - 1) * scale;
      this.W1.push(row);
    }
    for (var k = 0; k < nOut; k++) {
      var r2 = new Array(nHid);
      for (var h = 0; h < nHid; h++) r2[h] = (Math.random() * 2 - 1) * 0.1;
      this.W2.push(r2);
    }
    this.h = zeros(nHid);
    this.p = zeros(nOut);      // what the weights say
    this.pMix = zeros(nOut);   // what it actually plays: the above, kept off the walls
  }

  // `mask[k]` false rules an action out: a disc that is away cannot be held
  // up as a shield, so BLOCK is simply not on offer that throw.
  Net.prototype.forward = function (x, mask) {
    var j, i, k, s;
    for (j = 0; j < this.nHid; j++) {
      s = this.b1[j];
      var row = this.W1[j];
      for (i = 0; i < this.nIn; i++) s += row[i] * x[i];
      this.h[j] = Math.tanh(s);
    }
    var z = new Array(this.nOut), top = -Infinity;
    for (k = 0; k < this.nOut; k++) {
      if (mask && !mask[k]) { z[k] = -Infinity; continue; }
      s = this.b2[k];
      var r2 = this.W2[k];
      for (j = 0; j < this.nHid; j++) s += r2[j] * this.h[j];
      z[k] = s;
      if (s > top) top = s;
    }
    var sum = 0;
    for (k = 0; k < this.nOut; k++) {
      this.p[k] = z[k] === -Infinity ? 0 : Math.exp(z[k] - top);
      sum += this.p[k];
    }
    for (k = 0; k < this.nOut; k++) this.p[k] = sum > 0 ? this.p[k] / sum : (mask && !mask[k] ? 0 : 1 / this.nOut);

    // Always keep a little weight on the answers it has stopped choosing.
    // Entropy alone cannot do this: its pull on a distribution goes to zero
    // as that distribution collapses, so a policy that has settled on one
    // answer is already past being pulled back. Worse, a policy that always
    // loses drives its own baseline down to meet it, the advantage goes to
    // zero with it, and nothing moves again. Between them a side can be
    // farmed forever by an opponent it never tries anything against. The
    // floor is what stops that: it keeps finding out what the others would
    // have been worth. Learning still follows the weights, so this is
    // exploration laid over the policy rather than part of it.
    var avail = 0;
    for (k = 0; k < this.nOut; k++) if (!mask || mask[k]) avail++;
    var eps = exports.eps;
    for (k = 0; k < this.nOut; k++) {
      this.pMix[k] = (mask && !mask[k]) ? 0
                   : (1 - eps) * this.p[k] + eps / avail;
    }
    return this.p;
  };

  // Plays from the floored spread; learning still follows the weights.
  Net.prototype.sample = function () {
    var r = Math.random(), acc = 0;
    for (var k = 0; k < this.nOut; k++) {
      acc += this.pMix[k];
      if (r < acc) return k;
    }
    for (var m = this.nOut - 1; m >= 0; m--) if (this.pMix[m] > 0) return m;
    return 0;
  };

  // One REINFORCE step on the action just taken, nudged toward keeping the
  // spread of answers wide. `x` and the forward pass that produced `p` must
  // be the ones the action came from.
  Net.prototype.learn = function (x, took, adv, lr, beta) {
    var k, j, i;
    // Entropy of the current spread, for the term that resists collapsing.
    var H = 0;
    for (k = 0; k < this.nOut; k++) if (this.p[k] > 1e-9) H -= this.p[k] * Math.log(this.p[k]);

    var dz = new Array(this.nOut);
    for (k = 0; k < this.nOut; k++) {
      if (this.p[k] <= 0) { dz[k] = 0; continue; }          // ruled out this throw
      var pg = ((k === took ? 1 : 0) - this.p[k]) * adv;
      var ent = -this.p[k] * (Math.log(this.p[k]) + H);
      dz[k] = pg + beta * ent;
    }
    var dh = zeros(this.nHid);
    for (k = 0; k < this.nOut; k++) {
      if (dz[k] === 0) continue;
      var r2 = this.W2[k];
      for (j = 0; j < this.nHid; j++) {
        dh[j] += dz[k] * r2[j];
        r2[j] += lr * dz[k] * this.h[j];
      }
      this.b2[k] += lr * dz[k];
    }
    for (j = 0; j < this.nHid; j++) {
      var g = dh[j] * (1 - this.h[j] * this.h[j]);          // through the tanh
      if (g === 0) continue;
      var row = this.W1[j];
      for (i = 0; i < this.nIn; i++) row[i] += lr * g * x[i];
      this.b1[j] += lr * g;
    }
  };

  // A side's pair of policies, plus the running averages that make the
  // reward signal useful and give the readout something to show.
  function Side(nIn, nHid) {
    this.att = new Net(nIn, nHid, 3);
    this.def = new Net(nIn, nHid, 3);
    this.baseAtt = 0; this.baseDef = 0;
    this.throws = 0; this.through = 0;
    this.recent = 0;                      // share of throws getting through, smoothed
    this.aimMix = [1 / 3, 1 / 3, 1 / 3];  // what it has been choosing lately
    this.guardMix = [1 / 3, 1 / 3, 1 / 3];
  }

  function blend(mix, k, rate) {
    for (var i = 0; i < mix.length; i++) mix[i] += ((i === k ? 1 : 0) - mix[i]) * rate;
  }

  var exports = window.DiscWarsLearn = {
    AIMS: AIMS,
    GUARDS: GUARDS,
    Net: Net,
    Side: Side,
    lr: 0.05,
    beta: 0.02,
    eps: 0.08,
    baseRate: 0.02,
    mixRate: 0.02,

    // Attacker picks an aim, defender picks a guard, both from the same
    // reading of the situation. Returns everything the caller needs to play
    // the throw out and then settle up.
    decide: function (attSide, defSide, x, canBlock) {
      attSide.att.forward(x, null);
      var aim = attSide.att.sample();
      var pAim = attSide.att.p.slice();
      var mask = [true, canBlock, true];
      defSide.def.forward(x, mask);
      var guard = defSide.def.sample();
      var pGuard = defSide.def.p.slice();
      return { aim: aim, guard: guard, through: guard !== aim,
               pAim: pAim, pGuard: pGuard, canBlock: canBlock };
    },

    // The throw has been resolved: teach both sides what came of it.
    settle: function (attSide, defSide, x, d) {
      var rAtt = d.through ? 1 : -1;
      attSide.baseAtt += (rAtt - attSide.baseAtt) * this.baseRate;
      defSide.baseDef += (-rAtt - defSide.baseDef) * this.baseRate;

      attSide.att.forward(x, null);
      attSide.att.learn(x, d.aim, rAtt - attSide.baseAtt, this.lr, this.beta);

      var mask = [true, d.canBlock, true];
      defSide.def.forward(x, mask);
      defSide.def.learn(x, d.guard, -rAtt - defSide.baseDef, this.lr, this.beta);

      attSide.throws++;
      if (d.through) attSide.through++;
      attSide.recent += ((d.through ? 1 : 0) - attSide.recent) * this.mixRate;
      blend(attSide.aimMix, d.aim, this.mixRate);
      blend(defSide.guardMix, d.guard, this.mixRate);
    }
  };
})();
