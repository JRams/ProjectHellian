# Port of the DOM side of js/main.js (panels, buttons, log, forecast).
#
# Godot concept: UI lives on a CanvasLayer (renders above the 2D world,
# ignores camera) and is built from Control nodes managed by containers —
# VBoxContainer stacks children, PanelContainer draws a background.
# Buttons expose a `pressed` signal; this script re-exports them as
# game-level signals so main.gd never touches button nodes directly.
extends CanvasLayer

signal simulate_toggled
signal end_turn_pressed
signal reset_pressed

const SPEEDS := [["Slow", 0.6], ["Normal", 0.3], ["Fast", 0.09]]

const LOG_COLORS := {
	"phase": "8dbef0", "player-hit": "8dbef0", "enemy-hit": "f0938d",
	"miss": "767d8c", "death": "ffb14d", "heal": "7de8a0",
	"victory": "ffe94d", "info": "c8ccd6",
}

# @onready defers the assignment until the node tree is ready — the Godot
# equivalent of document.getElementById, resolved by scene-tree path.
@onready var banner: Label = $Banner
@onready var simulate_btn: Button = $Sidebar/Controls/SimulateBtn
@onready var end_turn_btn: Button = $Sidebar/Controls/EndTurnBtn
@onready var reset_btn: Button = $Sidebar/Controls/ResetBtn
@onready var speed: OptionButton = $Sidebar/SpeedRow/Speed
@onready var counts: Label = $Sidebar/Counts
@onready var info: RichTextLabel = $Sidebar/InfoPanel/Info
@onready var log_label: RichTextLabel = $Sidebar/LogPanel/Log
@onready var forecast: PanelContainer = $Forecast
@onready var forecast_text: RichTextLabel = $Forecast/ForecastText


func _ready() -> void:
	for s: Array in SPEEDS:
		speed.add_item(s[0])
	speed.select(1)
	# Signal connections in code. (In the editor you'd use the Node dock —
	# same mechanism, this way it's visible in the diff.)
	simulate_btn.pressed.connect(func() -> void: simulate_toggled.emit())
	end_turn_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	reset_btn.pressed.connect(func() -> void: reset_pressed.emit())


func sim_delay() -> float:
	return SPEEDS[speed.selected][1]


func set_simulating(on: bool) -> void:
	simulate_btn.text = "⏸ Pause" if on else "▶ Simulate"


func update_banner(game: Game) -> void:
	if game.winner == Unit.Team.PLAYER:
		banner.text = "★ VICTORY — Player army wins!"
	elif game.winner == Unit.Team.ENEMY:
		banner.text = "★ DEFEAT — Enemy army wins!"
	else:
		var phase := "Player" if game.turn == Unit.Team.PLAYER else "Enemy"
		banner.text = "Turn %d — %s Phase" % [game.turn_count, phase]
	# Enum values are ints, so they key the colors Dictionary directly.
	var team: int = game.turn
	if game.winner != Game.NO_WINNER:
		team = game.winner
	banner.add_theme_color_override("font_color", GameData.team_colors[team]["light"])


func update_counts(game: Game) -> void:
	counts.text = "Player %d · Enemy %d" % [
		game.living_units(Unit.Team.PLAYER).size(),
		game.living_units(Unit.Team.ENEMY).size(),
	]


func show_unit_info(u: Unit) -> void:
	var c := u.u_class
	var team_hex: String = GameData.team_colors[u.team]["main"].to_html(false)
	var rng_text := ""
	if not c.attack_range.is_empty():
		var parts := PackedStringArray()
		for r: int in c.attack_range:
			parts.append(str(r))
		rng_text = " (rng %s)" % ",".join(parts)
	info.text = ("[b][color=#%s]●[/color] %s — %s[/b]\n" +
			"HP %d/%d   Mov %d\nStr %d   Mag %d\nSkl %d   Spd %d\nDef %d   Res %d\n" +
			"[color=#ffe94d]%s%s[/color]\n[color=#9aa0ae]%s[/color]") % [
		team_hex, u.unit_name, c.display_name,
		u.hp, u.max_hp, c.movement, c.strength, c.magic_power,
		c.skill, c.speed, c.defense, c.resistance,
		c.weapon, rng_text, c.description,
	]


func show_terrain_info(cell: Vector2i) -> void:
	var t := Grid.terrain_at(cell)
	var cost_text := "—" if t.cost == INF else str(int(t.cost))
	info.text = "[b]%s[/b]\n[color=#9aa0ae]Move cost %s · +%d Def · +%d Avoid[/color]" % [
		t.display_name, cost_text, t.defense, t.avoid,
	]


func show_default_info() -> void:
	info.text = ("[b]Grimwater Crossing[/b]\n[color=#9aa0ae]Select a blue unit " +
			"to move it, or press Simulate to watch the AI fight it out.[/color]")


# Connected to Game.log_added — the core signals, the UI listens.
func on_log_added(entry: Dictionary) -> void:
	var color: String = LOG_COLORS.get(entry["kind"], "c8ccd6")
	log_label.append_text("[color=#%s]%s[/color]\n" % [color, entry["text"]])


func clear_log() -> void:
	log_label.clear()


func show_forecast(attacker: Unit, defender: Unit) -> void:
	var f := Combat.battle_forecast(attacker, defender)
	var a: Dictionary = f["atk"]
	var text := ("[b][color=#8dbef0]Battle Forecast[/color][/b]\n%s → %s\n" +
			"Dmg %d%s · Hit %d%% · Crit %d%%") % [
		attacker.unit_name, defender.unit_name,
		a["dmg"], " ×2" if a["double"] else "", a["hit"], a["crit"],
	]
	if f["def"] != null:
		var d: Dictionary = f["def"]
		text += "\n[color=#f0938d]Counter: Dmg %d%s · Hit %d%% · Crit %d%%[/color]" % [
			d["dmg"], " ×2" if d["double"] else "", d["hit"], d["crit"],
		]
	else:
		text += "\n[color=#f0938d]No counterattack[/color]"
	forecast_text.text = text
	forecast.visible = true


func hide_forecast() -> void:
	forecast.visible = false
