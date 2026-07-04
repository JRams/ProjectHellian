# Headless test — the Godot equivalent of the Playwright harness used to
# verify the JS prototype. Runs entire AI-vs-AI battles with no window.
#
# Run from the godot/ directory:
#   godot --headless -s tests/sim_test.gd
#
# `-s` (or --script) runs a script that extends SceneTree or MainLoop
# instead of the main scene; _init fires once at startup.
extends SceneTree

const RUNS := 10


func _init() -> void:
	var failures := 0
	print("== Project Hellian simulation test: %d battles ==" % RUNS)
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
		var side := "player" if game.winner == Unit.Team.PLAYER else "enemy"
		print("run %d: %s wins on turn %d (player %d / enemy %d left)" % [
			i, side, game.turn_count,
			game.living_units(Unit.Team.PLAYER).size(),
			game.living_units(Unit.Team.ENEMY).size(),
		])

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
