# Port of the interaction half of js/main.js — the orchestrator.
#
# Owns the Game (pure logic), the Board (terrain/highlight drawing), one
# UnitNode instance per unit, and the UI layer. Input arrives through
# _unhandled_input, which Godot only calls with events no Control consumed —
# so clicking a sidebar Button never leaks through to the battlefield.
# AI pacing uses a Timer node instead of setTimeout chains.
extends Node2D

# The same interaction state machine as the JS version.
enum State { IDLE, MOVE_SELECT, ACTION_SELECT }
# What the timer is currently driving.
enum Auto { NONE, ENEMY_PHASE, SIMULATE }

const UNIT_SCENE := preload("res://scenes/unit.tscn")

var game: Game
var state := State.IDLE
var auto := Auto.NONE
# Bumped by Reset. Coroutines paused on `await` capture the value before
# suspending and bail out if it changed — otherwise a Reset mid-vignette
# would resume a continuation written for the previous game.
var epoch := 0
var selected: Unit = null
var reachable := {}
var move_from := Vector2i(-1, -1)
var attack_targets: Array = []
var heal_targets: Array = []
var unit_nodes := {}      # unit id -> UnitNode

@onready var board: Node2D = $Board
@onready var units_root: Node2D = $Units
@onready var ui: CanvasLayer = $UI
@onready var sim_timer: Timer = $SimTimer
@onready var battle_fx: Control = $UI/BattleFX


func _ready() -> void:
	game = Game.new()
	game.log_added.connect(ui.on_log_added)
	ui.simulate_toggled.connect(_on_simulate_toggled)
	ui.end_turn_pressed.connect(_on_end_turn)
	ui.reset_pressed.connect(_on_reset)
	sim_timer.timeout.connect(_on_sim_timer)
	_spawn_unit_nodes()
	_replay_log()
	_refresh_all()


func _spawn_unit_nodes() -> void:
	for node: Node in units_root.get_children():
		node.queue_free()
	unit_nodes = {}
	for u: Unit in game.units:
		var n := UNIT_SCENE.instantiate()
		units_root.add_child(n)
		n.setup(u, game)
		unit_nodes[u.id] = n


# Game.reset() rebuilds the log before the UI can hear the signals; replay it.
func _replay_log() -> void:
	ui.clear_log()
	for entry: Dictionary in game.log:
		ui.on_log_added(entry)


# --- Input -------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_hover(_mouse_cell())
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_click(_mouse_cell())


func _mouse_cell() -> Vector2i:
	var local := board.get_local_mouse_position()
	return Vector2i(int(floor(local.x / GameData.TILE)), int(floor(local.y / GameData.TILE)))


func _on_hover(cell: Vector2i) -> void:
	board.set_hover(cell if Grid.in_bounds(cell) else Vector2i(-1, -1))
	if state == State.MOVE_SELECT:
		_refresh_all()  # keep the path preview tracking the cursor
	_update_hover_panels(cell)


func _update_hover_panels(cell: Vector2i) -> void:
	# Forecast when hovering an attackable enemy in ACTION_SELECT.
	if state == State.ACTION_SELECT:
		var over := game.unit_at(cell) if Grid.in_bounds(cell) else null
		if over != null and attack_targets.has(over):
			ui.show_forecast(selected, over)
		else:
			ui.hide_forecast()
	# Info panel: hovered unit > selected unit > terrain > default.
	var shown: Unit = null
	if Grid.in_bounds(cell):
		shown = game.unit_at(cell)
	if shown == null:
		shown = selected
	if shown != null:
		ui.show_unit_info(shown)
	elif Grid.in_bounds(cell):
		ui.show_terrain_info(cell)
	else:
		ui.show_default_info()


func _on_click(cell: Vector2i) -> void:
	if auto != Auto.NONE or game.winner != Game.NO_WINNER:
		return
	if game.turn != Unit.Team.PLAYER or not Grid.in_bounds(cell):
		return
	var clicked := game.unit_at(cell)

	match state:
		State.IDLE:
			if clicked != null and clicked.team == Unit.Team.PLAYER and not clicked.acted:
				_select_unit(clicked)
		State.MOVE_SELECT:
			if clicked == selected:
				# Clicking the unit itself: stay in place, go to action select.
				move_from = selected.pos
				_enter_action_select()
			elif clicked != null and clicked.team == Unit.Team.PLAYER and not clicked.acted:
				_select_unit(clicked)
			elif clicked == null and reachable.has(cell) and not reachable[cell]["pass_only"]:
				move_from = selected.pos
				game.move_unit(selected, cell)
				unit_nodes[selected.id].refresh(true)
				_enter_action_select()
			else:
				_clear_selection()
		State.ACTION_SELECT:
			if clicked != null and attack_targets.has(clicked):
				if ui.anims_enabled():
					# Interactive battle: strikes resolve inside the vignette,
					# one QTE per blow (offense for ours, brace for counters).
					var pending := game.begin_battle(selected, clicked)
					_clear_selection()
					_refresh_all()
					if await _play_interactive(pending):
						_maybe_auto_end_turn()
				else:
					game.attack(selected, clicked)
					game.take_last_battle()  # no vignette to replay it
					_clear_selection()
					_refresh_all()
					_maybe_auto_end_turn()
			elif clicked != null and heal_targets.has(clicked):
				game.heal(selected, clicked)
				_finish_action()
			else:
				game.hold(selected)  # click elsewhere = wait
				_finish_action()
	_refresh_all()


# --- Selection state machine ---------------------------------------------------


