# Port of drawUnit() in js/render.js — but as a SCENE INSTANCE.
#
# Godot concept: unit.tscn is a reusable "prefab". main.gd instantiates one
# per Unit and adds it to the tree. Each instance owns its position,
# drawing, and animations; the JS version instead looped over all units in
# a single draw call. Position animation uses a Tween: a fire-and-forget
# interpolator the engine advances every frame.
extends Node2D

var unit: Unit          # the core-logic unit this node visualizes
var game: Game          # to know whose phase it is (for the "acted" gray)
var selected := false


func setup(p_unit: Unit, p_game: Game) -> void:
	unit = p_unit
	game = p_game
	position = _grid_to_px(unit.pos)


# Called by main.gd after any state change.
func refresh(animate_move := false) -> void:
	visible = unit.is_alive()
	var target := _grid_to_px(unit.pos)
	if animate_move and position != target:
		var tween := create_tween()
		tween.tween_property(self, "position", target, 0.15) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		position = target
	queue_redraw()


func _grid_to_px(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GameData.TILE + GameData.TILE / 2.0,
			cell.y * GameData.TILE + GameData.TILE / 2.0)


func _draw() -> void:
	if unit == null:
		return
	var colors: Dictionary = GameData.team_colors[unit.team]
	var grayed: bool = unit.acted and unit.team == game.turn

	var body: Color = Color("8a8a8a") if grayed else colors["main"]
	var rim: Color = Color("5a5a5a") if grayed else colors["dark"]

	if selected:
		draw_circle(Vector2(0, -2), 18, Color(1.0, 0.91, 0.3, 0.35))
	draw_circle(Vector2(0, -2), 14, body)
	draw_arc(Vector2(0, -2), 14, 0, TAU, 32, rim, 2.5)

	# Class letter. _draw text needs an explicit font; use the theme default.
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-14, 3), unit.u_class.icon,
			HORIZONTAL_ALIGNMENT_CENTER, 28, 15, Color.WHITE)

	# HP bar
	var half := GameData.TILE / 2.0
	var w := GameData.TILE - 12.0
	var bar_pos := Vector2(-half + 6, half - 9)
	draw_rect(Rect2(bar_pos, Vector2(w, 5)), Color(0, 0, 0, 0.55))
	var frac := float(unit.hp) / unit.max_hp
	var bar := Color("5ad35a") if frac > 0.5 else (Color("e8c33a") if frac > 0.25 else Color("e05050"))
	draw_rect(Rect2(bar_pos + Vector2(1, 1), Vector2((w - 2) * frac, 3)), bar)
