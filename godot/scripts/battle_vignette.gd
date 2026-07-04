# Port of js/battle.js — the Fire Emblem style combat cut-in.
#
# Two modes:
#  - REPLAY: combat already resolved by the core; the overlay replays the
#    recorded events (used for AI-vs-AI simulation).
#  - INTERACTIVE: Legend of Dragoon style additions. The battle resolves
#    strike by strike DURING the vignette:
#      * Offense (your strikes): SWIPE in the direction shown, timed
#        against the shrinking ring — one swipe per step of your class's
#        rhythm. Scales damage dealt 0.75x-1.5x. (Mobile prototype: on
#        the main branch this is a timed tap instead.)
#      * Defense (incoming strikes): HOLD (finger down) in anticipation
#        while the enemy charges you, then RELEASE as the blow lands.
#        Parried! 50% / Blocked 75% / held-through Guarded 90% /
#        dropped guard 100%.
#    Ring color = combat type: blue physical, green magic, red defense.
#
# Godot concepts on display:
#  - A full-screen Control with mouse_filter STOP shields everything under
#    it while visible; _gui_input gives us press/skip clicks for free.
#  - The JS requestAnimationFrame loop becomes _process(delta).
#  - Keyboard timing input arrives via _unhandled_key_input.
#  - Completion is a SIGNAL (`finished`); main.gd `await`s it.
class_name BattleVignette
extends Control

signal finished

enum Phase { INTRO, APPROACH, QTE, IMPACT, OUTRO }

const W := 560.0
const H := 300.0
const INTRO_DUR := 0.35   # seconds: panel fade-in, fighters slide in
const STRIKE := 0.95      # seconds per attack event (replay mode)
const IMPACT_AT := 0.35   # fraction of a replay strike beat where the blow lands
const APPROACH_DUR := 0.33  # interactive: lunge-in before the QTE
const IMPACT_DUR := 0.8   # interactive: blow lands, then retreat
const OUTRO := 0.6
const OUTRO_KILL := 1.1
const HP_DRAIN_RATE := 30.0
const QTE_LEAD_IN := 0.45  # pause before the first ring starts shrinking
const QTE_GAP := 0.3       # pause between presses of a multi-step addition
const RING_POS := Vector2(280, 105)
const RING_START := 74.0
const RING_END := 26.0
# A swipe = touch travels this many pixels; graded the moment it's crossed.
const SWIPE_MIN_DIST := 60.0
const SWIPE_DIRS := {
	"up": Vector2.UP, "down": Vector2.DOWN,
	"left": Vector2.LEFT, "right": Vector2.RIGHT,
}

var playing := false
var interactive := false
var time_scale := 1.0
var left := {}
var right := {}
var popups: Array = []
var flash := 0.0
var panel_alpha := 0.0

# replay mode
var beats: Array = []
var beat_index := 0
var beat_elapsed := 0.0

# interactive mode
var game_ref: Game = null
var battle := {}
var strikes: Array = []
var strike_idx := -1
var qte := {}
var phase := Phase.INTRO
var phase_t := 0.0
var outro_dur := OUTRO
var outro_beat := {}
var finish_called := false

# swipe tracking (one finger; index 0 with mouse emulation)
var touch_start := Vector2.ZERO
var touch_active := false
var swipe_consumed := false


# --- QTE grading (static so the headless test can exercise it) ----------------


static func grade_press(err: float, spec: Dictionary) -> Dictionary:
	if err <= spec["perfect"]:
		return {"points": 1.0, "text": "PERFECT!", "color": Color("ffe94d")}
	if err <= spec["good"]:
		return {"points": 0.6, "text": "Good", "color": Color.WHITE}
	return {"points": 0.0, "text": "Miss", "color": Color("8a90a0")}


# Offense: average press quality maps to a damage multiplier.
static func offense_result(points: Array) -> Dictionary:
	var avg := 0.0
	for p: float in points:
		avg += p
	avg /= points.size()
	var label := "Whiffed"
	if avg >= 0.999:
		label = "MAX!"
	elif avg >= 0.6:
		label = "Great"
	elif avg > 0.0:
		label = "Good"
	return {"mult": 0.75 + 0.75 * avg, "label": label}


