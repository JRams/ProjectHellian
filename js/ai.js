// ---------------------------------------------------------------
// AI: plans one action for a single unit. Used for the enemy team
// and for both teams in auto-simulation mode. Engine-agnostic.
// ---------------------------------------------------------------

// Expected damage of one full battle, used for scoring options.
function expectedExchange(attacker, defender) {
  const f = battleForecast(attacker, defender);
  const hits = h => h.dmg * (h.hit / 100) * (h.double ? 2 : 1);
  const dealt = hits(f.atk);
  const taken = f.def ? hits(f.def) : 0;
  return { dealt, taken, forecast: f };
}

// Set of tile keys any enemy of `unit` could attack next turn.
function enemyThreatTiles(unit, units) {
  const threat = new Set();
  for (const e of units) {
    if (e.hp <= 0 || e.team === unit.team) continue;
    if (!e.cls.range.length) continue;
    const reach = reachableTiles(e, units);
    for (const node of reach.values()) {
      if (node.passOnly) continue;
      for (const r of e.cls.range) {
        // all tiles at manhattan distance r from this standing spot
        for (let dx = -r; dx <= r; dx++) {
          const dy = r - Math.abs(dx);
          for (const sy of dy === 0 ? [0] : [-1, 1]) {
            const tx = node.x + dx, ty = node.y + sy * dy;
            if (inBounds(tx, ty)) threat.add(key(tx, ty));
          }
        }
      }
    }
  }
  return threat;
}

// Decide the best action for `unit`. Returns one of:
//   { move: {x,y}, attack: targetUnit }
//   { move: {x,y}, heal: targetUnit }
//   { move: {x,y} }            (reposition toward the front)
//   { move: null }             (nothing useful to do)
function planAction(unit, units, turnCount = 1) {
  const reachable = reachableTiles(unit, units);
  const enemies = units.filter(u => u.hp > 0 && u.team !== unit.team);
  if (enemies.length === 0) return { move: null };

  // --- Healers: heal the most wounded reachable ally ---------------------
  if (unit.cls.healRange && unit.cls.healRange.length) {
    let best = null;
    for (const node of reachable.values()) {
      if (node.passOnly) continue;
      for (const ally of healTargetsFrom(unit, node.x, node.y, units)) {
        const need = ally.maxHp - ally.hp;
        if (!best || need > best.need) {
          best = { move: { x: node.x, y: node.y }, heal: ally, need };
        }
      }
    }
    if (best) return { move: best.move, heal: best.heal };
    return retreatOrFollow(unit, units, reachable, enemies);
  }

  // --- Combat units: score every (tile, target) attack option ------------
  let best = null;
  for (const node of reachable.values()) {
    if (node.passOnly) continue;
    for (const target of targetsFrom(unit, node.x, node.y, units)) {
      // Evaluate the exchange as if standing on the candidate tile.
      const ox = unit.x, oy = unit.y;
      unit.x = node.x; unit.y = node.y;
      const ex = expectedExchange(unit, target);
      unit.x = ox; unit.y = oy;

      let score = ex.dealt - ex.taken * 0.6;
      if (ex.dealt >= target.hp) score += 50;                    // likely kill
      if (ex.taken >= unit.hp) score -= 40;                      // likely death
      score += terrainAt(node.x, node.y).avoid * 0.05;           // prefer cover
      if (!best || score > best.score) {
        best = { move: { x: node.x, y: node.y }, attack: target, score };
      }
    }
  }
  if (best && best.score > -5) return { move: best.move, attack: best.attack };

  // --- No good attack: advance toward the nearest enemy ------------------
  return advanceToward(unit, units, reachable, enemies, turnCount);
}

// Advance toward the nearest enemy, but avoid stopping inside enemy threat
// range and don't outrun the rest of the army. The caution fades as turns
// pass so a stand-off at a chokepoint eventually breaks.
function advanceToward(unit, units, reachable, enemies, turnCount) {
  let target = null, bestDist = Infinity;
  for (const e of enemies) {
    const d = manhattan(unit.x, unit.y, e.x, e.y);
    if (d < bestDist) { bestDist = d; target = e; }
  }

  const threat = enemyThreatTiles(unit, units);
  const threatPenalty = Math.max(0, 7 - turnCount);       // fearless by turn 7
  // Cohesion anchors only to allies that can fight (a fleeing healer must
  // not pin the army in place), and it fades in the late game so the last
  // survivors still hunt each other down.
  const anchors = turnCount < 8
    ? units.filter(u => u.hp > 0 && u.team === unit.team && u !== unit && u.cls.range.length)
    : [];

  let best = null;
  for (const node of reachable.values()) {
    if (node.passOnly) continue;
    let score = -manhattan(node.x, node.y, target.x, target.y);
    if (threat.has(key(node.x, node.y))) score -= threatPenalty;
    if (anchors.length) {
      let allyDist = Infinity;
      for (const a of anchors) allyDist = Math.min(allyDist, manhattan(node.x, node.y, a.x, a.y));
      score -= Math.max(0, allyDist - 3) * 1.5;
    }
    score -= node.cost * 0.01; // tie-break: spend less movement
    if (!best || score > best.score) best = { node, score };
  }
  if (!best || (best.node.x === unit.x && best.node.y === unit.y)) {
    return { move: null };
  }
  return { move: { x: best.node.x, y: best.node.y } };
}

// Healers with nobody to heal: stay near allies, away from enemies.
function retreatOrFollow(unit, units, reachable, enemies) {
  const allies = units.filter(u => u.hp > 0 && u.team === unit.team && u !== unit);
  if (allies.length === 0) return { move: null };
  let best = null;
  for (const node of reachable.values()) {
    if (node.passOnly) continue;
    let allyDist = Infinity, enemyDist = Infinity;
    for (const a of allies) allyDist = Math.min(allyDist, manhattan(node.x, node.y, a.x, a.y));
    for (const e of enemies) enemyDist = Math.min(enemyDist, manhattan(node.x, node.y, e.x, e.y));
    const score = enemyDist * 1.5 - allyDist;
    if (!best || score > best.score) best = { node, score };
  }
  if (!best || (best.node.x === unit.x && best.node.y === unit.y)) return { move: null };
  return { move: { x: best.node.x, y: best.node.y } };
}
