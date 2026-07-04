// ---------------------------------------------------------------
// Battle vignette: the Fire Emblem style combat cut-in.
// Two modes:
//  - REPLAY: combat already resolved by the core; the overlay replays the
//    recorded events (used for AI-vs-AI simulation).
//  - INTERACTIVE: Legend of Dragoon style additions. The battle resolves
//    strike by strike DURING the vignette:
//      * Offense (your strikes): time taps (Space / click) against a
//        shrinking ring — one per step of your class's rhythm. Scales
//        damage dealt 0.75x-1.5x.
//      * Defense (incoming strikes): HOLD in anticipation while the enemy
//        charges you, then RELEASE as the blow lands. Parried! 50% /
//        Blocked 75% / held-through Guarded 90% / dropped guard 100%.
//    Ring color = combat type: blue physical, green magic, red defense.
// ---------------------------------------------------------------

const VIGNETTE = {
  W: 560, H: 300,
  INTRO: 0.35,       // seconds: panel fade-in, fighters slide in
  STRIKE: 0.95,      // seconds per attack event (replay mode)
  IMPACT_AT: 0.35,   // fraction of a replay strike beat where the blow lands
  APPROACH: 0.33,    // interactive: lunge-in before the QTE
  IMPACT: 0.8,       // interactive: blow lands, then retreat
  OUTRO: 0.6,
  OUTRO_KILL: 1.1,
  HP_DRAIN_RATE: 30, // HP per second the displayed bar drains
  QTE_LEAD_IN: 0.45, // pause before the first ring starts shrinking
  QTE_GAP: 0.3,      // pause between presses of a multi-step addition
  RING_X: 280, RING_Y: 105, RING_START: 74, RING_END: 26,
};

// --- QTE grading (pure functions, also used by tests) -----------------------

function gradePress(err, spec) {
  if (err <= spec.perfect) return { points: 1, text: "PERFECT!", color: "#ffe94d" };
  if (err <= spec.good) return { points: 0.6, text: "Good", color: "#ffffff" };
  return { points: 0, text: "Miss", color: "#8a90a0" };
}

// Offense: average press quality maps to a damage multiplier.
function offenseResult(points) {
  const avg = points.reduce((a, b) => a + b, 0) / points.length;
  const mult = 0.75 + 0.75 * avg;
  const label = avg >= 0.999 ? "MAX!" : avg >= 0.6 ? "Great" : avg > 0 ? "Good" : "Whiffed";
  return { mult, label };
}

// Defense: grade the hold-and-release parry. `q` carries the hold state
// machine: waiting (never pressed) | holding | released (+releaseErr).
function defenseResult(q) {
  if (q.state === "released") {
    if (q.releaseErr <= q.spec.perfect) return { mult: 0.5, label: "Parried!" };
    if (q.releaseErr <= q.spec.good) return { mult: 0.75, label: "Blocked" };
    return { mult: 1.0, label: "Exposed" };  // dropped the guard too early
  }
  if (q.state === "holding") return { mult: 0.9, label: "Guarded" }; // static guard
  return { mult: 1.0, label: "Exposed" };    // never raised the guard
}