# Defense: grade the hold-and-release parry. `q` carries the hold state
# machine: waiting (never pressed) | holding | released (+release_err).
static func defense_result(q: Dictionary) -> Dictionary:
	if q["state"] == "released":
		if q["release_err"] <= q["spec"]["perfect"]:
			return {"mult": 0.5, "label": "Parried!"}
		if q["release_err"] <= q["spec"]["good"]:
			return {"mult": 0.75, "label": "Blocked"}
		return {"mult": 1.0, "label": "Exposed"}  # dropped the guard too early
	if q["state"] == "holding":
		return {"mult": 0.9, "label": "Guarded"}  # static guard
	return {"mult": 1.0, "label": "Exposed"}      # never raised the guard


# --- setup ---------------------------------------------------------------------


func _setup_scene(p_battle: Dictionary) -> void:
	left = _make_fighter(p_battle["attacker"], -1, p_battle["attacker_hp_before"])
	right = _make_fighter(p_battle["defender"], 1, p_battle["defender_hp_before"])
	popups = []
	flash = 0.0
	panel_alpha = 0.0
	visible = true
	playing = true


# `side` is -1 for the left fighter, +1 for the right.
func _make_fighter(unit: Unit, side: int, hp_before: int) -> Dictionary:
	return {
		"unit": unit, "side": side,
		"home": 150.0 if side == -1 else 410.0,
		"x": 150.0 if side == -1 else 410.0,
		"lunge": 0.0,       # 0..1 progress toward the other fighter
		"dodge": 0.0,       # remaining dodge-animation seconds
		"shake": 0.0,       # remaining hit-shake seconds
		"shown_hp": float(hp_before),
		"target_hp": float(hp_before),
		"alpha": 1.0,
	}


func _fighter_of(unit: Unit) -> Dictionary:
	return left if left["unit"] == unit else right


# --- REPLAY mode (battle has "events") ------------------------------------------


func play(p_battle: Dictionary, p_time_scale := 1.0) -> void:
	interactive = false
	game_ref = null
	time_scale = p_time_scale
	_setup_scene(p_battle)

	var killed := false
	for ev: Dictionary in p_battle["events"]:
		if ev["type"] == "hit" and ev["killed"]:
			killed = true
	beats = [{"type": "intro", "dur": INTRO_DUR}]
	for ev: Dictionary in p_battle["events"]:
		beats.append({"type": "strike", "dur": STRIKE, "ev": ev, "applied": false})
	beats.append({"type": "outro", "dur": OUTRO_KILL if killed else OUTRO,
			"death_shown": false})
	beat_index = 0
	beat_elapsed = 0.0


# --- INTERACTIVE mode (battle has "strikes") -------------------------------------


func play_interactive(p_battle: Dictionary, p_game: Game) -> void:
	interactive = true
	game_ref = p_game
	battle = p_battle
	time_scale = 1.0   # QTEs can't be time-scaled: timing IS the game
	_setup_scene(p_battle)
	strikes = p_battle["strikes"]
	strike_idx = -1
	qte = {}
	finish_called = false
	phase = Phase.INTRO
	phase_t = 0.0


# --- lifecycle --------------------------------------------------------------------


func skip() -> void:
	if playing and not interactive:  # no skipping an addition
		_finish()


# Hard stop (used by Reset): don't commit a half-played battle; the caller
# resets all game state. Emits `finished` so awaiting coroutines resume
# (they bail via main.gd's epoch guard).
func abort() -> void:
	if playing:
		_finish(false)


func _finish(commit := true) -> void:
	if commit and interactive and game_ref != null and not finish_called:
		finish_called = true
		game_ref.finish_battle(battle["attacker"])
	playing = false
	visible = false
	finished.emit()


# --- input ------------------------------------------------------------------------


# MOBILE PROTOTYPE: input arrives as touch events. On a phone these come
# from the screen; on desktop, emulate_touch_from_mouse (project.godot)
# synthesizes them from mouse drags, so the swipes are testable anywhere.
#  - Offense: swipe in the step's direction; graded when the finger has
#    travelled SWIPE_MIN_DIST, so timing is judged at the flick itself.
#  - Defense: finger down = guard up, finger up = release (unchanged).
#  - Replay mode: any tap skips.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not interactive:
				skip()
				return
			touch_active = true
			swipe_consumed = false
			touch_start = event.position
			_hold_start()
		else:
			touch_active = false
			if interactive:
				if not swipe_consumed:
					_try_swipe(event.position - touch_start)
				_hold_end()
	elif event is InputEventScreenDrag and interactive and touch_active \
			and not swipe_consumed:
		_try_swipe(event.position - touch_start)


