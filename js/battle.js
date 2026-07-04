// ---------------------------------------------------------------
// Battle vignette: the Fire Emblem style combat cut-in.
// Combat is resolved instantly by the core (combat.js); this overlay
// REPLAYS the recorded events as an animation — lunges, damage popups,
// draining HP bars, crit flashes, dodges, deaths. Click to skip.
// ---------------------------------------------------------------

const VIGNETTE = {
  W: 560, H: 300,
  INTRO: 0.35,       // seconds: panel fade-in, fighters slide in
  STRIKE: 0.95,      // seconds per attack event
  IMPACT_AT: 0.35,   // fraction of a strike beat where the blow lands
  OUTRO: 0.6,
  OUTRO_KILL: 1.1,
  HP_DRAIN_RATE: 30, // HP per second the displayed bar drains
};

class BattleVignette {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    canvas.width = VIGNETTE.W;
    canvas.height = VIGNETTE.H;
    this.playing = false;
    canvas.addEventListener("click", () => this.skip());
    this.tick = this.tick.bind(this);
  }

  // battle = { attacker, defender, preHp: {attacker, defender}, events }
  // timeScale > 1 plays the whole vignette proportionally faster (used by
  // the Fast simulation speed so animations don't dominate the run time).
  play(battle, onDone, timeScale = 1) {
    this.battle = battle;
    this.onDone = onDone;
    this.timeScale = timeScale;
    this.playing = true;
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

    const killed = battle.events.some(e => e.killed);
    this.beats = [{ type: "intro", dur: VIGNETTE.INTRO }];
    for (const ev of battle.events) {
      this.beats.push({ type: "strike", dur: VIGNETTE.STRIKE, ev, applied: false });
    }
    this.beats.push({ type: "outro", dur: killed ? VIGNETTE.OUTRO_KILL : VIGNETTE.OUTRO, deathShown: false });

    this.beatIndex = 0;
    this.lastTime = performance.now();
    this.beatElapsed = 0;
    this.canvas.classList.remove("hidden");
    requestAnimationFrame(this.tick);
  }

  fighterOf(unit) { return this.left.unit === unit ? this.left : this.right; }

  tick(now) {
    if (!this.playing) return;
    const dt = Math.min(0.05, (now - this.lastTime) / 1000) * this.timeScale;
    this.lastTime = now;
    this.beatElapsed += dt;

    const beat = this.beats[this.beatIndex];
    const t = Math.min(1, this.beatElapsed / beat.dur);
    this.updateBeat(beat, t, dt);
    this.updateCommon(dt);
    this.draw();

    if (t >= 1) {
      this.beatIndex++;
      this.beatElapsed = 0;
      if (this.beatIndex >= this.beats.length) { this.finish(); return; }
    }
    requestAnimationFrame(this.tick);
  }

  updateBeat(beat, t, dt) {
    if (beat.type === "intro") {
      this.panelAlpha = t;
      // fighters slide in from off-panel
      const ease = 1 - (1 - t) * (1 - t);
      this.left.x = this.left.home - 80 * (1 - ease);
      this.right.x = this.right.home + 80 * (1 - ease);
    } else if (beat.type === "strike") {
      this.panelAlpha = 1;
      const actor = this.fighterOf(beat.ev.from);
      const victim = this.fighterOf(beat.ev.to);
      // lunge toward the victim, land the blow, retreat
      const ia = VIGNETTE.IMPACT_AT;
      let lunge;
      if (t < ia) lunge = t / ia;                       // wind up + close in
      else if (t < 0.6) lunge = 1;                      // in their face
      else lunge = 1 - (t - 0.6) / 0.4;                 // retreat
      actor.lunge = Math.max(0, Math.min(1, lunge));

      if (!beat.applied && t >= ia) {
        beat.applied = true;
        this.applyImpact(beat.ev, actor, victim);
      }
    } else if (beat.type === "outro") {
      // fade out any slain fighter, then the whole panel
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
      const fadeStart = 1 - 0.35 / beat.dur;
      this.panelAlpha = t > fadeStart ? 1 - (t - fadeStart) / (1 - fadeStart) : 1;
    }
  }

  applyImpact(ev, actor, victim) {
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
    // bar
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
    if (!this.playing) return;
    this.finish();
  }

  finish() {
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
