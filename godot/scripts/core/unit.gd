# Port of makeUnit() in js/game.js — a live unit on the battlefield.
# Positions use Vector2i (Godot's integer 2D vector) instead of separate
# x/y fields; it's hashable, so it doubles as a Dictionary key.
class_name Unit
extends RefCounted

enum Team { PLAYER, ENEMY }

var id: int
var unit_name: String    # "name" shadows Node.name conventions; avoid it
var u_class: UnitClass   # "class" is a reserved word in GDScript
var team: Team
var pos: Vector2i
var hp: int
var max_hp: int
var acted := false       # has this unit taken its action this turn?


func _init(p_id: int, p_class: UnitClass, p_pos: Vector2i,
		p_name: String, p_team: Team) -> void:
	id = p_id
	u_class = p_class
	pos = p_pos
	unit_name = p_name
	team = p_team
	hp = p_class.max_hp
	max_hp = p_class.max_hp


func is_alive() -> bool:
	return hp > 0


func can_fight() -> bool:
	return not u_class.attack_range.is_empty()