# Desktop fallbacks: arrow keys are instant swipes, Space drives the parry.
func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or not interactive or not event is InputEventKey:
		return
	if event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			_hold_start()
		elif not event.pressed:
			_hold_end()
	elif event.pressed and not event.echo:
		match event.keycode:
			KEY_UP: _swipe("up")
			KEY_DOWN: _swipe("down")
			KEY_LEFT: _swipe("left")
			KEY_RIGHT: _swipe("right")


# Turn a touch displacement into a directional swipe once it's long enough.
func _try_swipe(delta_pos: Vector2) -> void:
	if delta_pos.length() < SWIPE_MIN_DIST:
		return
	swipe_consumed = true
	var dir := "right" if delta_pos.x > 0 else "left"
	if absf(delta_pos.y) > absf(delta_pos.x):
		dir = "down" if delta_pos.y > 0 else "up"
	_swipe(dir)


# A completed swipe: for offense, both the DIRECTION and the MOMENT the
# swipe completed are graded — wrong direction is a Miss no matter the
# timing. Defense ignores swipes (it's hold/release).
func _swipe(dir: String) -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] != "offense" or qte["step_t"] < 0.0 or qte["step_done"]:
		return
	var wanted: String = qte["spec"]["swipes"][qte["step"]]
	if dir != wanted:
		_record_press({"points": 0.0, "text": "Miss", "color": Color("8a90a0")})
		return
	var period: float = qte["spec"]["periods"][qte["step"]]
	_record_press(grade_press(absf(qte["step_t"] - period), qte["spec"]))


# Guard up (defense only — offense is driven by completed swipes).
func _hold_start() -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] == "defense" and qte["state"] == "waiting":
		qte["state"] = "holding"


# Release: only meaningful for the defensive parry.
func _hold_end() -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] == "defense" and qte["state"] == "holding":
		qte["state"] = "released"
		qte["release_t"] = qte["step_t"]
		qte["release_err"] = absf(qte["step_t"]
				- (qte["spec"]["windup"] + qte["spec"]["travel"]))


# --- frame driver -------------------------------------------------------------------


func _process(delta: float) -> void:
	if not playing:
		return
	var dt := minf(delta, 0.05) * time_scale
	if interactive:
		_step_interactive(dt)
	else:
		_step_replay(dt)
	_update_common(dt)
	queue_redraw()


func _step_replay(dt: float) -> void:
	beat_elapsed += dt
	var beat: Dictionary = beats[beat_index]
	var t: float = minf(1.0, beat_elapsed / beat["dur"])
	match beat["type"]:
		"intro":
			_update_intro(t)
		"strike":
			panel_alpha = 1.0
			var ev: Dictionary = beat["ev"]
			var lunge: float
			if t < IMPACT_AT:
				lunge = t / IMPACT_AT
			elif t < 0.6:
				lunge = 1.0
			else:
				lunge = 1.0 - (t - 0.6) / 0.4
			_fighter_of(ev["from"])["lunge"] = clampf(lunge, 0.0, 1.0)
			if not beat["applied"] and t >= IMPACT_AT:
				beat["applied"] = true
				_apply_impact(ev)
		"outro":
			_update_outro(beat, t, beat["dur"])
	if t >= 1.0:
		beat_index += 1
		beat_elapsed = 0.0
		if beat_index >= beats.size():
			_finish()


func _step_interactive(dt: float) -> void:
	phase_t += dt
	match phase:
		Phase.INTRO:
			var t := minf(1.0, phase_t / INTRO_DUR)
			_update_intro(t)
			if t >= 1.0:
				_next_strike()
		Phase.APPROACH:
			panel_alpha = 1.0
			var t := minf(1.0, phase_t / APPROACH_DUR)
			_actor_fighter()["lunge"] = _ease_out(t)
			if t >= 1.0:
				_start_qte()
		Phase.QTE:
			_update_qte(dt)
		Phase.IMPACT:
			var t := minf(1.0, phase_t / IMPACT_DUR)
			# hold the pose briefly, then retreat
			_actor_fighter()["lunge"] = 1.0 if t < 0.35 else 1.0 - (t - 0.35) / 0.65
			if t >= 1.0:
				_next_strike()
		Phase.OUTRO:
			var t := minf(1.0, phase_t / outro_dur)
			_update_outro(outro_beat, t, outro_dur)
			if t >= 1.0:
				_finish()


