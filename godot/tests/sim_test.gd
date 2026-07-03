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

	print("== %s ==" % ("FAILED (%d)" % failures if failures > 0 else "ALL OK"))
	quit(1 if failures > 0 else 0)
