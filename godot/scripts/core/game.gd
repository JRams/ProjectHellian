# Port of js/game.js — game state, turn flow, actions, win conditions.
# One deliberate Godot-ism: the class emits a SIGNAL whenever a log entry is
# added. The UI subscribes to it, so the core never touches a UI node — the
# same decoupling the JS version got by having main.js poll game.log.
class_name Game
extends RefCounted

signal log_added(entry: Dictionary)

const NO_WINNER := -1
const TURN_LIMIT := 60

var units: Array = []            # Array of Unit
var turn: Unit.Team = Unit.Team.PLAYER
var turn_count := 1
var winner := NO_WINNER          # NO_WINNER, or a Unit.Team value
var log: Array = []              # Array of {text, kind, turn}
var last_battle := {}            # pending battle record for the vignette
var rng := RandomNumberGenerator.new()

var _next_unit_id := 1


func _init() -> void:
	reset()


func reset() -> void:
	_next_unit_id = 1
	units = []
	for row: Array in GameData.PLAYER_ARMY:
		units.append(_make_unit(row, Unit.Team.PLAYER))
	for row: Array in GameData.ENEMY_ARMY:
		units.append(_make_unit(row, Unit.Team.ENEMY))
	turn = Unit.Team.PLAYER
	turn_count = 1
	winner = NO_WINNER
	log = []
	last_battle = {}
	add_log("— Turn 1: Player phase —", "phase")


func _make_unit(row: Array, team: Unit.Team) -> Unit:
	var u := Unit.new(_next_unit_id, GameData.unit_classes[row[0]],
			Vector2i(row[1], row[2]), row[3], team)
	_next_unit_id += 1
	return u


func add_log(text: String, kind: String = "info") -> void:
	var entry := {"text": text, "kind": kind, "turn": turn_count}
	log.append(entry)
	if log.size() > 200:
		log.pop_front()
	log_added.emit(entry)


func living_units(team: int = -1) -> Array:
	return units.filter(func(u: Unit) -> bool:
		return u.is_alive() and (team == -1 or u.team == team))


func unit_at(p: Vector2i) -> Unit:
	for u: Unit in units:
		if u.is_alive() and u.pos == p:
			return u
	return null


# --- Actions ----------------------------------------------------------------


func move_unit(unit: Unit, p: Vector2i) -> void:
	unit.pos = p


func attack(attacker: Unit, defender: Unit) -> Array:
	# Snapshot for the battle vignette: the overlay replays these events
	# starting from pre-battle HP. Core stays presentation-agnostic — it
	# just records what happened; the UI decides whether to animate it.
	last_battle = {
		"attacker": attacker, "defender": defender,
		"attacker_hp_before": attacker.hp, "defender_hp_before": defender.hp,
		"events": [],
	}
	var events := Combat.resolve_battle(attacker, defender, rng)
	last_battle["events"] = events
	for ev: Dictionary in events:
		var from_u: Unit = ev["from"]
		var to_u: Unit = ev["to"]
		if ev["type"] == "miss":
			add_log("%s (%s) misses %s." % [from_u.unit_name,
					from_u.u_class.display_name, to_u.unit_name], "miss")
		else:
			var crit_text: String = " CRITICAL!" if ev["crit"] else ""
			var kind := "player-hit" if from_u.team == Unit.Team.PLAYER else "enemy-hit"
			add_log("%s (%s) hits %s for %d.%s" % [from_u.unit_name,
					from_u.u_class.display_name, to_u.unit_name, ev["dmg"], crit_text], kind)
			if ev["killed"]:
				add_log("%s falls!" % to_u.unit_name, "death")
	attacker.acted = true
	check_winner()
	return events


func heal(healer: Unit, target: Unit) -> Dictionary:
	var ev := Combat.resolve_heal(healer, target)
	add_log("%s heals %s for %d HP." % [healer.unit_name, target.unit_name,
			ev["amount"]], "heal")
	healer.acted = true
	return ev


func hold(unit: Unit) -> void:
	unit.acted = true


# Hand the pending battle record to the UI exactly once.
func take_last_battle() -> Dictionary:
	var b := last_battle
	last_battle = {}
	return b


# --- Turn flow ---------------------------------------------------------------


func end_turn() -> void:
	for u: Unit in units:
		u.acted = false
	if turn == Unit.Team.PLAYER:
		turn = Unit.Team.ENEMY
		add_log("— Turn %d: Enemy phase —" % turn_count, "phase")
	else:
		turn = Unit.Team.PLAYER
		turn_count += 1
		if turn_count > TURN_LIMIT:
			decide_by_attrition()
			return
		add_log("— Turn %d: Player phase —" % turn_count, "phase")


# Safety valve for the simulation: if nobody routs the other side within
# TURN_LIMIT turns (e.g. only healers remain), decide by units left, then HP.
func decide_by_attrition() -> void:
	var score := func(team: int) -> int:
		var alive := living_units(team)
		var total := alive.size() * 1000
		for u: Unit in alive:
			total += u.hp
		return total
	var player_score: int = score.call(Unit.Team.PLAYER)
	var enemy_score: int = score.call(Unit.Team.ENEMY)
	winner = Unit.Team.PLAYER if player_score >= enemy_score else Unit.Team.ENEMY
	var side := "player" if winner == Unit.Team.PLAYER else "enemy"
	add_log("★ Turn limit reached — %s army wins by attrition." % side, "victory")


func all_acted(team: Unit.Team) -> bool:
	return living_units(team).all(func(u: Unit) -> bool: return u.acted)


func check_winner() -> void:
	if living_units(Unit.Team.ENEMY).is_empty():
		winner = Unit.Team.PLAYER
		add_log("★ Victory! The player army routs the enemy on turn %d." % turn_count,
				"victory")
	elif living_units(Unit.Team.PLAYER).is_empty():
		winner = Unit.Team.ENEMY
		add_log("★ Defeat. The enemy army wins on turn %d." % turn_count, "victory")


# Execute one AI-planned action for the next unacted unit on `team`.
# Returns the unit that acted, or null if the whole team has acted.
func step_ai(team: Unit.Team) -> Unit:
	if winner != NO_WINNER:
		return null
	var unit: Unit = null
	for u: Unit in living_units(team):
		if not u.acted:
			unit = u
			break
	if unit == null:
		return null

	var plan := AI.plan_action(unit, units, turn_count)
	if plan["move"] != null:
		move_unit(unit, plan["move"])
	if plan["attack"] != null:
		attack(unit, plan["attack"])
	elif plan["heal"] != null:
		heal(unit, plan["heal"])
	else:
		hold(unit)
	return unit
