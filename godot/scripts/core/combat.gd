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


# Resolve a full battle. Returns an array of event Dictionaries for the
# log / renderer. Order: attacker strike, counter, follow-up by the faster.
static func resolve_battle(attacker: Unit, defender: Unit,
		rng: RandomNumberGenerator) -> Array:
	var events: Array = []

	var strike := func(a: Unit, d: Unit) -> void:
		if a.hp <= 0 or d.hp <= 0:
			return
		var s := strike_stats(a, d)
		if rng.randi_range(0, 99) >= int(s["hit"]):
			events.append({"type": "miss", "from": a, "to": d})
			return
		var is_crit: bool = rng.randi_range(0, 99) < int(s["crit"])
		var dmg: int = s["dmg"] * 3 if is_crit else s["dmg"]
		d.hp = maxi(0, d.hp - dmg)
		events.append({
			"type": "hit", "from": a, "to": d,
			"dmg": dmg, "crit": is_crit, "killed": d.hp == 0,
		})

	strike.call(attacker, defender)
	if defender.hp > 0 and can_counter(defender, attacker):
		strike.call(defender, attacker)
	if doubles(attacker, defender):
		strike.call(attacker, defender)
	elif defender.hp > 0 and can_counter(defender, attacker) and doubles(defender, attacker):
		strike.call(defender, attacker)
	return events


static func resolve_heal(healer: Unit, target: Unit) -> Dictionary:
	var amount := mini(healer.u_class.heal_power + healer.u_class.magic_power,
			target.max_hp - target.hp)
	target.hp += amount
	return {"type": "heal", "from": healer, "to": target, "amount": amount}
