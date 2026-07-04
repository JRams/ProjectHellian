# Port of one entry of TERRAIN in js/data.js.
# A plain data class: RefCounted is Godot's base for non-node,
# reference-counted objects (roughly "a garbage-collected POJO").
class_name TerrainType
extends RefCounted

var display_name: String
var cost: float          # movement cost; INF = impassable
var defense: int         # added to Def/Res while standing here
var avoid: int           # added to avoid while standing here
var color: Color
var color_alt: Color     # checkerboard variant


func _init(p_name: String, p_cost: float, p_defense: int, p_avoid: int,
		p_color: Color, p_color_alt: Color) -> void:
	display_name = p_name
	cost = p_cost
	defense = p_defense
	avoid = p_avoid
	color = p_color
	color_alt = p_color_alt
