// ---------------------------------------------------------------
// UI layer: input handling, side panels, simulation loop.
// ---------------------------------------------------------------

const game = new Game();
const canvas = document.getElementById("board");
const renderer = new Renderer(canvas);
const battleFX = new BattleVignette(document.getElementById("battlefx"));

// UI interaction state machine:
//   idle          — nothing selected
//   moveSelect    — friendly unit selected, movement range shown
//   actionSelect  — unit has moved, choose attack/heal target or wait
const ui = {
  game,
  state: "idle",
  selected: null,
  reachable: null,
  path: null,
  attackTargets: null,
  healTargets: null,
  hover: null,
  moveFrom: null,      // original position, for showing where the unit came from
  simulating: false,
  simTimer: null,
};

function redraw() {
  renderer.draw(game, ui);
  updatePanels();
}

// --- Selection helpers ----------------------------------------------------

function clearSelection() {
  ui.state = "idle";
  ui.selected = null;
  ui.reachable = null;
  ui.path = null;
  ui.attackTargets = null;
  ui.healTargets = null;
  ui.moveFrom = null;
}

function selectUnit(unit) {
  ui.selected = unit;
  ui.reachable = reachableTiles(unit, game.units);
  ui.state = "moveSelect";
}

function enterActionSelect(unit) {
  ui.state = "actionSelect";
  ui.reachable = null;
  ui.path = null;
  ui.attackTargets = targetsFrom(unit, unit.x, unit.y, game.units);
  ui.healTargets = healTargetsFrom(unit, unit.x, unit.y, game.units);
  if (ui.attackTargets.length === 0 && ui.healTargets.length === 0) {
    finishAction(unit); // nothing to do here but wait
  }
}

function finishAction(unit) {
  if (!unit.acted) game.wait(unit);
  clearSelection();
  maybeAutoEndTurn();
  redraw();
}

function maybeAutoEndTurn() {
  if (game.winner) return;
  if (game.turn === "player" && game.allActed("player")) {
    game.endTurn();
    runEnemyPhase();
  }
}

function animsOn() {
  return document.getElementById("anims").checked;
}

// If the last action was a battle and animations are on, play the vignette
// and run `done` when it closes; otherwise run `done` immediately. Every
// "what happens next" (enemy phase, next sim step) is deferred through here
// so the game never advances underneath the animation.
function playBattleThen(done) {
  const battle = game.takeLastBattle();
  if (!battle || !animsOn()) {
    done();
    return;
  }
  ui.battlePlaying = true;
  const timeScale = simDelay() <= 100 ? 3 : 1; // Fast speed: quicker vignettes
  battleFX.play(battle, () => {
    ui.battlePlaying = false;
    redraw();
    done();
  }, timeScale);
}

// Run an interactive (QTE) battle in the vignette; strikes resolve as the
// player times their presses.
function playInteractive(battle, done) {
  ui.battlePlaying = true;
  battleFX.playInteractive(battle, game, () => {
    ui.battlePlaying = false;
    redraw();
    done();
  });
}

// --- Click handling ---------------------------------------------------------

canvas.addEventListener("mousemove", e => {
  const r = canvas.getBoundingClientRect();
  const x = Math.floor((e.clientX - r.left) / r.width * MAP_W);
  const y = Math.floor((e.clientY - r.top) / r.height * MAP_H);
  ui.hover = { x, y };
  if (ui.state === "moveSelect" && ui.reachable) {
    const node = ui.reachable.get(key(x, y));
    ui.path = node && !node.passOnly ? pathTo(ui.reachable, x, y) : null;
  }
  updateForecast(x, y);
  redraw();
});

canvas.addEventListener("mouseleave", () => { ui.hover = null; redraw(); });

