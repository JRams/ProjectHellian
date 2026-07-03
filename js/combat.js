// ---------------------------------------------------------------
// Combat resolution: Fire Emblem style damage / hit / crit / doubling.
// Engine-agnostic.
// ---------------------------------------------------------------

function unitAvoid(unit) {
  return unit.cls.spd * 2 + terrainAt(unit.x, unit.y).avoid;
}

// One direction of a battle: what happens when `atk` strikes `def`.
function strikeStats(atk, def) {
  const magic = !!atk.cls.magic;
  const power = (magic ? atk.cls.mag : atk.cls.str) + atk.cls.mt;
  const guard = (magic ? def.cls.res : def.cls.def) + terrainAt(def.x, def.y).def;
  const dmg = Math.max(0, power - guard);
  const hit = Math.max(5, Math.min(100, atk.cls.hit + atk.cls.skl * 2 - unitAvoid(def)));
  const crit = Math.max(0, atk.cls.crit + Math.floor(atk.cls.skl / 2) - def.cls.spd);
  return { dmg, hit, crit };
}

function canCounter(defender, attacker) {
  const d = manhattan(defender.x, defender.y, attacker.x, attacker.y);
  return defender.cls.range.includes(d);
}

function doubles(a, b) {
  return a.cls.spd >= b.cls.spd + 4;
}

// Preview shown before committing to an attack.
function battleForecast(attacker, defender) {
  const atk = strikeStats(attacker, defender);
  const counter = canCounter(defender, attacker);
  const def = counter ? strikeStats(defender, attacker) : null;
  return {
    atk: { ...atk, double: doubles(attacker, defender) },
    def: def ? { ...def, double: doubles(defender, attacker) } : null,
  };
}

// Resolve a full battle. Returns an array of event objects for the log /
// renderer. Order: attacker strike, counter, then follow-up by the faster.
function resolveBattle(attacker, defender, rng) {
  const events = [];
  const roll = () => Math.floor(rng() * 100);

  function strike(a, d) {
    if (a.hp <= 0 || d.hp <= 0) return;
    const s = strikeStats(a, d);
    if (roll() >= s.hit) {
      events.push({ type: "miss", from: a, to: d });
      return;
    }
    const isCrit = roll() < s.crit;
    const dmg = isCrit ? s.dmg * 3 : s.dmg;
    d.hp = Math.max(0, d.hp - dmg);
    events.push({ type: "hit", from: a, to: d, dmg, crit: isCrit, killed: d.hp === 0 });
  }

  strike(attacker, defender);
  if (defender.hp > 0 && canCounter(defender, attacker)) strike(defender, attacker);
  if (doubles(attacker, defender)) strike(attacker, defender);
  else if (defender.hp > 0 && canCounter(defender, attacker) && doubles(defender, attacker)) {
    strike(defender, attacker);
  }
  return events;
}

function resolveHeal(healer, target) {
  const amount = Math.min(healer.cls.healPower + healer.cls.mag, target.maxHp - target.hp);
  target.hp += amount;
  return { type: "heal", from: healer, to: target, amount };
}
