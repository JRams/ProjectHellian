# A scenario: terrain, rosters, and objective — everything that makes one
# battle map. Saved as `maps/*.tres`, painted with the editor workbench
# (tools/map_workbench.tscn), and loaded by the game.
#
# Why a Resource: `@export`ed fields are editable in Godot's Inspector for
# free, `.tres` is a diffable text format, and `load()` handles the file IO.
# Terrain and rosters stay human-readable strings on purpose — a map is
# still fixable in a text editor if the tooling is ever in the way.
#
# This class depends on GameData (terrain + class tables) but nothing
# depends on it, so there's no cycle: MapData -> GameData, one direction.
class_name MapData
extends Resource

# Map legend, matching GameData.TERRAIN_CHARS:
#   . plain   f forest   m mountain   ~ water   = bridge   F fort
@export_multiline var map_name := "Untitled"
@export_enum("rout", "seize", "survive") var objective := "rout"
@export var turn_limit := 60

## One string per row; every row must be the same length.
@export var terrain_rows: PackedStringArray = []

## One unit per line: "<Class> <x> <y> <Name>", e.g. "Knight 1 4 Doran".
@export var player_units: PackedStringArray = []
@export var enemy_units: PackedStringArray = []


# Snapshot whatever map GameData currently holds into a fresh resource.
# Used to seed the first .tres from the built-in scenario.
static func from_game_data() -> MapData:
	var m := MapData.new()
	m.map_name = GameData.current_map_name
	m.terrain_rows = PackedStringArray(GameData.map_layout)
	m.player_units = _rows_to_lines(GameData.player_army)
	m.enemy_units = _rows_to_lines(GameData.enemy_army)
	return m


