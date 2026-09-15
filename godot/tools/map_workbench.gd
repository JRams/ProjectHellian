# Map editing workbench — a @tool scene you open in the Godot editor to
# paint scenarios with the engine's own TileMap editor.
#
# The deliberate design choice here: this script does NOT implement painting.
# Godot already ships a good tile painter (brush, fill, rect, line, pick),
# and reimplementing it would be both a lot of untested UI code and a worse
# tool. So the workbench is only the parts Godot can't know about:
#   MapData <-> TileMapLayer conversion, validation, and AI playtesting.
#
# Workflow:
#   1. Open tools/map_workbench.tscn.
#   2. Select the root node, drop a MapData into `Map` (or tick New Blank Map).
#   3. Tick `Load From Map` -> the tile layers fill in.
#   4. Select the Terrain or Units layer and paint with the TileMap panel.
#   5. Tick `Save To Map`, then `Validate`, then `Playtest`.
#   6. Ctrl+S saves the .tres.
#
# Actions are bool @exports that fire on tick and immediately untick
# themselves — the portable Godot 4 idiom for "a button in the Inspector"
# (4.4+ also has @export_tool_button, but this works on every 4.x).
@tool
extends Node2D

# Atlas layout of maps/tiles/hellian_tileset.tres:
#   row 0 = terrain, row 1 = player units, row 2 = enemy units.
const TERRAIN_TILE := {
	".": Vector2i(0, 0), "f": Vector2i(1, 0), "m": Vector2i(2, 0),
	"~": Vector2i(3, 0), "=": Vector2i(4, 0), "F": Vector2i(5, 0),
}
const UNIT_ORDER: Array[String] = [
	"Knight", "Mercenary", "Cavalier", "Archer", "Mage", "Healer", "Pegasus",
]
const PLAYER_ROW := 1
const ENEMY_ROW := 2
const SOURCE_ID := 0

@export var map: MapData

@export_group("Grid")
@export var grid_width := 16
@export var grid_height := 12

@export_group("Actions")
## Fill the tile layers from `map` so you can paint it.
@export var load_from_map := false:
	set(v):
		load_from_map = false
		if v:
			_load_from_map()
## Write what you painted back into `map`. Ctrl+S afterwards to save the file.
@export var save_to_map := false:
	set(v):
		save_to_map = false
		if v:
			_save_to_map()
## Report structural problems: stacked units, impassable spawns, walled-off armies.
@export var validate := false:
	set(v):
		validate = false
		if v:
			_validate()
## Run AI-vs-AI battles on this map and report win rate / length.
@export var playtest := false:
	set(v):
		playtest = false
		if v:
			_playtest()
## Replace `map` with an empty grid_width x grid_height field of plains.
@export var new_blank_map := false:
	set(v):
		new_blank_map = false
		if v:
			_new_blank_map()
## Write `map` out as JSON next to the .tres (portable, web-readable).
@export var export_json := false:
	set(v):
		export_json = false
		if v:
			_export_json()

@export_group("Playtest")
@export_range(1, 500) var playtest_battles := 25


func _terrain_layer() -> TileMapLayer:
	return get_node_or_null("Terrain") as TileMapLayer


func _unit_layer() -> TileMapLayer:
	return get_node_or_null("Units") as TileMapLayer


# --- MapData -> tiles ---------------------------------------------------------


func _load_from_map() -> void:
	var terrain := _terrain_layer()
	var units := _unit_layer()
	if map == null or terrain == null or units == null:
		push_warning("Map workbench: assign a MapData and keep Terrain/Units layers.")
		return
	terrain.clear()
	units.clear()

	grid_width = maxi(map.width(), 1)
	grid_height = maxi(map.height(), 1)
	for y in map.height():
		for x in map.width():
			var ch := map.char_at(Vector2i(x, y))
			var atlas: Vector2i = TERRAIN_TILE.get(ch, TERRAIN_TILE["."])
			terrain.set_cell(Vector2i(x, y), SOURCE_ID, atlas)

	_place_units(units, map.roster(map.player_units), PLAYER_ROW)
	_place_units(units, map.roster(map.enemy_units), ENEMY_ROW)
	print("[maps] loaded '%s' (%dx%d)" % [map.map_name, map.width(), map.height()])


func _place_units(layer: TileMapLayer, rows: Array, row: int) -> void:
	for r: Array in rows:
		var idx := UNIT_ORDER.find(r[0])
		if idx < 0:
			push_warning("Map workbench: unknown class '%s'." % r[0])
			continue
		layer.set_cell(Vector2i(r[1], r[2]), SOURCE_ID, Vector2i(idx, row))


# --- tiles -> MapData ---------------------------------------------------------


