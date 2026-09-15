# Headless test — the Godot equivalent of the Playwright harness used to
# verify the JS prototype. Runs entire AI-vs-AI battles with no window.
#
# Run from the godot/ directory:
#   godot --headless -s tests/sim_test.gd
#
# Add `-- --map res://maps/<name>.tres` to validate and balance-test a
# specific scenario instead of the built-in one. That turns this script
# into map QA: the same AI that plays the game reports whether a new map
# is winnable, lopsided, or prone to stalling.
#
# `-s` (or --script) runs a script that extends SceneTree or MainLoop
# instead of the main scene; _init fires once at startup.
extends SceneTree

const RUNS := 10


func _init() -> void:
	var failures := 0
	var map_path := _map_arg()
	if not map_path.is_empty():
		failures += _load_map(map_path)
	print("== Project Hellian simulation test: %d battles on '%s' =="
			% [RUNS, GameData.current_map_name])
	var player_wins := 0
	var attrition := 0
	var turn_total := 0
	for i in RUNS:
		var game := Game.new()
		game.rng.seed = 1000 + i  # seeded => reproducible
		var guard := 0
		while game.winner == Game.NO_WINNER and guard < 5000:
			guard += 1
			if game.step_ai(game.turn) == null:
				game.end_turn()
		if game.winner == Game.NO_WINNER:
			print("run %d: FAILED — no winner after %d steps" % [i, guard])
			failures += 1
			continue
		if game.winner == Unit.Team.PLAYER:
			player_wins += 1
		if game.turn_count > GameData.turn_limit:
			attrition += 1
		turn_total += game.turn_count
		var side := "player" if game.winner == Unit.Team.PLAYER else "enemy"
		print("run %d: %s wins on turn %d (player %d / enemy %d left)" % [
			i, side, game.turn_count,
			game.living_units(Unit.Team.PLAYER).size(),
			game.living_units(Unit.Team.ENEMY).size(),
		])

	print("balance: player win rate %d%% (%d/%d), avg %.1f turns, %d hit the turn limit"
			% [roundi(100.0 * player_wins / RUNS), player_wins, RUNS,
			float(turn_total) / RUNS, attrition])

	# Core-logic assertions (mirrors the checks the JS harness ran in-page).
	var game := Game.new()
	var knight: Unit = game.units[0]
	var reach := Grid.reachable_tiles(knight, game.units)
	for node: Dictionary in reach.values():
		if node["cost"] > knight.u_class.movement:
			print("FAILED: reachable tile beyond movement budget")
			failures += 1
		var path := Grid.path_to(reach, node["pos"])
		for j in range(1, path.size()):
			if Grid.manhattan(path[j - 1], path[j]) != 1:
				print("FAILED: non-cardinal step in path")
				failures += 1
	print("reachability: %d tiles for %s (mov %d)" % [
		reach.size(), knight.unit_name, knight.u_class.movement])

	failures += _test_qte(game)
	failures += _test_map_data()

	print("== %s ==" % ("FAILED (%d)" % failures if failures > 0 else "ALL OK"))
	quit(1 if failures > 0 else 0)


# QTE grading math and multiplier-scaled strike resolution.
func _test_qte(game: Game) -> int:
	var failures := 0
	var spec := {"periods": [0.55], "perfect": 0.055, "good": 0.12}
	if BattleVignette.grade_press(0.02, spec)["points"] != 1.0 \
			or BattleVignette.grade_press(0.09, spec)["points"] != 0.6 \
			or BattleVignette.grade_press(0.3, spec)["points"] != 0.0:
		print("FAILED: grade_press tiers wrong")
		failures += 1
	if BattleVignette.offense_result([1.0, 1.0, 1.0])["label"] != "MAX!" \
			or not is_equal_approx(BattleVignette.offense_result([1.0, 1.0, 1.0])["mult"], 1.5) \
			or not is_equal_approx(BattleVignette.offense_result([0.0])["mult"], 0.75):
		print("FAILED: offense multipliers wrong")
		failures += 1
	var dspec: Dictionary = GameData.DEFENSE_QTE
	var parry := {"state": "released", "release_err": 0.02, "spec": dspec}
	var block := {"state": "released", "release_err": 0.12, "spec": dspec}
	var early := {"state": "released", "release_err": 0.5, "spec": dspec}
	var held := {"state": "holding", "spec": dspec}
	var none := {"state": "waiting", "spec": dspec}
	if BattleVignette.defense_result(parry)["mult"] != 0.5 \
			or BattleVignette.defense_result(block)["mult"] != 0.75 \
			or BattleVignette.defense_result(early)["mult"] != 1.0 \
			or BattleVignette.defense_result(held)["mult"] != 0.9 \
			or BattleVignette.defense_result(none)["mult"] != 1.0:
		print("FAILED: parry multipliers wrong")
		failures += 1

	# Strike order: merc (spd 11) vs knight (spd 3) at range 1 = merc doubles.
	var merc: Unit = game.units[1]
	var knight: Unit = game.units[7]
	merc.pos = Vector2i(5, 5)
	knight.pos = Vector2i(5, 6)
	var strikes := Combat.plan_strikes(merc, knight)
	if strikes.size() != 3 or strikes[2]["actor"] != merc:
		print("FAILED: plan_strikes order wrong (got %d strikes)" % strikes.size())
		failures += 1

	# A guaranteed hit at 1.5x deals exactly round(base * 1.5).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var before := knight.hp
	var ev := Combat.resolve_strike(merc, knight, rng, 1.5, 1.0, "MAX!")
	if ev["type"] == "hit" and not ev["crit"]:
		var base: int = Combat.strike_stats(merc, knight)["dmg"]
		if before - knight.hp != roundi(base * 1.5):
			print("FAILED: offense multiplier not applied to damage")
			failures += 1
	print("qte: grading, multipliers, and strike order OK")
	return failures


