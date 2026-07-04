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

// The full strike order of a battle: attacker, counter (if the defender's
// range allows), then a follow-up by whichever side doubles. Strikes whose
// actor or target has died by the time they come up are skipped at
// resolution time.
function planStrikes(attacker, defender) {
  const strikes = [{ actor: attacker, target: defender }];
  const counter = canCounter(defender, attacker);
  if (counter) strikes.push({ actor: defender, target: attacker });
  if (doubles(attacker, defender)) {
    strikes.push({ actor: attacker, target: defender });
  } else if (counter && doubles(defender, attacker)) {
    strikes.push({ actor: defender, target: attacker });
  }
  return strikes;
}

// Resolve ONE strike, mutating the target's HP.
// offMult scales damage dealt (the attacker's QTE result); defMult scales
// damage taken (the defender's QTE result). Both default to neutral so
// AI-vs-AI battles behave exactly as before QTEs existed.
// `qte` is an optional grade label carried into the event for the log.
function resolveStrike(actor, target, rng, offMult = 1, defMult = 1, qte = null) {
  const s = strikeStats(actor, target);
  if (Math.floor(rng() * 100) >= s.hit) {
    return { type: "miss", from: actor, to: target, qte };
  }
  const isCrit = Math.floor(rng() * 100) < s.crit;
  const dmg = Math.max(0, Math.round((isCrit ? s.dmg * 3 : s.dmg) * offMult * defMult));
  target.hp = Math.max(0, target.hp - dmg);
  return { type: "hit", from: actor, to: target, dmg, crit: isCrit,
    killed: target.hp === 0, qte };
}

// Resolve a full battle instantly at neutral multipliers (AI vs AI, or
// animations disabled). Returns the event list for the log / replay.
function resolveBattle(attacker, defender, rng) {
  const events = [];
  for (const s of planStrikes(attacker, defender)) {
    if (s.actor.hp <= 0 || s.target.hp <= 0) continue;
    events.push(resolveStrike(s.actor, s.target, rng));
  }
  return events;
}

function resolveHeal(healer, target) {
  const amount = Math.min(healer.cls.healPower + healer.cls.mag, target.maxHp - target.hp);
  target.hp += amount;
  return { type: "heal", from: healer, to: target, amount };
}