class BattleVignette {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    canvas.width = VIGNETTE.W;
    canvas.height = VIGNETTE.H;
    this.playing = false;
    this.interactive = false;
    // Offense taps trigger on press-down; defense parries need the release
    // too, so both edges of key and mouse are wired.
    canvas.addEventListener("mousedown", () => {
      if (this.interactive) this.holdStart();
      else this.skip();
    });
    canvas.addEventListener("mouseup", () => {
      if (this.interactive) this.holdEnd();
    });
    window.addEventListener("keydown", e => {
      if (e.code === "Space" && this.playing && this.interactive) {
        e.preventDefault();
        if (!e.repeat) this.holdStart();
      }
    });
    window.addEventListener("keyup", e => {
      if (e.code === "Space" && this.playing && this.interactive) {
        e.preventDefault();
        this.holdEnd();
      }
    });
    this.tick = this.tick.bind(this);
  }

  // --- shared setup -----------------------------------------------------

  setupScene(battle) {
    const mkFighter = (unit, side, hp) => ({
      unit, side,
      home: side === "L" ? 150 : 410,
      x: side === "L" ? 150 : 410,
      lunge: 0,        // 0..1 progress toward the other fighter
      dodge: 0,        // remaining dodge-animation seconds
      shake: 0,        // remaining hit-shake seconds
      shownHp: hp,     // animated display value
      targetHp: hp,    // value shownHp drains toward
      alpha: 1,
    });
    this.left = mkFighter(battle.attacker, "L", battle.preHp.attacker);
    this.right = mkFighter(battle.defender, "R", battle.preHp.defender);
    this.popups = [];
    this.flash = 0;
    this.panelAlpha = 0;
    this.lastTime = performance.now();
    this.canvas.classList.remove("hidden");
  }

  fighterOf(unit) { return this.left.unit === unit ? this.left : this.right; }

  // --- REPLAY mode (battle = {attacker, defender, preHp, events}) --------

  play(battle, onDone, timeScale = 1) {
    this.interactive = false;
    this.game = null;
    this.onDone = onDone;
    this.timeScale = timeScale;
    this.playing = true;
    this.setupScene(battle);

    const killed = battle.events.some(e => e.killed);
    this.beats = [{ type: "intro", dur: VIGNETTE.INTRO }];
    for (const ev of battle.events) {
      this.beats.push({ type: "strike", dur: VIGNETTE.STRIKE, ev, applied: false });
    }
    this.beats.push({ type: "outro", dur: killed ? VIGNETTE.OUTRO_KILL : VIGNETTE.OUTRO, deathShown: false });
    this.beatIndex = 0;
    this.beatElapsed = 0;
    requestAnimationFrame(this.tick);
  }

  // --- INTERACTIVE mode (battle = {attacker, defender, preHp, strikes}) --

  playInteractive(battle, game, onDone) {
    this.interactive = true;
    this.game = game;
    this.battle = battle;
    this.onDone = onDone;
    this.timeScale = 1;   // QTEs can't be time-scaled: timing IS the game
    this.playing = true;
    this.setupScene(battle);
    this.strikes = battle.strikes;
    this.strikeIdx = -1;
    this.qte = null;
    this.finishCalled = false;
    this.phase = "intro";
    this.phaseT = 0;
    requestAnimationFrame(this.tick);
  }

  // --- frame driver -------------------------------------------------------

  tick(now) {
    if (!this.playing) return;
    const dt = Math.min(0.05, (now - this.lastTime) / 1000) * this.timeScale;
    this.lastTime = now;

    if (this.interactive) this.stepInteractive(dt);
    else this.stepReplay(dt);
    this.updateCommon(dt);
    this.draw();
    if (this.playing) requestAnimationFrame(this.tick);
  }

  stepReplay(dt) {
    this.beatElapsed += dt;
    const beat = this.beats[this.beatIndex];
    const t = Math.min(1, this.beatElapsed / beat.dur);
    this.updateReplayBeat(beat, t);
    if (t >= 1) {
      this.beatIndex++;
      this.beatElapsed = 0;
      if (this.beatIndex >= this.beats.length) this.finish();
    }
  }

  updateReplayBeat(beat, t) {
    if (beat.type === "intro") {
      this.updateIntro(t);
    } else if (beat.type === "strike") {
      this.panelAlpha = 1;
      const actor = this.fighterOf(beat.ev.from);
      const ia = VIGNETTE.IMPACT_AT;
      let lunge;
      if (t < ia) lunge = t / ia;
      else if (t < 0.6) lunge = 1;
      else lunge = 1 - (t - 0.6) / 0.4;
      actor.lunge = Math.max(0, Math.min(1, lunge));
      if (!beat.applied && t >= ia) {
        beat.applied = true;
        this.applyImpact(beat.ev);
      }
    } else if (beat.type === "outro") {
      this.updateOutro(beat, t);
    }
  }

  stepInteractive(dt) {
    this.phaseT += dt;
    const strike = this.strikes[this.strikeIdx];
    switch (this.phase) {
      case "intro": {
        const t = Math.min(1, this.phaseT / VIGNETTE.INTRO);
        this.updateIntro(t);
        if (t >= 1) this.nextStrike();
        break;
      }
      case "approach": {
        this.panelAlpha = 1;
        const t = Math.min(1, this.phaseT / VIGNETTE.APPROACH);
        this.fighterOf(strike.actor).lunge = easeOutQuad(t);
        if (t >= 1) this.startQTE(strike);
        break;
      }
      case "qte":
        this.updateQTE(dt);
        break;
      case "impact": {
        const t = Math.min(1, this.phaseT / VIGNETTE.IMPACT);
        // hold the pose briefly, then retreat
        this.fighterOf(strike.actor).lunge = t < 0.35 ? 1 : 1 - (t - 0.35) / 0.65;
        if (t >= 1) this.nextStrike();
        break;
      }
      case "outro": {
        const t = Math.min(1, this.phaseT / this.outroDur);
        this.updateOutro(this.outroBeat, t);
        if (t >= 1) this.finish();
        break;
      }
    }
  }

  nextStrike() {
    this.phaseT = 0;
    // find the next strike whose actor and target are both still alive
    do { this.strikeIdx++; } while (
      this.strikeIdx < this.strikes.length &&
      (this.strikes[this.strikeIdx].actor.hp <= 0 ||
       this.strikes[this.strikeIdx].target.hp <= 0));

    if (this.strikeIdx >= this.strikes.length) {
      // battle over: commit the result, then play the outro
      if (!this.finishCalled) {
        this.finishCalled = true;
        this.game.finishBattle(this.battle.attacker);
      }
      const killed = this.left.targetHp <= 0 || this.right.targetHp <= 0;
      this.outroDur = killed ? VIGNETTE.OUTRO_KILL : VIGNETTE.OUTRO;
      this.outroBeat = { deathShown: false, dur: this.outroDur };
      this.phase = "outro";
    } else if (this.strikes[this.strikeIdx].actor.team === "player") {
      this.phase = "approach";
    } else {
      // Incoming strike: no separate approach — the enemy's charge happens
      // DURING the QTE and is itself the release cue for the parry.
      this.startQTE(this.strikes[this.strikeIdx]);
    }
  }

  startQTE(strike) {
    const offense = strike.actor.team === "player";
    if (offense) {
      this.qte = {
        spec: strike.actor.cls.qte,
        kind: "offense",
        color: strike.actor.cls.magic ? QTE_COLORS.magic : QTE_COLORS.physical,
        step: 0,
        stepT: -VIGNETTE.QTE_LEAD_IN,  // negative time = wind-up, ring not moving
        stepDone: false,
        points: [],
      };
    } else {
      this.qte = {
        spec: DEFENSE_QTE,
        kind: "defense",
        color: QTE_COLORS.defense,
        stepT: 0,
        state: "waiting",   // waiting -> holding -> released
        releaseErr: null,
      };
    }
    this.phase = "qte";
    this.phaseT = 0;
  }

  updateQTE(dt) {
    const q = this.qte;
    q.stepT += dt;
    if (q.kind === "defense") {
      this.updateDefenseQTE(q);
      return;
    }
    const period = q.spec.periods[q.step];
    if (!q.stepDone && q.stepT > period + q.spec.good) {
      this.recordPress({ points: 0, text: "Miss", color: "#8a90a0" });
    }
    if (q.stepDone) {
      q.step++;
      q.stepDone = false;
      if (q.step >= q.spec.periods.length) this.resolveQTEStrike();
      else q.stepT = -VIGNETTE.QTE_GAP;
    }
  }

  updateDefenseQTE(q) {
    const impact = q.spec.windup + q.spec.travel;
    // the enemy's lunge IS the timing cue: it tracks the gauge exactly
    const strike = this.strikes[this.strikeIdx];
    const k = Math.min(1, Math.max(0, (q.stepT - q.spec.windup) / q.spec.travel));
    this.fighterOf(strike.actor).lunge = k;

    if (q.state === "released") {
      // blow still lands at the impact moment even if the guard dropped early
      if (q.stepT >= Math.max(impact, q.releaseT)) this.resolveQTEStrike();
    } else if (q.stepT >= impact + q.spec.good) {
      this.resolveQTEStrike();  // held through, or never raised the guard
    }
  }

  // Press-down: offense grades the tap immediately; defense raises the guard.
  holdStart() {
    if (!this.playing || !this.interactive || this.phase !== "qte") return;
    const q = this.qte;
    if (q.kind === "offense") {
      if (q.stepT < 0 || q.stepDone) return;  // ignore presses in the wind-up
      const period = q.spec.periods[q.step];
      this.recordPress(gradePress(Math.abs(q.stepT - period), q.spec));
    } else if (q.state === "waiting") {
      q.state = "holding";
      q.pressT = q.stepT;
    }
  }

  // Release: only meaningful for the defensive parry.
  holdEnd() {
    if (!this.playing || !this.interactive || this.phase !== "qte") return;
    const q = this.qte;
    if (q.kind === "defense" && q.state === "holding") {
      q.state = "released";
      q.releaseT = q.stepT;
      q.releaseErr = Math.abs(q.stepT - (q.spec.windup + q.spec.travel));
    }
  }

  recordPress(grade) {
    const q = this.qte;
    q.points.push(grade.points);
    q.stepDone = true;
    this.popups.push({ text: grade.text, x: VIGNETTE.RING_X, y: VIGNETTE.RING_Y - 38,
      color: grade.color, size: 16, age: 0, dur: 0.7 });
  }

  resolveQTEStrike() {
    const q = this.qte;
    const strike = this.strikes[this.strikeIdx];
    let offMult = 1, defMult = 1, label = null;
    if (q.kind === "offense") {
      const r = offenseResult(q.points);
      offMult = r.mult;
      label = r.label;
    } else {
      const r = defenseResult(q);
      defMult = r.mult;
      label = r.label;
    }
    const ev = this.game.strike(strike.actor, strike.target, offMult, defMult, label);
    this.applyImpact(ev);
    if (label) {
      this.popups.push({ text: label, x: VIGNETTE.W / 2, y: 84,
        color: q.color, size: 20, age: 0, dur: 1.0 });
    }
    this.qte = null;
    this.phase = "impact";
    this.phaseT = 0;
  }

  // --- shared beat pieces --------------------------------------------------

  updateIntro(t) {
    this.panelAlpha = t;
    const ease = easeOutQuad(t);
    this.left.x = this.left.home - 80 * (1 - ease);
    this.right.x = this.right.home + 80 * (1 - ease);
  }

  updateOutro(beat, t) {
    for (const f of [this.left, this.right]) {
      if (f.targetHp <= 0) {
        f.alpha = Math.max(0, 1 - t * 1.6);
        if (!beat.deathShown) {
          beat.deathShown = true;
          this.popups.push({ text: `${f.unit.name} falls!`, x: VIGNETTE.W / 2,
            y: 60, color: "#ffe94d", size: 20, age: 0, dur: 1.0 });
        }
      }
    }
    const dur = beat.dur || this.outroDur;
    const fadeStart = 1 - 0.35 / dur;
    this.panelAlpha = t > fadeStart ? 1 - (t - fadeStart) / (1 - fadeStart) : 1;
  }

  applyImpact(ev) {
    const victim = this.fighterOf(ev.to);
    const vx = victim.x + (victim.side === "L" ? -10 : 10);
    if (ev.type === "miss") {
      victim.dodge = 0.35;
      this.popups.push({ text: "Miss", x: vx, y: 120, color: "#aab0be",
        size: 18, age: 0, dur: 0.9 });
    } else {
      victim.targetHp = Math.max(0, victim.targetHp - ev.dmg);
      victim.shake = ev.crit ? 0.4 : 0.28;
      if (ev.crit) {
        this.flash = 0.22;
        this.popups.push({ text: "CRITICAL!", x: VIGNETTE.W / 2, y: 52,
          color: "#ffe94d", size: 22, age: 0, dur: 0.9 });
      }
      this.popups.push({ text: `${ev.dmg}`, x: vx, y: 118,
        color: ev.crit ? "#ffe94d" : "#ffffff", size: ev.crit ? 30 : 24,
        age: 0, dur: 0.9 });
    }
  }

  updateCommon(dt) {
    for (const f of [this.left, this.right]) {
      if (f.shownHp > f.targetHp) {
        f.shownHp = Math.max(f.targetHp, f.shownHp - VIGNETTE.HP_DRAIN_RATE * dt);
      }
      f.dodge = Math.max(0, f.dodge - dt);
      f.shake = Math.max(0, f.shake - dt);
    }
    this.flash = Math.max(0, this.flash - dt);
    for (const p of this.popups) p.age += dt;
    this.popups = this.popups.filter(p => p.age < p.dur);
  }

  // --- drawing ---------------------------------------------------------

  fighterX(f) {
    const other = f === this.left ? this.right : this.left;
    const towards = (other.home - f.home) * 0.72;
    let x = f.x + towards * easeOutQuad(f.lunge);
    if (f.dodge > 0) {
      const dt01 = 1 - f.dodge / 0.35;
      x += Math.sin(dt01 * Math.PI) * 38 * (f.side === "L" ? -1 : 1);
    }
    if (f.shake > 0) x += Math.sin(f.shake * 70) * 8 * (f.shake / 0.28);
    return x;
  }

  draw() {
    const { W, H } = VIGNETTE;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, W, H);
    ctx.save();
    ctx.globalAlpha = this.panelAlpha;

    // panel + sky + platforms
    roundRect(ctx, 0, 0, W, H, 12, "#171a22", "#3a3f4c");
    const sky = ctx.createLinearGradient(0, 10, 0, 200);
    sky.addColorStop(0, "#313a4d");
    sky.addColorStop(1, "#20242f");
    ctx.fillStyle = sky;
    ctx.fillRect(10, 10, W - 20, 190);
    for (const hx of [150, 410]) {
      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.beginPath();
      ctx.ellipse(hx, 212, 78, 16, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    for (const f of [this.left, this.right]) this.drawFighter(f);
    this.drawHpBox(this.left, 22);
    this.drawHpBox(this.right, W / 2 + 8);
    if (this.interactive && this.phase === "qte" && this.qte) this.drawQTE();

    // popups
    for (const p of this.popups) {
      const k = p.age / p.dur;
      ctx.globalAlpha = this.panelAlpha * (1 - k * k);
      ctx.fillStyle = p.color;
      ctx.font = `bold ${p.size}px 'Segoe UI', sans-serif`;
      ctx.textAlign = "center";
      ctx.fillText(p.text, p.x, p.y - 26 * k);
    }
    ctx.globalAlpha = this.panelAlpha;

    // crit flash
    if (this.flash > 0) {
      ctx.globalAlpha = this.panelAlpha * (this.flash / 0.22) * 0.75;
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, W, H);
    }
    ctx.restore();
  }

  drawQTE() {
    // slight extra dim so the prompts read clearly
    this.ctx.fillStyle = "rgba(10,12,16,0.35)";
    this.ctx.fillRect(10, 10, VIGNETTE.W - 20, 190);
    if (this.qte.kind === "defense") this.drawDefenseQTE();
    else this.drawOffenseQTE();
  }

  drawOffenseQTE() {
    const ctx = this.ctx;
    const q = this.qte;
    const { RING_X, RING_Y, RING_START, RING_END } = VIGNETTE;
    const period = q.spec.periods[q.step];

    // step dots: one per press in this class's addition
    const n = q.spec.periods.length;
    for (let i = 0; i < n; i++) {
      const dx = RING_X + (i - (n - 1) / 2) * 18;
      ctx.beginPath();
      ctx.arc(dx, RING_Y - 52, 5, 0, Math.PI * 2);
      ctx.fillStyle = i < q.step ? q.color : "rgba(255,255,255,0.25)";
      ctx.fill();
    }

    // target ring
    ctx.lineWidth = 3;
    ctx.strokeStyle = q.color;
    ctx.beginPath();
    ctx.arc(RING_X, RING_Y, RING_END, 0, Math.PI * 2);
    ctx.stroke();

    // shrinking ring (only once the wind-up is over)
    if (q.stepT >= 0 && !q.stepDone) {
      const k = Math.min(1, q.stepT / period);
      const r = RING_START - (RING_START - RING_END) * k;
      ctx.lineWidth = 4;
      ctx.globalAlpha = this.panelAlpha * 0.95;
      ctx.beginPath();
      ctx.arc(RING_X, RING_Y, r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = this.panelAlpha;
    }

    ctx.fillStyle = "rgba(255,255,255,0.55)";
    ctx.font = "11px 'Segoe UI', sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("SPACE / CLICK", RING_X, RING_Y + 48);
  }

  drawDefenseQTE() {
    const ctx = this.ctx;
    const q = this.qte;
    const impact = q.spec.windup + q.spec.travel;
    const total = impact + q.spec.good;   // gauge spans up to the last legal release
    const xa = 160, xb = 400, y = 100;
    const toX = t => xa + (xb - xa) * Math.min(1, t / total);

    // track
    ctx.strokeStyle = "rgba(255,255,255,0.3)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(xa, y);
    ctx.lineTo(xb, y);
    ctx.stroke();
    // good / perfect release zones around the impact notch
    ctx.fillStyle = "rgba(224,72,72,0.30)";
    ctx.fillRect(toX(impact - q.spec.good), y - 8, toX(impact + q.spec.good) - toX(impact - q.spec.good), 16);
    ctx.fillStyle = "rgba(224,72,72,0.65)";
    ctx.fillRect(toX(impact - q.spec.perfect), y - 8, toX(impact + q.spec.perfect) - toX(impact - q.spec.perfect), 16);
    // impact notch
    ctx.strokeStyle = q.color;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(toX(impact), y - 14);
    ctx.lineTo(toX(impact), y + 14);
    ctx.stroke();
    // the incoming blow
    const holding = q.state === "holding";
    ctx.strokeStyle = holding ? "#ffffff" : "rgba(255,255,255,0.6)";
    ctx.lineWidth = holding ? 4 : 3;
    ctx.beginPath();
    ctx.moveTo(toX(q.stepT), y - 11);
    ctx.lineTo(toX(q.stepT), y + 11);
    ctx.stroke();

    // shield arc on the defender while the guard is up
    const defender = this.fighterOf(this.strikes[this.strikeIdx].target);
    const dx = this.fighterX(defender);
    ctx.strokeStyle = q.color;
    ctx.lineWidth = holding ? 5 : 2;
    ctx.globalAlpha = this.panelAlpha * (holding ? 0.95 : q.state === "waiting" ? 0.3 : 0.15);
    ctx.beginPath();
    ctx.arc(dx, 175, 44, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = this.panelAlpha;

    ctx.fillStyle = "rgba(255,255,255,0.55)";
    ctx.font = "11px 'Segoe UI', sans-serif";
    ctx.textAlign = "center";
    const hint = q.state === "waiting" ? "HOLD SPACE / MOUSE TO GUARD"
      : q.state === "holding" ? "RELEASE AS THE BLOW LANDS!"
      : "";
    if (hint) ctx.fillText(hint, (xa + xb) / 2, y + 34);
  }

  drawFighter(f) {
    const ctx = this.ctx;
    const x = this.fighterX(f);
    const y = 175;
    const colors = TEAM_COLORS[f.unit.team];
    ctx.save();
    ctx.globalAlpha = this.panelAlpha * f.alpha;
    ctx.fillStyle = colors.main;
    ctx.strokeStyle = colors.dark;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(x, y, 34, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#fff";
    ctx.font = "bold 34px 'Segoe UI', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(f.unit.cls.icon, x, y);
    ctx.restore();
  }

  drawHpBox(f, bx) {
    const ctx = this.ctx;
    const by = 232;
    const w = VIGNETTE.W / 2 - 30;
    roundRect(ctx, bx, by, w, 58, 8, "rgba(12,14,19,0.92)", "#3a3f4c");
    ctx.fillStyle = "#e8e8ec";
    ctx.font = "bold 14px 'Segoe UI', sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillText(`${f.unit.name}`, bx + 10, by + 18);
    ctx.fillStyle = "#9aa0ae";
    ctx.font = "11px 'Segoe UI', sans-serif";
    ctx.fillText(`${f.unit.cls.name} · ${f.unit.cls.weapon}`, bx + 10, by + 33);
    const barW = w - 62;
    ctx.fillStyle = "rgba(0,0,0,0.6)";
    ctx.fillRect(bx + 10, by + 40, barW, 10);
    const frac = Math.max(0, f.shownHp / f.unit.maxHp);
    ctx.fillStyle = frac > 0.5 ? "#5ad35a" : frac > 0.25 ? "#e8c33a" : "#e05050";
    ctx.fillRect(bx + 11, by + 41, (barW - 2) * frac, 8);
    ctx.fillStyle = "#e8e8ec";
    ctx.font = "bold 13px 'Segoe UI', sans-serif";
    ctx.textAlign = "right";
    ctx.fillText(`${Math.ceil(f.shownHp)}/${f.unit.maxHp}`, bx + w - 10, by + 50);
  }

  // --- lifecycle --------------------------------------------------------

  skip() {
    if (!this.playing || this.interactive) return; // no skipping an addition
    this.finish();
  }

  finish() {
    // Interactive battles must always commit their result, even on abort
    // paths that reach finish() early.
    if (this.interactive && this.game && !this.finishCalled) {
      this.finishCalled = true;
      this.game.finishBattle(this.battle.attacker);
    }
    this.playing = false;
    this.canvas.classList.add("hidden");
    if (this.onDone) {
      const done = this.onDone;
      this.onDone = null;
      done();
    }
  }

  // Hard stop (used by Reset): hide without firing the continuation.
  abort() {
    this.playing = false;
    this.interactive = false;
    this.onDone = null;
    this.canvas.classList.add("hidden");
  }
}

function easeOutQuad(t) { return 1 - (1 - t) * (1 - t); }

function roundRect(ctx, x, y, w, h, r, fill, stroke) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
  ctx.fillStyle = fill;
  ctx.fill();
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 2;
    ctx.stroke();
  }
}