canvas.addEventListener("click", e => {
  if (ui.simulating || ui.battlePlaying || game.winner) return;
  if (game.turn !== "player") return;

  const r = canvas.getBoundingClientRect();
  const x = Math.floor((e.clientX - r.left) / r.width * MAP_W);
  const y = Math.floor((e.clientY - r.top) / r.height * MAP_H);
  if (!inBounds(x, y)) return;
  const clicked = game.unitAt(x, y);

  if (ui.state === "idle") {
    if (clicked && clicked.team === "player" && !clicked.acted) selectUnit(clicked);
  } else if (ui.state === "moveSelect") {
    const unit = ui.selected;
    if (clicked === unit) {
      // Clicking the unit itself: stay in place, go to action select.
      ui.moveFrom = { x: unit.x, y: unit.y };
      enterActionSelect(unit);
    } else if (clicked && clicked.team === "player" && !clicked.acted) {
      selectUnit(clicked); // switch selection
    } else {
      const node = ui.reachable.get(key(x, y));
      if (node && !node.passOnly && !clicked) {
        ui.moveFrom = { x: unit.x, y: unit.y };
        game.moveUnit(unit, x, y);
        enterActionSelect(unit);
      } else {
        clearSelection();
      }
    }
  } else if (ui.state === "actionSelect") {
    const unit = ui.selected;
    if (clicked && ui.attackTargets && ui.attackTargets.includes(clicked)) {
      if (animsOn()) {
        // Interactive battle: strikes resolve inside the vignette, with a
        // QTE per blow (offense for our strikes, brace for counters).
        const battle = game.beginBattle(unit, clicked);
        clearSelection();
        redraw();
        playInteractive(battle, () => { maybeAutoEndTurn(); redraw(); });
      } else {
        game.attack(unit, clicked);
        game.takeLastBattle(); // no vignette to replay it
        clearSelection();
        maybeAutoEndTurn();
      }
    } else if (clicked && ui.healTargets && ui.healTargets.includes(clicked)) {
      game.heal(unit, clicked);
      clearSelection();
      maybeAutoEndTurn();
    } else {
      finishAction(unit); // click elsewhere = wait
      return;
    }
  }
  redraw();
});

// --- Enemy phase (AI) -------------------------------------------------------

function runEnemyPhase() {
  redraw();
  const step = () => {
    if (game.winner) { redraw(); return; }
    // With animations on, enemy attacks become interactive battles so the
    // player can brace (red QTE) against incoming strikes and time counters.
    const acted = game.stepAI("enemy", animsOn());
    redraw();
    if (acted) {
      const pending = game.takePendingBattle();
      if (pending) playInteractive(pending, () => setTimeout(step, simDelay()));
      else playBattleThen(() => setTimeout(step, simDelay()));
    } else {
      game.endTurn();
      redraw();
    }
  };
  setTimeout(step, simDelay());
}

// --- Full simulation (AI vs AI) ----------------------------------------------

function simulateStep() {
  if (game.winner || !ui.simulating) {
    ui.simulating = false;
    document.getElementById("simulate").textContent = "▶ Simulate Battle";
    redraw();
    return;
  }
  const acted = game.stepAI(game.turn);
  if (!acted) game.endTurn();
  redraw();
  playBattleThen(() => {
    if (ui.simulating) ui.simTimer = setTimeout(simulateStep, simDelay());
  });
}

function simDelay() {
  return Number(document.getElementById("speed").value);
}

document.getElementById("simulate").addEventListener("click", () => {
  if (game.winner || ui.battlePlaying) return;
  ui.simulating = !ui.simulating;
  clearSelection();
  document.getElementById("simulate").textContent =
    ui.simulating ? "⏸ Pause" : "▶ Simulate Battle";
  if (ui.simulating) simulateStep();
  else clearTimeout(ui.simTimer);
});

document.getElementById("endturn").addEventListener("click", () => {
  if (ui.simulating || ui.battlePlaying || game.winner || game.turn !== "player") return;
  clearSelection();
  game.endTurn();
  runEnemyPhase();
});