func _select_unit(unit: Unit) -> void:
	selected = unit
	reachable = Grid.reachable_tiles(unit, game.units)
	state = State.MOVE_SELECT


func _enter_action_select() -> void:
	state = State.ACTION_SELECT
	reachable = {}
	attack_targets = Grid.targets_from(selected, selected.pos, game.units)
	heal_targets = Grid.heal_targets_from(selected, selected.pos, game.units)
	if attack_targets.is_empty() and heal_targets.is_empty():
		game.hold(selected)  # nothing to do here but wait
		_finish_action()


func _finish_action() -> void:
	_clear_selection()
	_maybe_auto_end_turn()


func _clear_selection() -> void:
	state = State.IDLE
	selected = null
	reachable = {}
	attack_targets = []
	heal_targets = []
	move_from = Vector2i(-1, -1)
	ui.hide_forecast()


func _maybe_auto_end_turn() -> void:
	if game.winner != Game.NO_WINNER:
		return
	if game.turn == Unit.Team.PLAYER and game.all_acted(Unit.Team.PLAYER):
		game.end_turn()
		_start_auto(Auto.ENEMY_PHASE)


# --- Timer-driven AI (enemy phase and full simulation) ---------------------------


func _start_auto(mode: Auto) -> void:
	auto = mode
	sim_timer.start(ui.sim_delay())


func _on_sim_timer() -> void:
	match auto:
		Auto.ENEMY_PHASE:
			_step_enemy_phase()
		Auto.SIMULATE:
			_step_simulation()
		Auto.NONE:
			pass


func _step_enemy_phase() -> void:
	if game.winner != Game.NO_WINNER:
		auto = Auto.NONE
	else:
		# With animations on, enemy attacks become interactive battles so the
		# player can brace (red QTE) against incoming strikes and time counters.
		var acted := game.step_ai(Unit.Team.ENEMY, ui.anims_enabled())
		if acted != null:
			unit_nodes[acted.id].refresh(true)
			_refresh_all()
			var pending := game.take_pending_battle()
			var flow_ok: bool
			if not pending.is_empty():
				flow_ok = await _play_interactive(pending)
			else:
				flow_ok = await _play_battle_if_any()
			if flow_ok and auto == Auto.ENEMY_PHASE:
				sim_timer.start(ui.sim_delay())
		else:
			game.end_turn()
			auto = Auto.NONE
	_refresh_all()


func _step_simulation() -> void:
	if game.winner != Game.NO_WINNER:
		auto = Auto.NONE
		ui.set_simulating(false)
	else:
		var acted := game.step_ai(game.turn)
		if acted != null:
			unit_nodes[acted.id].refresh(true)
		else:
			game.end_turn()
		_refresh_all()
		if await _play_battle_if_any() and auto == Auto.SIMULATE:
			sim_timer.start(ui.sim_delay())
	_refresh_all()


# If the last action was a battle and animations are on, play the vignette
# and wait for it to close. The caller `await`s this, so nothing advances
# the game underneath the animation — the GDScript equivalent of the
# continuation-callback plumbing in js/main.js, but linear to read.
# Returns false if a Reset invalidated this flow while it was suspended.
func _play_battle_if_any() -> bool:
	var battle := game.take_last_battle()
	if battle.is_empty() or not ui.anims_enabled():
		return true
	var my_epoch := epoch
	battle_fx.play(battle, ui.battle_time_scale())
	await battle_fx.finished
	if epoch != my_epoch:
		return false
	_refresh_all()
	return true


# Run an interactive (QTE) battle; strikes resolve as the player times
# presses. Same epoch guard as the replay path.
func _play_interactive(pending: Dictionary) -> bool:
	var my_epoch := epoch
	battle_fx.play_interactive(pending, game)
	await battle_fx.finished
	if epoch != my_epoch:
		return false
	_refresh_all()
	return true


# --- Buttons ---------------------------------------------------------------------


func _on_simulate_toggled() -> void:
	if game.winner != Game.NO_WINNER:
		return
	if auto == Auto.SIMULATE:
		auto = Auto.NONE
		sim_timer.stop()
		ui.set_simulating(false)
	else:
		_clear_selection()
		ui.set_simulating(true)
		_start_auto(Auto.SIMULATE)
	_refresh_all()


func _on_end_turn() -> void:
	if auto != Auto.NONE or game.winner != Game.NO_WINNER \
			or game.turn != Unit.Team.PLAYER:
		return
	_clear_selection()
	game.end_turn()
	_start_auto(Auto.ENEMY_PHASE)
	_refresh_all()


func _on_reset() -> void:
	auto = Auto.NONE
	epoch += 1                # invalidate suspended flows BEFORE abort resumes them
	sim_timer.stop()
	battle_fx.abort()
	ui.set_simulating(false)
	_clear_selection()
	game.reset()
	_spawn_unit_nodes()
	_replay_log()
	_refresh_all()


# --- View sync ---------------------------------------------------------------------


func _refresh_all() -> void:
	var path: Array[Vector2i] = []
	if state == State.MOVE_SELECT and Grid.in_bounds(board.hover) \
			and reachable.has(board.hover) and not reachable[board.hover]["pass_only"]:
		path = Grid.path_to(reachable, board.hover)
	board.refresh(reachable, path, attack_targets, heal_targets)
	for u: Unit in game.units:
		var node: Node2D = unit_nodes[u.id]
		node.selected = u == selected
		node.refresh()
	ui.update_banner(game)
	ui.update_counts(game)
