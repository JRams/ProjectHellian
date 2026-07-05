# Port of the terrain/highlight half of js/render.js.
#
# Godot concept: instead of an immediate-mode canvas redrawn every frame,
# a Node2D owns its own drawing via _draw(). Godot caches the result and
# only calls _draw() again after queue_redraw() — so the game notifies the
# board when state changes rather than repainting 60x per second.
extends Node2D

const T := GameData.TILE

# View state, assigned by main.gd before it calls queue_redraw().
var reachable := {}        # Dictionary[Vector2i -> node] or empty
var path: Array[Vector2i] = []
var attack_targets: Array = []
var heal_targets: Array = []
var hover := Vector2i(-1, -1)


func refresh(p_reachable: Dictionary, p_path: Array[Vector2i],
		p_attack: Array, p_heal: Array) -> void:
	reachable = p_reachable
	path = p_path
	attack_targets = p_attack
	heal_targets = p_heal
	queue_redraw()


func set_hover(cell: Vector2i) -> void:
	if cell != hover:
		hover = cell
		queue_redraw()


func _draw() -> void:
	_draw_terrain()
	_draw_grid_lines()
	_draw_highlights()
	_draw_path()
	_draw_cursor()


func _draw_terrain() -> void:
	for y in GameData.MAP_H:
		for x in GameData.MAP_W:
			var cell := Vector2i(x, y)
			var key: String = GameData.TERRAIN_CHARS[GameData.MAP_LAYOUT[y][x]]
			BattleArt.draw_map_tile(self, cell, T, key)


func _draw_grid_lines() -> void:
	var line := Color(0, 0, 0, 0.07)
	for x in GameData.MAP_W + 1:
		draw_line(Vector2(x * T, 0), Vector2(x * T, GameData.MAP_H * T), line)
	for y in GameData.MAP_H + 1:
		draw_line(Vector2(0, y * T), Vector2(GameData.MAP_W * T, y * T), line)


func _draw_highlights() -> void:
	for node: Dictionary in reachable.values():
		if not node["pass_only"]:
			_tint(node["pos"], Color(0.31, 0.55, 1.0, 0.40))
	for u: Unit in attack_targets:
		_tint(u.pos, Color(1.0, 0.24, 0.24, 0.45))
	for u: Unit in heal_targets:
		_tint(u.pos, Color(0.24, 1.0, 0.47, 0.45))


func _tint(cell: Vector2i, color: Color) -> void:
	draw_rect(Rect2(cell.x * T, cell.y * T, T, T), color)


func _draw_path() -> void:
	if path.size() < 2:
		return
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(Vector2(cell.x * T + T / 2.0, cell.y * T + T / 2.0))
	draw_polyline(pts, Color(1, 1, 1, 0.85), 4.0)


func _draw_cursor() -> void:
	if Grid.in_bounds(hover):
		draw_rect(Rect2(hover.x * T + 2, hover.y * T + 2, T - 4, T - 4),
				Color("ffe94d"), false, 3.0)