static func _rows_to_lines(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Array in rows:
		out.append("%s %d %d %s" % [r[0], r[1], r[2], r[3]])
	return out


# "Knight 1 4 Doran" -> {"cls": "Knight", "x": 1, "y": 4, "name": "Doran"}
# Returns {} when the line can't be parsed; validate() reports the details.
static func parse_unit_line(line: String) -> Dictionary:
	var parts := line.strip_edges().split(" ", false)
	if parts.size() < 4:
		return {}
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {}
	var name_parts := parts.slice(3)
	return {
		"cls": parts[0],
		"x": int(parts[1]),
		"y": int(parts[2]),
		"name": " ".join(name_parts),
	}


func width() -> int:
	return 0 if terrain_rows.is_empty() else terrain_rows[0].length()


func height() -> int:
	return terrain_rows.size()


func char_at(p: Vector2i) -> String:
	if p.y < 0 or p.y >= terrain_rows.size():
		return ""
	var row := terrain_rows[p.y]
	if p.x < 0 or p.x >= row.length():
		return ""
	return row[p.x]


# Roster in the [class, x, y, name] shape GameData/Game already expect.
func roster(lines: PackedStringArray) -> Array:
	var out: Array = []
	for line in lines:
		var u := parse_unit_line(line)
		if not u.is_empty():
			out.append([u["cls"], u["x"], u["y"], u["name"]])
	return out


# Make this the live map. Everything that reads the board goes through
# GameData, so this is the whole "load a map" operation.
func apply() -> void:
	var rows: Array[String] = []
	for r in terrain_rows:
		rows.append(r)
	GameData.map_layout = rows
	GameData.map_w = width()
	GameData.map_h = height()
	GameData.player_army = roster(player_units)
	GameData.enemy_army = roster(enemy_units)
	GameData.current_map_name = map_name
	GameData.turn_limit = turn_limit


# --- validation ---------------------------------------------------------------
# Catches the mistakes a map editor actually makes. Returns a list of
# "ERROR: ..." / "WARN: ..." strings; empty means the map is sound.


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if terrain_rows.is_empty():
		problems.append("ERROR: map has no terrain rows.")
		return problems

	var w := width()
	for y in terrain_rows.size():
		if terrain_rows[y].length() != w:
			problems.append("ERROR: row %d is %d tiles wide, expected %d."
					% [y, terrain_rows[y].length(), w])
	for y in terrain_rows.size():
		for x in terrain_rows[y].length():
			var ch := terrain_rows[y][x]
			if not GameData.TERRAIN_CHARS.has(ch):
				problems.append("ERROR: unknown terrain '%s' at (%d, %d)." % [ch, x, y])

	var players := _check_roster(player_units, "player", problems)
	var enemies := _check_roster(enemy_units, "enemy", problems)
	if players.is_empty():
		problems.append("ERROR: no player units placed.")
	if enemies.is_empty():
		problems.append("ERROR: no enemy units placed.")

	# Two units can never share a tile.
	var taken := {}
	for u: Dictionary in players + enemies:
		var p := Vector2i(u["x"], u["y"])
		if taken.has(p):
			problems.append("ERROR: two units stacked on (%d, %d)." % [p.x, p.y])
		taken[p] = true

	if objective != "rout":
		problems.append("WARN: objective '%s' is not implemented yet — " % objective
				+ "the game will play this map as a rout.")
	if turn_limit < 1:
		problems.append("ERROR: turn_limit must be at least 1.")

	if not players.is_empty() and not enemies.is_empty():
		problems.append_array(_check_reachability(players, enemies))
	return problems


# Parses a roster, reporting bad lines, unknown classes, out-of-bounds
# positions, and units standing somewhere their class can't stand.
func _check_roster(lines: PackedStringArray, side: String,
		problems: PackedStringArray) -> Array:
	var out: Array = []
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		var u := parse_unit_line(line)
		if u.is_empty():
			problems.append("ERROR: %s line '%s' is not '<Class> <x> <y> <Name>'."
					% [side, line])
			continue
		if not GameData.unit_classes.has(u["cls"]):
			problems.append("ERROR: unknown class '%s' in %s roster." % [u["cls"], side])
			continue
		var p := Vector2i(u["x"], u["y"])
		if p.x < 0 or p.y < 0 or p.x >= width() or p.y >= height():
			problems.append("ERROR: %s unit %s is off the map at (%d, %d)."
					% [side, u["name"], p.x, p.y])
			continue
		var cls: UnitClass = GameData.unit_classes[u["cls"]]
		if not _passable_for(p, cls.is_mounted, cls.is_flier):
			problems.append("ERROR: %s (%s) starts on impassable terrain at (%d, %d)."
					% [u["name"], u["cls"], p.x, p.y])
		out.append(u)
	return out


# Can the two armies actually fight? Flood-fills each player unit's
# movement region (ignoring move budget — this is about connectivity, not
# one turn) and checks whether any enemy is in or adjacent to it.
func _check_reachability(players: Array, enemies: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	var stranded: Array[String] = []
	var any_engagement := false

	for u: Dictionary in players:
		var cls: UnitClass = GameData.unit_classes.get(u["cls"], null)
		if cls == null:
			continue
		var region := _region_from(Vector2i(u["x"], u["y"]), cls.is_mounted, cls.is_flier)
		var can_engage := false
		for e: Dictionary in enemies:
			var ep := Vector2i(e["x"], e["y"])
			if region.has(ep):
				can_engage = true
				break
			for d in Grid.CARDINALS:
				if region.has(ep + d):
					can_engage = true
					break
			if can_engage:
				break
		if can_engage:
			any_engagement = true
		else:
			stranded.append("%s (%s)" % [u["name"], u["cls"]])

	if not any_engagement:
		problems.append("ERROR: no player unit can reach any enemy — "
				+ "the armies are walled off from each other.")
	elif not stranded.is_empty():
		problems.append("WARN: cannot reach the enemy at all: %s." % ", ".join(stranded))
	return problems


func _passable_for(p: Vector2i, mounted: bool, flier: bool) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= width() or p.y >= height():
		return false
	var ch := char_at(p)
	if not GameData.TERRAIN_CHARS.has(ch):
		return false
	if flier:
		return true
	var key: String = GameData.TERRAIN_CHARS[ch]
	if mounted and key == "mountain":
		return false
	return GameData.terrain_types[key].cost < INF


# Every tile reachable from `start` by cardinal steps, ignoring move cost.
func _region_from(start: Vector2i, mounted: bool, flier: bool) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in Grid.CARDINALS:
			var n: Vector2i = cur + d
			if seen.has(n) or not _passable_for(n, mounted, flier):
				continue
			seen[n] = true
			queue.append(n)
	return seen


# --- portability --------------------------------------------------------------
# .tres is Godot-only. JSON keeps maps readable by the web prototype and by
# any external tooling, and keeps the "which version is canonical" decision
# open (see docs/DECISIONS-TO-MAKE.md).


func to_dict() -> Dictionary:
	return {
		"name": map_name,
		"objective": objective,
		"turn_limit": turn_limit,
		"terrain": Array(terrain_rows),
		"player": Array(player_units),
		"enemy": Array(enemy_units),
	}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.map_name = d.get("name", "Untitled")
	m.objective = d.get("objective", "rout")
	m.turn_limit = int(d.get("turn_limit", 60))
	m.terrain_rows = PackedStringArray(d.get("terrain", []))
	m.player_units = PackedStringArray(d.get("player", []))
	m.enemy_units = PackedStringArray(d.get("enemy", []))
	return m


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return OK


static func load_json(path: String) -> MapData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
