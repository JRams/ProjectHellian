# Port of js/grid.js — cardinal-direction movement, pathfinding, ranges.
# All functions are static; a "node" here is a plain Dictionary:
#   { "pos": Vector2i, "cost": float, "from": Vector2i or null, "pass_only": bool }
# The reachable set is Dictionary[Vector2i -> node], replacing the JS Map
# keyed by y*W+x — Vector2i is hashable so it can key a Dictionary directly.
class_name Grid
extends RefCounted

# The four cardinal directions. There is no diagonal movement.
const CARDINALS: Array[Vector2i] = [
	Vector2i(0, -1),  # north
	Vector2i(1, 0),   # east
	Vector2i(0, 1),   # south
	Vector2i(-1, 0),  # west
]


static func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < GameData.MAP_W and p.y >= 0 and p.y < GameData.MAP_H


static func terrain_at(p: Vector2i) -> TerrainType:
	var ch := GameData.MAP_LAYOUT[p.y][p.x]
	return GameData.terrain_types[GameData.TERRAIN_CHARS[ch]]


# Movement cost of a tile for a specific unit (INF = impassable).
static func move_cost(unit: Unit, p: Vector2i) -> float:
	var t := terrain_at(p)
	if unit.u_class.is_flier:
		return 1.0  # fliers ignore terrain
	if unit.u_class.is_mounted and t == GameData.terrain_types["mountain"]:
		return INF
	return t.cost


# Dijkstra flood-fill over cardinal steps. Returns every tile the unit can
# reach with its movement stat. Tiles occupied by enemies block passage;
# tiles occupied by allies can be passed through but not stopped on
# (marked pass_only).
static func reachable_tiles(unit: Unit, units: Array) -> Dictionary:
	var occupied := {}
	for u: Unit in units:
		if u.is_alive() and u != unit:
			occupied[u.pos] = u

	var best := {}
	var start := {"pos": unit.pos, "cost": 0.0, "from": null, "pass_only": false}
	best[unit.pos] = start
	var frontier: Array = [start]

	while not frontier.is_empty():
		# pop lowest-cost node (linear scan is fine for maps this size)
		var bi := 0
		for i in range(1, frontier.size()):
			if frontier[i]["cost"] < frontier[bi]["cost"]:
				bi = i
		var cur: Dictionary = frontier.pop_at(bi)

		for dir in CARDINALS:
			var np: Vector2i = cur["pos"] + dir
			if not in_bounds(np):
				continue
			var total: float = cur["cost"] + move_cost(unit, np)
			if total > unit.u_class.movement:
				continue
			if occupied.has(np) and occupied[np].team != unit.team:
				continue  # enemies block
			if best.has(np) and best[np]["cost"] <= total:
				continue
			var node := {"pos": np, "cost": total, "from": cur["pos"], "pass_only": false}
			best[np] = node
			frontier.append(node)

	# Can't end movement on any occupied tile (ally or enemy).
	for p: Vector2i in best:
		best[p]["pass_only"] = occupied.has(p)
	return best


# Reconstruct the cardinal-step path to a reachable tile.
static func path_to(reachable: Dictionary, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var p: Variant = dest
	while p != null and reachable.has(p):
		path.push_front(p)
		p = reachable[p]["from"]
	return path


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Enemies attackable from a given standing position.
static func targets_from(unit: Unit, p: Vector2i, units: Array) -> Array:
	var out: Array = []
	for u: Unit in units:
		if u.is_alive() and u.team != unit.team \
				and unit.u_class.attack_range.has(manhattan(p, u.pos)):
			out.append(u)
	return out


# Wounded allies healable from a given standing position.
static func heal_targets_from(unit: Unit, p: Vector2i, units: Array) -> Array:
	if unit.u_class.heal_range.is_empty():
		return []
	var out: Array = []
	for u: Unit in units:
		if u.is_alive() and u != unit and u.team == unit.team and u.hp < u.max_hp \
				and unit.u_class.heal_range.has(manhattan(p, u.pos)):
			out.append(u)
	return out
