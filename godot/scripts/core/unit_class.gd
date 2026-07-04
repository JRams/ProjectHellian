# Port of one entry of CLASSES in js/data.js.
# JS used ad-hoc object literals; in GDScript we get real typed fields.
# Abbreviated JS stat names are expanded because `str` is a built-in
# GDScript function and shadowing it invites confusion.
class_name UnitClass
extends RefCounted

var display_name := ""
var icon := ""
var weapon := ""
var max_hp := 0
var strength := 0        # was: str
var magic_power := 0     # was: mag
var skill := 0           # was: skl
var speed := 0           # was: spd
var defense := 0         # was: def
var resistance := 0      # was: res
var movement := 0        # was: mov
var attack_range: Array = []   # manhattan distances this class attacks at
var might := 0           # was: mt (weapon power)
var hit := 0
var crit := 0
var is_magic := false    # damage targets resistance instead of defense
var is_mounted := false  # blocked by mountains
var is_flier := false    # ignores all terrain
var heal_range: Array = []
var heal_power := 0
var description := ""
# QTE "addition" pattern: {periods: Array[float], perfect: float, good: float}
var qte: Dictionary = {}


# Build from a dictionary so game_data.gd reads like the JS class table.
func _init(d: Dictionary = {}) -> void:
	display_name = d.get("display_name", "")
	icon = d.get("icon", "")
	weapon = d.get("weapon", "")
	max_hp = d.get("max_hp", 0)
	strength = d.get("strength", 0)
	magic_power = d.get("magic_power", 0)
	skill = d.get("skill", 0)
	speed = d.get("speed", 0)
	defense = d.get("defense", 0)
	resistance = d.get("resistance", 0)
	movement = d.get("movement", 0)
	attack_range = d.get("attack_range", [])
	might = d.get("might", 0)
	hit = d.get("hit", 0)
	crit = d.get("crit", 0)
	is_magic = d.get("is_magic", false)
	is_mounted = d.get("is_mounted", false)
	is_flier = d.get("is_flier", false)
	heal_range = d.get("heal_range", [])
	heal_power = d.get("heal_power", 0)
	description = d.get("description", "")
	qte = d.get("qte", {})