func _save_to_map() -> void:
	var terrain := _terrain_layer()
	var units := _unit_layer()
	if map == null or terrain == null or units == null:
		push_warning("Map workbench: assign a MapData and keep Terrain/Units layers.")
		return

	# Terrain: anything unpainted inside the grid becomes plains.
	var char_for := {}
	for ch: String in TERRAIN_TILE:
		char_for[TERRAIN_TILE[ch]] = ch
	var rows := PackedStringArray()
	for y in grid_height:
		var line := ""
		for x in grid_width:
			var atlas := terrain.get_cell_atlas_coords(Vector2i(x, y))
			line += char_for.get(atlas, ".")
		rows.append(line)
	map.terrain_rows = rows

	# Units: keep the existing name whenever a unit of the same class is
	# still standing on that tile, so renaming survives terrain edits.
	var previous := _name_lookup()
	var players := PackedStringArray()
	var enemies := PackedStringArray()
	var counters := {}
	for cell: Vector2i in units.get_used_cells():
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_width or cell.y >= grid_height:
			continue
		var atlas := units.get_cell_atlas_coords(cell)
		if atlas.x < 0 or atlas.x >= UNIT_ORDER.size():
			continue
		if atlas.y != PLAYER_ROW and atlas.y != ENEMY_ROW:
			continue
		var cls: String = UNIT_ORDER[atlas.x]
		var key := "%d,%d" % [cell.x, cell.y]
		var unit_name: String = previous.get(key, {}).get(cls, "")
		if unit_name.is_empty():
			counters[cls] = int(counters.get(cls, 0)) + 1
			unit_name = "%s%d" % [cls, counters[cls]]
		var line := "%s %d %d %s" % [cls, cell.x, cell.y, unit_name]
		if atlas.y == PLAYER_ROW:
			players.append(line)
		else:
			enemies.append(line)
	map.player_units = players
	map.enemy_units = enemies
	print("[maps] saved '%s': %dx%d, %d player / %d enemy units — Ctrl+S to write the file."
			% [map.map_name, grid_width, grid_height, players.size(), enemies.size()])


# {"x,y": {"Knight": "Doran"}} from the map's current rosters.
func _name_lookup() -> Dictionary:
	var out := {}
	for lines: PackedStringArray in [map.player_units, map.enemy_units]:
		for line in lines:
			var u := MapData.parse_unit_line(line)
			if u.is_empty():
				continue
			var key := "%d,%d" % [u["x"], u["y"]]
			if not out.has(key):
				out[key] = {}
			out[key][u["cls"]] = u["name"]
	return out


# --- tools --------------------------------------------------------------------


func _new_blank_map() -> void:
	var m := MapData.new()
	m.map_name = "New Map"
	var rows := PackedStringArray()
	for _y in grid_height:
		rows.append(".".repeat(grid_width))
	m.terrain_rows = rows
	map = m
	_load_from_map()
	print("[maps] new blank %dx%d map — paint it, then Save To Map."
			% [grid_width, grid_height])


func _validate() -> void:
	if map == null:
		push_warning("Map workbench: assign a MapData first.")
		return
	var problems := map.validate()
	if problems.is_empty():
		print("[maps] '%s' validates clean." % map.map_name)
		return
	print("[maps] '%s' — %d problem(s):" % [map.map_name, problems.size()])
	for p in problems:
		print("  " + p)
		if p.begins_with("ERROR"):
			push_error(p)
		else:
			push_warning(p)


# Reuses the AI simulation as map QA: if the map is lopsided or can
# deadlock, this is where it shows up — before you ever play it.
func _playtest() -> void:
	if map == null:
		push_warning("Map workbench: assign a MapData first.")
		return
	for p in map.validate():
		if p.begins_with("ERROR"):
			print("[maps] playtest aborted — fix validation errors first.")
			_validate()
			return

	var restore := MapData.from_game_data()
	map.apply()

	var player_wins := 0
	var total_turns := 0
	var attrition := 0
	var shortest := 9999
	var longest := 0
	for i in playtest_battles:
		var g := Game.new()
		g.rng.seed = 5000 + i
		var guard := 0
		while g.winner == Game.NO_WINNER and guard < 5000:
			guard += 1
			if g.step_ai(g.turn) == null:
				g.end_turn()
		if g.winner == Unit.Team.PLAYER:
			player_wins += 1
		if g.turn_count > GameData.turn_limit:
			attrition += 1
		total_turns += g.turn_count
		shortest = mini(shortest, g.turn_count)
		longest = maxi(longest, g.turn_count)

	restore.apply()
	var rate := 100.0 * player_wins / playtest_battles
	print("[maps] playtest '%s' over %d battles:" % [map.map_name, playtest_battles])
	print("  player win rate : %.0f%% (%d/%d)" % [rate, player_wins, playtest_battles])
	print("  turns           : avg %.1f, min %d, max %d"
			% [float(total_turns) / playtest_battles, shortest, longest])
	print("  hit turn limit  : %d" % attrition)
	if rate >= 80.0 or rate <= 20.0:
		push_warning("Map '%s' looks lopsided (%.0f%% player wins)." % [map.map_name, rate])
	if attrition > playtest_battles / 5:
		push_warning("Map '%s' stalls often (%d/%d battles hit the turn limit)."
				% [map.map_name, attrition, playtest_battles])


func _export_json() -> void:
	if map == null:
		push_warning("Map workbench: assign a MapData first.")
		return
	var path := map.resource_path
	if path.is_empty():
		push_warning("Map workbench: save the MapData as a .tres first.")
		return
	var json_path := path.get_basename() + ".json"
	if map.save_json(json_path) == OK:
		print("[maps] exported %s" % json_path)
	else:
		push_error("Map workbench: could not write %s" % json_path)