func _actor_fighter() -> Dictionary:
	return _fighter_of(strikes[strike_idx]["actor"])


func _next_strike() -> void:
	phase_t = 0.0
	# find the next strike whose actor and target are both still alive
	strike_idx += 1
	while strike_idx < strikes.size() \
			and (strikes[strike_idx]["actor"].hp <= 0
			or strikes[strike_idx]["target"].hp <= 0):
		strike_idx += 1

	if strike_idx >= strikes.size():
		# battle over: commit the result, then play the outro
		if not finish_called:
			finish_called = true
			game_ref.finish_battle(battle["attacker"])
		var killed: bool = left["target_hp"] <= 0.0 or right["target_hp"] <= 0.0
		outro_dur = OUTRO_KILL if killed else OUTRO
		outro_beat = {"death_shown": false}
		phase = Phase.OUTRO
	elif strikes[strike_idx]["actor"].team == Unit.Team.PLAYER:
		phase = Phase.APPROACH
	else:
		# Incoming strike: no separate approach — the enemy's charge happens
		# DURING the QTE and is itself the release cue for the parry.
		_start_qte()


func _start_qte() -> void:
	var strike: Dictionary = strikes[strike_idx]
	var actor: Unit = strike["actor"]
	if actor.team == Unit.Team.PLAYER:
		qte = {
			"spec": actor.u_class.qte,
			"kind": "offense",
			"color": GameData.qte_colors["magic"] if actor.u_class.is_magic \
					else GameData.qte_colors["physical"],
			"step": 0,
			"step_t": -QTE_LEAD_IN,  # negative time = wind-up, ring not moving
			"step_done": false,
			"points": [],
		}
	else:
		qte = {
			"spec": GameData.DEFENSE_QTE,
			"kind": "defense",
			"color": GameData.qte_colors["defense"],
			"step_t": 0.0,
			"state": "waiting",   # waiting -> holding -> released
			"release_t": 0.0,
			"release_err": 0.0,
		}
	phase = Phase.QTE
	phase_t = 0.0


func _update_qte(dt: float) -> void:
	qte["step_t"] += dt
	if qte["kind"] == "defense":
		_update_defense_qte()
		return
	var period: float = qte["spec"]["periods"][qte["step"]]
	if not qte["step_done"] and qte["step_t"] > period + qte["spec"]["good"]:
		_record_press({"points": 0.0, "text": "Miss", "color": Color("8a90a0")})
	if qte["step_done"]:
		qte["step"] += 1
		qte["step_done"] = false
		if qte["step"] >= qte["spec"]["periods"].size():
			_resolve_qte_strike()
		else:
			qte["step_t"] = -QTE_GAP


func _update_defense_qte() -> void:
	var impact: float = qte["spec"]["windup"] + qte["spec"]["travel"]
	# the enemy's lunge IS the timing cue: it tracks the gauge exactly
	var k: float = clampf((qte["step_t"] - qte["spec"]["windup"])
			/ qte["spec"]["travel"], 0.0, 1.0)
	_actor_fighter()["lunge"] = k

	if qte["state"] == "released":
		# blow still lands at the impact moment even if the guard dropped early
		if qte["step_t"] >= maxf(impact, qte["release_t"]):
			_resolve_qte_strike()
	elif qte["step_t"] >= impact + qte["spec"]["good"]:
		_resolve_qte_strike()  # held through, or never raised the guard


func _record_press(grade: Dictionary) -> void:
	qte["points"].append(grade["points"])
	qte["step_done"] = true
	_popup(grade["text"], RING_POS + Vector2(0, -38), grade["color"], 16, 0.7)


