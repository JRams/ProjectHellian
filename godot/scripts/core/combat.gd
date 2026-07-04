# Port of js/combat.js — Fire Emblem style damage / hit / crit / doubling.
# The only structural change: randomness comes from an injected
# RandomNumberGenerator so simulations can be seeded and reproduced,
# instead of JS's global Math.random.
class_name Combat
extends RefCounted


static func unit_avoid(unit: Unit) -> int:
	return unit.u_class.speed * 2 + Grid.terrain_at(unit.pos).avoid


# One direction of a battle: what happens when `atk` strikes `def`.
static func strike_stats(atk: Unit, def: Unit) -> Dictionary:
	var magic := atk.u_class.is_magic
	var power: int = (atk.u_class.magic_power if magic else atk.u_class.strength) \
			+ atk.u_class.might
	var guard: int = (def.u_class.resistance if magic else def.u_class.defense) \
			+ Grid.terrain_at(def.pos).defense
	var dmg := maxi(0, power - guard)
	var hit := clampi(atk.u_class.hit + atk.u_class.skill * 2 - unit_avoid(def), 5, 100)
	var crit := maxi(0, atk.u_class.crit + atk.u_class.skill / 2 - def.u_class.speed)
	return {"dmg": dmg, "hit": hit, "crit": crit}


static func can_counter(defender: Unit, attacker: Unit) -> bool:
	var d := Grid.manhattan(defender.pos, attacker.pos)
	return defender.u_class.attack_range.has(d)


static func doubles(a: Unit, b: Unit) -> bool:
	return a.u_class.speed >= b.u_class.speed + 4


# Preview shown before committing to an attack.
static func battle_forecast(attacker: Unit, defender: Unit) -> Dictionary:
	var atk := strike_stats(attacker, defender)
	atk["double"] = doubles(attacker, defender)
	var def: Variant = null
	if can_counter(defender, attacker):
		def = strike_stats(defender, attacker)
		def["double"] = doubles(defender, attacker)
	return {"atk": atk, "def": def}


# The full strike order of a battle: attacker, counter (if the defender's
# range allows), then a follow-up by whichever side doubles. Strikes whose
# actor or target has died by the time they come up are skipped at
# resolution time.
static func plan_strikes(attacker: Unit, defender: Unit) -> Array:
	var strikes: Array = [{"actor": attacker, "target": defender}]
	var counter := can_counter(defender, attacker)
	if counter:
		strikes.append({"actor": defender, "target": attacker})
	if doubles(attacker, defender):
		strikes.append({"actor": attacker, "target": defender})
	elif counter and doubles(defender, attacker):
		strikes.append({"actor": defender, "target": attacker})
	return strikes


# Resolve ONE strike, mutating the target's HP.
# off_mult scales damage dealt (the attacker's QTE result); def_mult scales
# damage taken (the defender's QTE result). Both default to neutral so
# AI-vs-AI battles behave exactly as before QTEs existed.
# `qte` is an optional grade label carried into the event for the log.
static func resolve_strike(actor: Unit, target: Unit, rng: RandomNumberGenerator,
		off_mult := 1.0, def_mult := 1.0, qte := "") -> Dictionary:
	var s := strike_stats(actor, target)
	if rng.randi_range(0, 99) >= int(s["hit"]):
		return {"type": "miss", "from": actor, "to": target, "qte": qte}
	var is_crit: bool = rng.randi_range(0, 99) < int(s["crit"])
	var base: int = s["dmg"] * 3 if is_crit else s["dmg"]
	var dmg := maxi(0, roundi(base * off_mult * def_mult))
	target.hp = maxi(0, target.hp - dmg)
	return {"type": "hit", "from": actor, "to": target,
		"dmg": dmg, "crit": is_crit, "killed": target.hp == 0, "qte": qte}


# Resolve a full battle instantly at neutral multipliers (AI vs AI, or
# animations disabled). Returns the event list for the log / replay.
static func resolve_battle(attacker: Unit, defender: Unit,
		rng: RandomNumberGenerator) -> Array:
	var events: Array = []
	for s: Dictionary in plan_strikes(attacker, defender):
		if s["actor"].hp <= 0 or s["target"].hp <= 0:
			continue
		events.append(resolve_strike(s["actor"], s["target"], rng))
	return events


static func resolve_heal(healer: Unit, target: Unit) -> Dictionary:
	var amount := mini(healer.u_class.heal_power + healer.u_class.magic_power,
			target.max_hp - target.hp)
	target.hp += amount
	return {"type": "heal", "from": healer, "to": target, "amount": amount}
