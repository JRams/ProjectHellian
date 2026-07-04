# Port of js/ai.js — plans one action for a single unit. Used for the enemy
# team and for both teams in auto-simulation mode.
# A plan is a Dictionary: { "move": Vector2i or null,
#                           "attack": Unit or null, "heal": Unit or null }
class_name AI
extends RefCounted


static func make_plan(move: Variant = null, attack: Unit = null, heal: Unit = null) -> Dictionary:
	return {"move": move, "attack": attack, "heal": heal}


# Expected damage of one full battle, used for scoring options.
static func expected_exchange(attacker: Unit, defender: Unit) -> Dictionary:
	var f := Combat.battle_forecast(attacker, defender)
	var hits := func(h: Dictionary) -> float:
		return h["dmg"] * (h["hit"] / 100.0) * (2.0 if h["double"] else 1.0)
	var dealt: float = hits.call(f["atk"])
	var taken: float = hits.call(f["def"]) if f["def"] != null else 0.0
	return {"dealt": dealt, "taken": taken}


# Set of tile positions any enemy of `unit` could attack next turn.
# Returned as Dictionary[Vector2i -> true] (GDScript has no built-in Set).
static func enemy_threat_tiles(unit: Unit, units: Array) -> Dictionary:
	var threat := {}
	for e: Unit in units:
		if not e.is_alive() or e.team == unit.team or not e.can_fight():
			continue
		var reach := Grid.reachable_tiles(e, units)
		for node: Dictionary in reach.values():
			if node["pass_only"]:
				continue
			for r: int in e.u_class.attack_range:
				# all tiles at manhattan distance r from this standing spot
				for dx in range(-r, r + 1):
					var dy: int = r - absi(dx)
					var sides: Array = [0] if dy == 0 else [-1, 1]
					for sy: int in sides:
						var t: Vector2i = node["pos"] + Vector2i(dx, sy * dy)
						if Grid.in_bounds(t):
							threat[t] = true
	return threat


# Decide the best action for `unit`.
static func plan_action(unit: Unit, units: Array, turn_count: int = 1) -> Dictionary:
	var reachable := Grid.reachable_tiles(unit, units)
	var enemies: Array = units.filter(
			func(u: Unit) -> bool: return u.is_alive() and u.team != unit.team)
	if enemies.is_empty():
		return make_plan()

	# --- Healers: heal the most wounded reachable ally ---------------------
	if not unit.u_class.heal_range.is_empty():
		var best_heal: Dictionary = {}
		for node: Dictionary in reachable.values():
			if node["pass_only"]:
				continue
			for ally: Unit in Grid.heal_targets_from(unit, node["pos"], units):
				var need := ally.max_hp - ally.hp
				if best_heal.is_empty() or need > best_heal["need"]:
					best_heal = {"pos": node["pos"], "heal": ally, "need": need}
		if not best_heal.is_empty():
			return make_plan(best_heal["pos"], null, best_heal["heal"])
		return retreat_or_follow(unit, units, reachable, enemies)

	# --- Combat units: score every (tile, target) attack option ------------
	var best: Dictionary = {}
	for node: Dictionary in reachable.values():
		if node["pass_only"]:
			continue
		for target: Unit in Grid.targets_from(unit, node["pos"], units):
			# Evaluate the exchange as if standing on the candidate tile.
			var original := unit.pos
			unit.pos = node["pos"]
			var ex := expected_exchange(unit, target)
			unit.pos = original

			var score: float = ex["dealt"] - ex["taken"] * 0.6
			if ex["dealt"] >= target.hp:
				score += 50.0  # likely kill
			if ex["taken"] >= unit.hp:
				score -= 40.0  # likely death
			score += Grid.terrain_at(node["pos"]).avoid * 0.05  # prefer cover
			if best.is_empty() or score > best["score"]:
				best = {"pos": node["pos"], "attack": target, "score": score}
	if not best.is_empty() and best["score"] > -5.0:
		return make_plan(best["pos"], best["attack"])

	# --- No good attack: advance toward the nearest enemy ------------------
	return advance_toward(unit, units, reachable, enemies, turn_count)


# Advance toward the nearest enemy, but avoid stopping inside enemy threat
# range and don't outrun the rest of the army. The caution fades as turns
# pass so a stand-off at a chokepoint eventually breaks.
static func advance_toward(unit: Unit, units: Array, reachable: Dictionary,
		enemies: Array, turn_count: int) -> Dictionary:
	var target: Unit = null
	var best_dist := 999999
	for e: Unit in enemies:
		var d := Grid.manhattan(unit.pos, e.pos)
		if d < best_dist:
			best_dist = d
			target = e

	var threat := enemy_threat_tiles(unit, units)
	var threat_penalty := maxf(0.0, 7.0 - turn_count)  # fearless by turn 7
	# Cohesion anchors only to allies that can fight (a fleeing healer must
	# not pin the army in place), and it fades in the late game so the last
	# survivors still hunt each other down.
	var anchors: Array = []
	if turn_count < 8:
		anchors = units.filter(func(u: Unit) -> bool:
			return u.is_alive() and u.team == unit.team and u != unit and u.can_fight())

	var best: Dictionary = {}
	for node: Dictionary in reachable.values():
		if node["pass_only"]:
			continue
		var score := -float(Grid.manhattan(node["pos"], target.pos))
		if threat.has(node["pos"]):
			score -= threat_penalty
		if not anchors.is_empty():
			var ally_dist := 999999
			for a: Unit in anchors:
				ally_dist = mini(ally_dist, Grid.manhattan(node["pos"], a.pos))
			score -= maxf(0.0, ally_dist - 3.0) * 1.5
		score -= node["cost"] * 0.01  # tie-break: spend less movement
		if best.is_empty() or score > best["score"]:
			best = {"pos": node["pos"], "score": score}
	if best.is_empty() or best["pos"] == unit.pos:
		return make_plan()
	return make_plan(best["pos"])


# Healers with nobody to heal: stay near allies, away from enemies.
static func retreat_or_follow(unit: Unit, units: Array, reachable: Dictionary,
		enemies: Array) -> Dictionary:
	var allies: Array = units.filter(func(u: Unit) -> bool:
		return u.is_alive() and u.team == unit.team and u != unit)
	if allies.is_empty():
		return make_plan()
	var best: Dictionary = {}
	for node: Dictionary in reachable.values():
		if node["pass_only"]:
			continue
		var ally_dist := 999999
		var enemy_dist := 999999
		for a: Unit in allies:
			ally_dist = mini(ally_dist, Grid.manhattan(node["pos"], a.pos))
		for e: Unit in enemies:
			enemy_dist = mini(enemy_dist, Grid.manhattan(node["pos"], e.pos))
		var score := enemy_dist * 1.5 - ally_dist
		if best.is_empty() or score > best["score"]:
			best = {"pos": node["pos"], "score": score}
	if best.is_empty() or best["pos"] == unit.pos:
		return make_plan()
	return make_plan(best["pos"])