func _resolve_qte_strike() -> void:
	var strike: Dictionary = strikes[strike_idx]
	var off_mult := 1.0
	var def_mult := 1.0
	var label := ""
	if qte["kind"] == "offense":
		var r := offense_result(qte["points"])
		off_mult = r["mult"]
		label = r["label"]
	else:
		var r := defense_result(qte)
		def_mult = r["mult"]
		label = r["label"]
	var ev: Dictionary = game_ref.strike(strike["actor"], strike["target"],
			off_mult, def_mult, label)
	_apply_impact(ev)
	if label != "":
		_popup(label, Vector2(W / 2.0, 84), qte["color"], 20, 1.0)
	qte = {}
	phase = Phase.IMPACT
	phase_t = 0.0


# --- shared beat pieces --------------------------------------------------------------


func _update_intro(t: float) -> void:
	panel_alpha = t
	var eased := _ease_out(t)
	left["x"] = left["home"] - 80.0 * (1.0 - eased)
	right["x"] = right["home"] + 80.0 * (1.0 - eased)


func _update_outro(beat: Dictionary, t: float, dur: float) -> void:
	for f: Dictionary in [left, right]:
		if f["target_hp"] <= 0.0:
			f["alpha"] = maxf(0.0, 1.0 - t * 1.6)
			if not beat["death_shown"]:
				beat["death_shown"] = true
				_popup("%s falls!" % f["unit"].unit_name, Vector2(W / 2.0, 60),
						Color("ffe94d"), 20, 1.0)
	var fade_start: float = 1.0 - 0.35 / dur
	panel_alpha = 1.0 if t <= fade_start else 1.0 - (t - fade_start) / (1.0 - fade_start)


func _apply_impact(ev: Dictionary) -> void:
	var victim := _fighter_of(ev["to"])
	var vx: float = victim["x"] + victim["side"] * 10.0
	if ev["type"] == "miss":
		victim["dodge"] = 0.35
		_popup("Miss", Vector2(vx, 120), Color("aab0be"), 18, 0.9)
	else:
		victim["target_hp"] = maxf(0.0, victim["target_hp"] - ev["dmg"])
		victim["shake"] = 0.4 if ev["crit"] else 0.28
		if ev["crit"]:
			flash = 0.22
			_popup("CRITICAL!", Vector2(W / 2.0, 52), Color("ffe94d"), 22, 0.9)
		_popup(str(ev["dmg"]), Vector2(vx, 118),
				Color("ffe94d") if ev["crit"] else Color.WHITE,
				30 if ev["crit"] else 24, 0.9)


func _popup(text: String, pos: Vector2, color: Color, size_px: int, dur: float) -> void:
	popups.append({"text": text, "pos": pos, "color": color,
			"size": size_px, "age": 0.0, "dur": dur})


func _update_common(dt: float) -> void:
	for f: Dictionary in [left, right]:
		if f["shown_hp"] > f["target_hp"]:
			f["shown_hp"] = maxf(f["target_hp"], f["shown_hp"] - HP_DRAIN_RATE * dt)
		f["dodge"] = maxf(0.0, f["dodge"] - dt)
		f["shake"] = maxf(0.0, f["shake"] - dt)
	flash = maxf(0.0, flash - dt)
	for p: Dictionary in popups:
		p["age"] += dt
	popups = popups.filter(func(p: Dictionary) -> bool: return p["age"] < p["dur"])


func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _fighter_x(f: Dictionary) -> float:
	var other: Dictionary = right if f == left else left
	var towards: float = (other["home"] - f["home"]) * 0.72
	var x: float = f["x"] + towards * _ease_out(f["lunge"])
	if f["dodge"] > 0.0:
		var d01: float = 1.0 - f["dodge"] / 0.35
		x += sin(d01 * PI) * 38.0 * f["side"]
	if f["shake"] > 0.0:
		x += sin(f["shake"] * 70.0) * 8.0 * (f["shake"] / 0.28)
	return x


# --- drawing (all in panel-local coordinates, offset to screen centre) ----------------