document.getElementById("reset").addEventListener("click", () => {
  ui.simulating = false;
  clearTimeout(ui.simTimer);
  battleFX.abort();          // drops the pending continuation on purpose:
  ui.battlePlaying = false;  // reset() rebuilds all state below
  document.getElementById("simulate").textContent = "▶ Simulate Battle";
  clearSelection();
  game.reset();
  redraw();
});

// --- Side panels --------------------------------------------------------------

function updateForecast(x, y) {
  const el = document.getElementById("forecast");
  if (ui.state === "actionSelect" && ui.attackTargets) {
    const target = game.unitAt(x, y);
    if (target && ui.attackTargets.includes(target)) {
      const f = battleForecast(ui.selected, target);
      const a = f.atk;
      let html = `<h3>Battle Forecast</h3>
        <div class="fc-row"><span>${ui.selected.name} → ${target.name}</span></div>
        <div class="fc-row">Dmg ${a.dmg}${a.double ? " ×2" : ""} · Hit ${a.hit}% · Crit ${a.crit}%</div>`;
      if (f.def) {
        const d = f.def;
        html += `<div class="fc-row counter">Counter: Dmg ${d.dmg}${d.double ? " ×2" : ""} · Hit ${d.hit}% · Crit ${d.crit}%</div>`;
      } else {
        html += `<div class="fc-row counter">No counterattack</div>`;
      }
      el.innerHTML = html;
      el.classList.remove("hidden");
      return;
    }
  }
  el.classList.add("hidden");
}

function updatePanels() {
  // Turn banner
  const banner = document.getElementById("turnbanner");
  if (game.winner) {
    banner.textContent = game.winner === "player" ? "★ VICTORY — Player army wins!" : "★ DEFEAT — Enemy army wins!";
    banner.className = "banner " + (game.winner === "player" ? "banner-player" : "banner-enemy");
  } else {
    banner.textContent = `Turn ${game.turnCount} — ${game.turn === "player" ? "Player" : "Enemy"} Phase`;
    banner.className = "banner " + (game.turn === "player" ? "banner-player" : "banner-enemy");
  }

  // Unit info (hovered, else selected)
  const info = document.getElementById("unitinfo");
  const shown = (ui.hover && game.unitAt(ui.hover.x, ui.hover.y)) || ui.selected;
  if (shown) {
    const c = shown.cls;
    info.innerHTML = `
      <h3><span class="dot ${shown.team}"></span>${shown.name} — ${c.name}</h3>
      <div class="stat-grid">
        <span>HP ${shown.hp}/${shown.maxHp}</span><span>Mov ${c.mov}</span>
        <span>Str ${c.str}</span><span>Mag ${c.mag}</span>
        <span>Skl ${c.skl}</span><span>Spd ${c.spd}</span>
        <span>Def ${c.def}</span><span>Res ${c.res}</span>
      </div>
      <div class="weapon">${c.weapon}${c.range.length ? ` (rng ${c.range.join(",")})` : ""}</div>
      <div class="desc">${c.desc}</div>`;
  } else if (ui.hover && inBounds(ui.hover.x, ui.hover.y)) {
    const t = terrainAt(ui.hover.x, ui.hover.y);
    info.innerHTML = `<h3>${t.name}</h3>
      <div class="desc">Move cost ${t.cost === Infinity ? "—" : t.cost} · +${t.def} Def · +${t.avoid} Avoid</div>`;
  } else {
    info.innerHTML = `<h3>Grimwater Crossing</h3>
      <div class="desc">Select a blue unit to move it, or press Simulate to watch the AI fight it out.</div>`;
  }

  // Battle log
  const logEl = document.getElementById("log");
  logEl.innerHTML = game.log.slice(-40).map(l => `<div class="log-${l.kind}">${l.text}</div>`).join("");
  logEl.scrollTop = logEl.scrollHeight;

  // Army counts
  document.getElementById("counts").textContent =
    `Player ${game.livingUnits("player").length} · Enemy ${game.livingUnits("enemy").length}`;
}

redraw();
