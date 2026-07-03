// ---------------------------------------------------------------
// Game state: units, turn order, actions, win conditions.
// Engine-agnostic — the renderer and input layer sit on top.
// ---------------------------------------------------------------

let nextUnitId = 1;

function makeUnit(className, x, y, personalName, team) {
  const cls = CLASSES[className];
  return {
    id: nextUnitId++,
    name: personalName,
    cls,
    team,            // "player" | "enemy"
    x, y,
    hp: cls.hp,
    maxHp: cls.hp,
    acted: false,    // has this unit taken its action this turn?
  };
}

class Game {
  constructor() {
    this.reset();
  }

  reset() {
    nextUnitId = 1;
    this.units = [
      ...PLAYER_ARMY.map(([c, x, y, n]) => makeUnit(c, x, y, n, "player")),
      ...ENEMY_ARMY.map(([c, x, y, n]) => makeUnit(c, x, y, n, "enemy")),
    ];
    this.turn = "player";
    this.turnCount = 1;
    this.winner = null;
    this.log = [];
    this.rng = Math.random;
    this.addLog(`— Turn 1: Player phase —`, "phase");
  }

  addLog(text, kind = "info") {
    this.log.push({ text, kind, turn: this.turnCount });
    if (this.log.length > 200) this.log.shift();
  }

  livingUnits(team) {
    return this.units.filter(u => u.hp > 0 && (!team || u.team === team));
  }

  unitAt(x, y) {
    return this.units.find(u => u.hp > 0 && u.x === x && u.y === y) || null;
  }

  // --- Actions ------------------------------------------------------------

  moveUnit(unit, x, y) {
    unit.x = x;
    unit.y = y;
  }

  attack(attacker, defender) {
    const events = resolveBattle(attacker, defender, this.rng);
    for (const ev of events) {
      if (ev.type === "miss") {
        this.addLog(`${ev.from.name} (${ev.from.cls.name}) misses ${ev.to.name}.`, "miss");
      } else {
        const critText = ev.crit ? " CRITICAL!" : "";
        this.addLog(
          `${ev.from.name} (${ev.from.cls.name}) hits ${ev.to.name} for ${ev.dmg}.${critText}`,
          ev.from.team === "player" ? "player-hit" : "enemy-hit");
        if (ev.killed) this.addLog(`${ev.to.name} falls!`, "death");
      }
    }
    attacker.acted = true;
    this.checkWinner();
    return events;
  }

  heal(healer, target) {
    const ev = resolveHeal(healer, target);
    this.addLog(`${healer.name} heals ${target.name} for ${ev.amount} HP.`, "heal");
    healer.acted = true;
    return ev;
  }

  wait(unit) {
    unit.acted = true;
  }

  // --- Turn flow ----------------------------------------------------------

  endTurn() {
    for (const u of this.units) u.acted = false;
    if (this.turn === "player") {
      this.turn = "enemy";
      this.addLog(`— Turn ${this.turnCount}: Enemy phase —`, "phase");
    } else {
      this.turn = "player";
      this.turnCount++;
      if (this.turnCount > 60) {
        this.decideByAttrition();
        return;
      }
      this.addLog(`— Turn ${this.turnCount}: Player phase —`, "phase");
    }
  }

  // Safety valve for the simulation: if nobody routs the other side within
  // 60 turns (e.g. only healers remain), decide by units left, then HP.
  decideByAttrition() {
    const score = team => {
      const alive = this.livingUnits(team);
      return alive.length * 1000 + alive.reduce((s, u) => s + u.hp, 0);
    };
    this.winner = score("player") >= score("enemy") ? "player" : "enemy";
    this.addLog(`★ Turn limit reached — ${this.winner} army wins by attrition.`, "victory");
  }

  allActed(team) {
    return this.livingUnits(team).every(u => u.acted);
  }

  checkWinner() {
    if (this.livingUnits("enemy").length === 0) {
      this.winner = "player";
      this.addLog(`★ Victory! The player army routs the enemy on turn ${this.turnCount}.`, "victory");
    } else if (this.livingUnits("player").length === 0) {
      this.winner = "enemy";
      this.addLog(`★ Defeat. The enemy army wins on turn ${this.turnCount}.`, "victory");
    }
  }

  // Execute one AI-planned action for the next unacted unit on `team`.
  // Returns the unit that acted, or null if the whole team has acted.
  stepAI(team) {
    if (this.winner) return null;
    const unit = this.livingUnits(team).find(u => !u.acted);
    if (!unit) return null;

    const plan = planAction(unit, this.units, this.turnCount);
    if (plan.move) this.moveUnit(unit, plan.move.x, plan.move.y);
    if (plan.attack)      this.attack(unit, plan.attack);
    else if (plan.heal)   this.heal(unit, plan.heal);
    else                  this.wait(unit);
    return unit;
  }
}