func _draw() -> void:
	if not playing:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45 * panel_alpha))

	var origin := (size - Vector2(W, H)) / 2.0
	draw_set_transform(origin)

	var a := panel_alpha
	var font := ThemeDB.fallback_font

	# panel + sky + platforms
	draw_rect(Rect2(0, 0, W, H), Color(0.09, 0.10, 0.13, 0.97 * a))
	draw_rect(Rect2(0, 0, W, H), Color(0.23, 0.25, 0.30, a), false, 2.0)
	var strips := 10
	for i in strips:
		var c := Color("313a4d").lerp(Color("20242f"), float(i) / (strips - 1))
		c.a = a
		draw_rect(Rect2(10, 10 + i * 19.0, W - 20, 19.0), c)
	for hx: float in [150.0, 410.0]:
		_draw_ellipse(Vector2(hx, 212), Vector2(78, 16), Color(0, 0, 0, 0.35 * a))

	for f: Dictionary in [left, right]:
		_draw_fighter(f, font)
	_draw_hp_box(left, 22.0, font)
	_draw_hp_box(right, W / 2.0 + 8.0, font)
	if interactive and phase == Phase.QTE and not qte.is_empty():
		_draw_qte(font)

	for p: Dictionary in popups:
		var k: float = p["age"] / p["dur"]
		var col: Color = p["color"]
		col.a = a * (1.0 - k * k)
		var pos: Vector2 = p["pos"] - Vector2(120, 26.0 * k)
		draw_string(font, pos, p["text"], HORIZONTAL_ALIGNMENT_CENTER, 240,
				p["size"], col)

	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, a * (flash / 0.22) * 0.75))

	draw_set_transform(Vector2.ZERO)  # reset for safety


func _draw_qte(font: Font) -> void:
	# slight extra dim so the prompts read clearly
	draw_rect(Rect2(10, 10, W - 20, 190), Color(0.04, 0.05, 0.06, 0.35 * panel_alpha))
	if qte["kind"] == "defense":
		_draw_defense_qte(font)
	else:
		_draw_offense_qte(font)


func _draw_offense_qte(font: Font) -> void:
	var color: Color = qte["color"]
	color.a = panel_alpha
	var period: float = qte["spec"]["periods"][qte["step"]]

	# step dots: one per press in this class's addition
	var n: int = qte["spec"]["periods"].size()
	for i in n:
		var dx: float = RING_POS.x + (i - (n - 1) / 2.0) * 18.0
		var dot := color if i < qte["step"] else Color(1, 1, 1, 0.25 * panel_alpha)
		draw_circle(Vector2(dx, RING_POS.y - 52.0), 5.0, dot)

	# target ring
	draw_arc(RING_POS, RING_END, 0, TAU, 48, color, 3.0)

	# required swipe direction, drawn as an arrow inside the target ring
	_draw_swipe_arrow(SWIPE_DIRS[qte["spec"]["swipes"][qte["step"]]], color)

	# shrinking ring (only once the wind-up is over)
	if qte["step_t"] >= 0.0 and not qte["step_done"]:
		var k: float = minf(1.0, qte["step_t"] / period)
		var r := RING_START - (RING_START - RING_END) * k
		draw_arc(RING_POS, r, 0, TAU, 48, color, 4.0)

	draw_string(font, RING_POS + Vector2(-120, 48), "SWIPE WITH THE ARROW",
			HORIZONTAL_ALIGNMENT_CENTER, 240, 11, Color(1, 1, 1, 0.55 * panel_alpha))


func _draw_swipe_arrow(dir: Vector2, color: Color) -> void:
	var tip := RING_POS + dir * 14.0
	var tail := RING_POS - dir * 12.0
	var side := Vector2(-dir.y, dir.x)  # perpendicular
	draw_line(tail, tip - dir * 6.0, color, 4.0)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * 10.0 + side * 7.0, tip - dir * 10.0 - side * 7.0,
	]), color)