# --- map loading ---------------------------------------------------------------


func _map_arg() -> String:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--map" and i + 1 < args.size():
			return args[i + 1]
	return ""


func _load_map(path: String) -> int:
	var m: MapData = load(path) as MapData
	if m == null:
		print("FAILED: could not load map '%s'" % path)
		return 1
	var problems := m.validate()
	var errors := 0
	for p in problems:
		print("  " + p)
		if p.begins_with("ERROR"):
			errors += 1
	if errors > 0:
		print("FAILED: map '%s' has %d validation error(s)" % [path, errors])
		return errors
	m.apply()
	return 0


# --- MapData tests --------------------------------------------------------------
# Exercises the scenario format and, more importantly, proves the validator
# actually catches broken maps — that is what makes it worth trusting in the
# editor workbench.


func _test_map_data() -> int:
	var failures := 0
	# These assertions describe the built-in scenario, so run them against it
	# even when --map loaded something else, then put the map back.
	var loaded := MapData.from_game_data()
	GameData.reset_to_default_map()

	# Round-trip: built-in map -> MapData -> dict -> MapData.
	var m := MapData.from_game_data()
	if m.width() != 16 or m.height() != 12:
		print("FAILED: snapshot has wrong dimensions (%dx%d)" % [m.width(), m.height()])
		failures += 1
	if m.roster(m.player_units).size() != 7 or m.roster(m.enemy_units).size() != 7:
		print("FAILED: snapshot roster size wrong")
		failures += 1
	var round_tripped := MapData.from_dict(m.to_dict())
	if round_tripped.to_dict() != m.to_dict():
		print("FAILED: MapData JSON round-trip is lossy")
		failures += 1
	if not m.validate().is_empty():
		print("FAILED: the built-in map does not validate clean:")
		for p in m.validate():
			print("  " + p)
		failures += 1

	# Unit line parsing, including names containing spaces.
	var parsed := MapData.parse_unit_line("Knight 3 4 Sir Doran")
	if parsed.get("cls") != "Knight" or parsed.get("x") != 3 \
			or parsed.get("y") != 4 or parsed.get("name") != "Sir Doran":
		print("FAILED: parse_unit_line wrong: %s" % parsed)
		failures += 1
	if not MapData.parse_unit_line("garbage").is_empty():
		print("FAILED: parse_unit_line accepted a malformed line")
		failures += 1

	failures += _expect_error("ragged rows", _map_of(
			["...", "....", "..."], ["Knight 0 0 A"], ["Knight 2 2 B"]))
	failures += _expect_error("unknown terrain", _map_of(
			["..X", "...", "..."], ["Knight 0 0 A"], ["Knight 2 2 B"]))
	failures += _expect_error("stacked units", _map_of(
			["...", "...", "..."], ["Knight 1 1 A"], ["Knight 1 1 B"]))
	failures += _expect_error("spawn in water", _map_of(
			["~..", "...", "..."], ["Knight 0 0 A"], ["Knight 2 2 B"]))
	failures += _expect_error("no enemies", _map_of(
			["...", "...", "..."], ["Knight 0 0 A"], []))

	# A river splitting the map: foot units are walled off, but a flier
	# crosses it — the validator has to know the difference.
	var split := ["..~..", "..~..", "..~.."]
	failures += _expect_error("armies walled off", _map_of(
			split, ["Knight 0 1 A"], ["Knight 4 1 B"]))
	var flier_map := _map_of(split, ["Pegasus 0 1 A"], ["Knight 4 1 B"])
	for p in flier_map.validate():
		if p.begins_with("ERROR"):
			print("FAILED: flier should be able to cross water, got: %s" % p)
			failures += 1

	loaded.apply()
	print("map data: format, round-trip, and validator OK")
	return failures


func _map_of(rows: Array, players: Array, enemies: Array) -> MapData:
	var m := MapData.new()
	m.map_name = "test"
	m.terrain_rows = PackedStringArray(rows)
	m.player_units = PackedStringArray(players)
	m.enemy_units = PackedStringArray(enemies)
	return m


func _expect_error(label: String, m: MapData) -> int:
	for p in m.validate():
		if p.begins_with("ERROR"):
			return 0
	print("FAILED: validator missed '%s'" % label)
	return 1