func _draw_defense_qte(font: Font) -> void:
	var color: Color = qte["color"]
	color.a = panel_alpha
	var impact: float = qte["spec"]["windup"] + qte["spec"]["travel"]
	var total: float = impact + qte["spec"]["good"]  # gauge ends at last legal release
	var xa := 160.0
	var xb := 400.0
	var y := 100.0
	var to_x := func(t: float) -> float:
		return xa + (xb - xa) * minf(1.0, t / total)

	# track
	draw_line(Vector2(xa, y), Vector2(xb, y), Color(1, 1, 1, 0.3 * panel_alpha), 3.0)
	# good / perfect release zones around the impact notch
	var gx1: float = to_x.call(impact - qte["spec"]["good"])
	var gx2: float = to_x.call(impact + qte["spec"]["good"])
	draw_rect(Rect2(gx1, y - 8, gx2 - gx1, 16), Color(0.88, 0.28, 0.28, 0.30 * panel_alpha))
	var px1: float = to_x.call(impact - qte["spec"]["perfect"])
	var px2: float = to_x.call(impact + qte["spec"]["perfect"])
	draw_rect(Rect2(px1, y - 8, px2 - px1, 16), Color(0.88, 0.28, 0.28, 0.65 * panel_alpha))
	# impact notch
	var nx: float = to_x.call(impact)
	draw_line(Vector2(nx, y - 14), Vector2(nx, y + 14), color, 3.0)
	# the incoming blow
	var holding: bool = qte["state"] == "holding"
	var mx: float = to_x.call(qte["step_t"])
	var marker := Color(1, 1, 1, panel_alpha if holding else 0.6 * panel_alpha)
	draw_line(Vector2(mx, y - 11), Vector2(mx, y + 11), marker, 4.0 if holding else 3.0)

	# shield arc on the defender while the guard is up
	var defender := _fighter_of(strikes[strike_idx]["target"])
	var dx := _fighter_x(defender)
	var shield := color
	if holding:
		shield.a = panel_alpha * 0.95
	elif qte["state"] == "waiting":
		shield.a = panel_alpha * 0.3
	else:
		shield.a = panel_alpha * 0.15
	draw_arc(Vector2(dx, 175.0), 44.0, 0, TAU, 48, shield, 5.0 if holding else 2.0)

	var hint := ""
	if qte["state"] == "waiting":
		hint = "HOLD TO GUARD"
	elif holding:
		hint = "RELEASE AS THE BLOW LANDS!"
	if hint != "":
		draw_string(font, Vector2((xa + xb) / 2.0 - 140, y + 34), hint,
				HORIZONTAL_ALIGNMENT_CENTER, 280, 11, Color(1, 1, 1, 0.55 * panel_alpha))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var ang := TAU * i / 24.0
		pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y))
	draw_colored_polygon(pts, color)


func _draw_fighter(f: Dictionary, font: Font) -> void:
	var unit: Unit = f["unit"]
	var x := _fighter_x(f)
	var y := 175.0
	var colors: Dictionary = GameData.team_colors[unit.team]
	var fa: float = panel_alpha * f["alpha"]
	var body: Color = colors["main"]
	body.a = fa
	var rim: Color = colors["dark"]
	rim.a = fa
	draw_circle(Vector2(x, y), 34, body)
	draw_arc(Vector2(x, y), 34, 0, TAU, 48, rim, 4.0)
	draw_string(font, Vector2(x - 40, y + 12), unit.u_class.icon,
			HORIZONTAL_ALIGNMENT_CENTER, 80, 34, Color(1, 1, 1, fa))


func _draw_hp_box(f: Dictionary, bx: float, font: Font) -> void:
	var unit: Unit = f["unit"]
	var a := panel_alpha
	var by := 232.0
	var w := W / 2.0 - 30.0
	draw_rect(Rect2(bx, by, w, 58), Color(0.05, 0.05, 0.07, 0.92 * a))
	draw_rect(Rect2(bx, by, w, 58), Color(0.23, 0.25, 0.30, a), false, 2.0)
	draw_string(font, Vector2(bx + 10, by + 18), unit.unit_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.91, 0.91, 0.93, a))
	draw_string(font, Vector2(bx + 10, by + 33),
			"%s · %s" % [unit.u_class.display_name, unit.u_class.weapon],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.60, 0.63, 0.68, a))
	var bar_w := w - 62.0
	draw_rect(Rect2(bx + 10, by + 40, bar_w, 10), Color(0, 0, 0, 0.6 * a))
	var frac: float = maxf(0.0, f["shown_hp"] / unit.max_hp)
	var bar := Color("5ad35a") if frac > 0.5 \
			else (Color("e8c33a") if frac > 0.25 else Color("e05050"))
	bar.a = a
	draw_rect(Rect2(bx + 11, by + 41, (bar_w - 2.0) * frac, 8), bar)
	draw_string(font, Vector2(bx + w - 60, by + 50),
			"%d/%d" % [ceili(f["shown_hp"]), unit.max_hp],
			HORIZONTAL_ALIGNMENT_RIGHT, 50, 13, Color(0.91, 0.91, 0.93, a))
