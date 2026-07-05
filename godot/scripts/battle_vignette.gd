# Port of js/battle.js — the Fire Emblem style combat cut-in.
# MOBILE PROTOTYPE, portrait layout: the enemy fights from the TOP of the
# panel, the player's unit from the BOTTOM, and all touch input happens in
# a dedicated SWIPE PAD below the scene.
#
# Two modes:
#  - REPLAY: combat already resolved by the core; the overlay replays the
#    recorded events (used for AI-vs-AI simulation). Tap to skip.
#  - INTERACTIVE: Legend of Dragoon style additions, resolved strike by
#    strike DURING the vignette:
#      * Offense (your strikes): SWIPE in the pad in the direction shown,
#        timed against the shrinking ring — one swipe per step of your
#        class's rhythm. Scales damage dealt 0.75x-1.5x.
#      * Defense, HOLD parry (physical attackers): finger down anywhere in
#        the pad to raise your guard while the enemy charges, RELEASE as
#        the blow lands. Parried! 50% / Blocked 75% / held-through
#        Guarded 90% / dropped guard 100%.
#      * Defense, DEFLECT parry (magic attackers): a spot lights up in the
#        pad — finger down ON THE SPOT, then SWIPE the shown direction as
#        the blow lands to fling the spell aside. Same grading; wrong spot
#        caps you at Guarded, wrong direction leaves you Exposed.
#    Successful parries buzz the phone (Input.vibrate_handheld).
#    Colors = combat type: blue physical, green magic, red defense.
class_name BattleVignette
extends Control

signal finished

enum Phase { INTRO, APPROACH, QTE, IMPACT, OUTRO }

# --- portrait panel geometry ---------------------------------------------------
const VW := 440.0
const VH := 800.0
const CENTER_X := 220.0
const TOP_BOX_Y := 14.0          # enemy HP box
const SCENE_RECT := Rect2(16, 84, 408, 390)
const TOP_FIGHTER_Y := 180.0     # enemy home
const BOT_FIGHTER_Y := 396.0     # player home
const BOT_BOX_Y := 482.0         # player HP box
const PAD_RECT := Rect2(20, 552, 400, 228)  # the dedicated swipe area
const RING_POS := Vector2(220, 666)         # offense ring, inside the pad
const GAUGE_Y := 592.0                      # defense timing gauge, inside the pad
const DEFLECT_ANCHORS: Array[float] = [100.0, 220.0, 340.0]  # spot x options

# --- timing ----------------------------------------------------------------------
const INTRO_DUR := 0.35
const STRIKE := 0.95      # seconds per attack event (replay mode)
const IMPACT_AT := 0.35   # fraction of a replay strike beat where the blow lands
const APPROACH_DUR := 0.33
const IMPACT_DUR := 0.8
const OUTRO := 0.6
const OUTRO_KILL := 1.1
const HP_DRAIN_RATE := 30.0
const QTE_LEAD_IN := 0.45
const QTE_GAP := 0.3
const RING_START := 74.0
const RING_END := 26.0
# A swipe = touch travels this many pixels; graded the moment it's crossed.
const SWIPE_MIN_DIST := 60.0
const SPOT_RADIUS := 34.0  # how close the finger must land for a deflect
const SWIPE_DIRS := {
	"up": Vector2.UP, "down": Vector2.DOWN,
	"left": Vector2.LEFT, "right": Vector2.RIGHT,
}

var playing := false
var interactive := false
var time_scale := 1.0
var top_f := {}   # the enemy-team fighter (fights from the top)
var bot_f := {}   # the player-team fighter (fights from the bottom)
var popups: Array = []
var flash := 0.0
var panel_alpha := 0.0
var battle_terrain := "plain"  # the defender's tile drives the backdrop

# panel chrome (built once; StyleBoxFlat gives rounded corners + borders)
var panel_style := _make_style(Color("14161d"), 10, Color("6a5a3a"), 2)
var plate_style := _make_style(Color(0.09, 0.10, 0.13, 0.96), 6, Color("6a5a3a"), 1)
var pad_style := _make_style(Color(0.055, 0.063, 0.086, 0.95), 8, Color("e04848"), 2)

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

# touch tracking (one finger; index 0 with mouse emulation)
var touch_start := Vector2.ZERO
var touch_active := false
var swipe_consumed := false


static func _make_style(bg: Color, radius: int, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	return sb


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


# Defense: grade the parry. `q` carries the state machine.
# mode "hold":    waiting | holding | released (+release_err)
# mode "deflect": waiting | holding (+armed) | swiped (+swipe_err) | released
static func defense_result(q: Dictionary) -> Dictionary:
	var mode: String = q.get("mode", "hold")
	if mode == "deflect":
		if q["state"] == "swiped":
			if q["swipe_err"] <= q["spec"]["perfect"]:
				return {"mult": 0.5, "label": "Parried!"}
			if q["swipe_err"] <= q["spec"]["good"]:
				return {"mult": 0.75, "label": "Blocked"}
			return {"mult": 1.0, "label": "Exposed"}
		if q["state"] == "holding":
			return {"mult": 0.9, "label": "Guarded"}  # guard up, no deflect
		return {"mult": 1.0, "label": "Exposed"}      # dropped / wrong dir / none
	# hold mode
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


# Portrait rule: the ENEMY fights from the top, the PLAYER from the bottom,
# regardless of who initiated the battle.
func _setup_scene(p_battle: Dictionary) -> void:
	var att: Unit = p_battle["attacker"]
	var def_u: Unit = p_battle["defender"]
	if att.team == Unit.Team.ENEMY:
		top_f = _make_fighter(att, -1, p_battle["attacker_hp_before"])
		bot_f = _make_fighter(def_u, 1, p_battle["defender_hp_before"])
	else:
		top_f = _make_fighter(def_u, -1, p_battle["defender_hp_before"])
		bot_f = _make_fighter(att, 1, p_battle["attacker_hp_before"])
	var tile_ch: String = GameData.MAP_LAYOUT[def_u.pos.y][def_u.pos.x]
	battle_terrain = GameData.TERRAIN_CHARS[tile_ch]
	popups = []
	flash = 0.0
	panel_alpha = 0.0
	visible = true
	playing = true


# `side` is -1 for the top fighter, +1 for the bottom one.
func _make_fighter(unit: Unit, side: int, hp_before: int) -> Dictionary:
	var home := TOP_FIGHTER_Y if side == -1 else BOT_FIGHTER_Y
	return {
		"unit": unit, "side": side,
		"home_y": home,
		"y": home + side * -70.0,  # slides in from off-scene during the intro
		"lunge": 0.0,       # 0..1 progress toward the other fighter (vertical)
		"dodge": 0.0,       # remaining dodge-animation seconds (horizontal)
		"shake": 0.0,       # remaining hit-shake seconds (horizontal)
		"shown_hp": float(hp_before),
		"target_hp": float(hp_before),
		"alpha": 1.0,
	}


func _fighter_of(unit: Unit) -> Dictionary:
	return top_f if top_f["unit"] == unit else bot_f


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


func _panel_origin() -> Vector2:
	return (size - Vector2(VW, VH)) / 2.0


# Touch events; on desktop, emulate_touch_from_mouse synthesizes them from
# mouse drags. During QTEs only touches that START inside the swipe pad
# count — the pad is the controller, the scene above is just the view.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not interactive:
				skip()
				return
			var local: Vector2 = event.position - _panel_origin()
			if phase == Phase.QTE and not PAD_RECT.has_point(local):
				return
			touch_active = true
			swipe_consumed = false
			touch_start = local
			_hold_start(local)
		else:
			if not touch_active:
				return
			touch_active = false
			if interactive:
				var local: Vector2 = event.position - _panel_origin()
				if not swipe_consumed:
					_try_swipe(local - touch_start)
				_hold_end()
	elif event is InputEventScreenDrag and interactive and touch_active \
			and not swipe_consumed:
		var local: Vector2 = event.position - _panel_origin()
		_try_swipe(local - touch_start)


# Desktop fallbacks: arrow keys are instant swipes, Space is the hold/parry
# finger (position requirement waived — keyboard always "arms" a deflect).
func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or not interactive or not event is InputEventKey:
		return
	if event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			_hold_start(Vector2(-1000, -1000), true)
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


# A completed swipe. Offense: direction AND the moment the swipe completed
# are graded. Deflect defense: only valid while holding an ARMED guard —
# right direction is graded on timing, wrong direction breaks the guard.
func _swipe(dir: String) -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] == "offense":
		if qte["step_t"] < 0.0 or qte["step_done"]:
			return
		var wanted: String = qte["spec"]["swipes"][qte["step"]]
		if dir != wanted:
			_record_press({"points": 0.0, "text": "Miss", "color": Color("8a90a0")})
			return
		var period: float = qte["spec"]["periods"][qte["step"]]
		_record_press(grade_press(absf(qte["step_t"] - period), qte["spec"]))
	elif qte.get("mode", "hold") == "deflect" and qte["state"] == "holding":
		if not qte["armed"]:
			return  # finger is down but not on the spot: no deflect from here
		if dir == qte["dir"]:
			qte["state"] = "swiped"
			qte["swipe_t"] = qte["step_t"]
			qte["swipe_err"] = absf(qte["step_t"]
					- (qte["spec"]["windup"] + qte["spec"]["travel"]))
		else:
			qte["state"] = "released"  # flung it the wrong way: guard broken


# Guard up. For a deflect parry the finger must land on the lit spot to arm
# the deflect; anywhere else still raises a plain (Guarded-at-best) guard.
func _hold_start(local: Vector2, keyboard := false) -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] != "defense" or qte["state"] != "waiting":
		return
	qte["state"] = "holding"
	if qte.get("mode", "hold") == "deflect":
		qte["armed"] = keyboard or local.distance_to(qte["spot"]) <= SPOT_RADIUS


# Release. Hold parry: graded against the impact. Deflect parry: releasing
# without having swiped drops the guard.
func _hold_end() -> void:
	if not playing or not interactive or phase != Phase.QTE:
		return
	if qte["kind"] != "defense" or qte["state"] != "holding":
		return
	if qte.get("mode", "hold") == "deflect":
		qte["state"] = "released"
	else:
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
		var killed: bool = top_f["target_hp"] <= 0.0 or bot_f["target_hp"] <= 0.0
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
		# Magic attacks demand the positional DEFLECT parry; physical ones
		# the plain hold. Both live inside the swipe pad.
		var deflect := actor.u_class.is_magic
		qte = {
			"spec": GameData.DEFENSE_QTE,
			"kind": "defense",
			"mode": "deflect" if deflect else "hold",
			"color": GameData.qte_colors["defense"],
			"step_t": 0.0,
			"state": "waiting",
			"release_t": 0.0,
			"release_err": 0.0,
		}
		if deflect:
			var rng := game_ref.rng
			qte["armed"] = false
			qte["swipe_t"] = 0.0
			qte["swipe_err"] = 0.0
			qte["spot"] = Vector2(
					DEFLECT_ANCHORS[rng.randi_range(0, DEFLECT_ANCHORS.size() - 1)],
					RING_POS.y)
			qte["dir"] = ["up", "left", "right"][rng.randi_range(0, 2)]
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

	if qte["state"] == "swiped":
		if qte["step_t"] >= maxf(impact, qte["swipe_t"]):
			_resolve_qte_strike()
	elif qte["state"] == "released" and qte.get("mode", "hold") == "hold":
		# blow still lands at the impact moment even if the guard dropped early
		if qte["step_t"] >= maxf(impact, qte["release_t"]):
			_resolve_qte_strike()
	elif qte["step_t"] >= impact + qte["spec"]["good"]:
		_resolve_qte_strike()  # held through / never guarded / broken deflect


func _record_press(grade: Dictionary) -> void:
	qte["points"].append(grade["points"])
	qte["step_done"] = true
	_popup(grade["text"], RING_POS + Vector2(0, -56), grade["color"], 16, 0.7)


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
		# Haptic feedback for a successful parry: a solid buzz for the
		# perfect one, a lighter tick for a block. No-op on desktop.
		if label == "Parried!":
			Input.vibrate_handheld(70)
		elif label == "Blocked":
			Input.vibrate_handheld(35)
	var ev: Dictionary = game_ref.strike(strike["actor"], strike["target"],
			off_mult, def_mult, label)
	_apply_impact(ev)
	if label != "":
		_popup(label, Vector2(CENTER_X, 290.0), qte["color"], 20, 1.0)
	qte = {}
	phase = Phase.IMPACT
	phase_t = 0.0


# --- shared beat pieces --------------------------------------------------------------


func _update_intro(t: float) -> void:
	panel_alpha = t
	var eased := _ease_out(t)
	for f: Dictionary in [top_f, bot_f]:
		f["y"] = f["home_y"] + f["side"] * -70.0 * (1.0 - eased)


func _update_outro(beat: Dictionary, t: float, dur: float) -> void:
	for f: Dictionary in [top_f, bot_f]:
		if f["target_hp"] <= 0.0:
			f["alpha"] = maxf(0.0, 1.0 - t * 1.6)
			if not beat["death_shown"]:
				beat["death_shown"] = true
				_popup("%s falls!" % f["unit"].unit_name, Vector2(CENTER_X, 140.0),
						Color("ffe94d"), 20, 1.0)
	var fade_start: float = 1.0 - 0.35 / dur
	panel_alpha = 1.0 if t <= fade_start else 1.0 - (t - fade_start) / (1.0 - fade_start)


func _apply_impact(ev: Dictionary) -> void:
	var victim := _fighter_of(ev["to"])
	var vpos := _fighter_pos(victim) + Vector2(46.0, -34.0)
	if ev["type"] == "miss":
		victim["dodge"] = 0.35
		_popup("Miss", vpos, Color("aab0be"), 18, 0.9)
	else:
		victim["target_hp"] = maxf(0.0, victim["target_hp"] - ev["dmg"])
		victim["shake"] = 0.4 if ev["crit"] else 0.28
		if ev["crit"]:
			flash = 0.22
			_popup("CRITICAL!", Vector2(CENTER_X, 120.0), Color("ffe94d"), 22, 0.9)
		_popup(str(ev["dmg"]), vpos,
				Color("ffe94d") if ev["crit"] else Color.WHITE,
				30 if ev["crit"] else 24, 0.9)


func _popup(text: String, pos: Vector2, color: Color, size_px: int, dur: float) -> void:
	popups.append({"text": text, "pos": pos, "color": color,
			"size": size_px, "age": 0.0, "dur": dur})


func _update_common(dt: float) -> void:
	for f: Dictionary in [top_f, bot_f]:
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


# Portrait: lunges travel vertically toward the other fighter; dodges and
# hit-shakes displace horizontally.
func _fighter_pos(f: Dictionary) -> Vector2:
	var other: Dictionary = bot_f if f == top_f else top_f
	var towards: float = (other["home_y"] - f["home_y"]) * 0.54
	var x := CENTER_X
	var y: float = f["y"] + towards * _ease_out(f["lunge"])
	if f["dodge"] > 0.0:
		var d01: float = 1.0 - f["dodge"] / 0.35
		x += sin(d01 * PI) * 38.0
	if f["shake"] > 0.0:
		x += sin(f["shake"] * 70.0) * 8.0 * (f["shake"] / 0.28)
	return Vector2(x, y)


# --- drawing (panel-local coordinates, offset to screen centre) ----------------------


func _draw() -> void:
	if not playing:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45 * panel_alpha))

	var origin := _panel_origin()
	draw_set_transform(origin)

	var a := panel_alpha
	var font := ThemeDB.fallback_font

	# panel chrome: bronze-trimmed frame. Fading the whole subtree with
	# self_modulate lets the backdrop keep its own per-shape alphas.
	self_modulate = Color(1, 1, 1, a)
	panel_style.bg_color = Color(0.078, 0.086, 0.113, 0.97)
	draw_style_box(panel_style, Rect2(0, 0, VW, VH))

	# the setting: terrain-aware layered backdrop (from the defender's tile)
	BattleArt.draw_backdrop(self, SCENE_RECT, battle_terrain)
	draw_rect(SCENE_RECT, Color(0.78, 0.67, 0.43, 0.25), false, 1.0)

	# fighters as figures. draw_figure manages its own canvas transforms for
	# rotated weapons, so drop to identity and pass absolute positions.
	draw_set_transform(Vector2.ZERO)
	for f: Dictionary in [top_f, bot_f]:
		if f["alpha"] > 0.02:
			var unit: Unit = f["unit"]
			var colors: Dictionary = GameData.team_colors[unit.team]
			BattleArt.draw_figure(self, origin + _fighter_pos(f), unit.u_class.icon,
					colors["main"], colors["dark"], f["side"] == -1,
					1.05 if f["side"] == -1 else 1.2)
	draw_set_transform(origin)

	_draw_hp_box(top_f, TOP_BOX_Y, font)
	_draw_hp_box(bot_f, BOT_BOX_Y, font)
	_draw_pad(font)
	if interactive and phase == Phase.QTE and not qte.is_empty():
		if qte["kind"] == "defense":
			_draw_defense_qte(font)
		else:
			_draw_offense_qte(font)

	for p: Dictionary in popups:
		var k: float = p["age"] / p["dur"]
		var col: Color = p["color"]
		col.a = a * (1.0 - k * k)
		var pos: Vector2 = p["pos"] - Vector2(120, 26.0 * k)
		draw_string(font, pos + Vector2(1.5, 1.5), p["text"],
				HORIZONTAL_ALIGNMENT_CENTER, 240, p["size"],
				Color(0, 0, 0, col.a * 0.8))
		draw_string(font, pos, p["text"], HORIZONTAL_ALIGNMENT_CENTER, 240,
				p["size"], col)

	if flash > 0.0:
		draw_rect(Rect2(0, 0, VW, VH), Color(1, 1, 1, a * (flash / 0.22) * 0.75))

	draw_set_transform(Vector2.ZERO)  # reset for safety


# The dedicated swipe area at the bottom of the panel.
func _draw_pad(font: Font) -> void:
	var a := panel_alpha
	var border := Color(0.30, 0.33, 0.40, a)
	if interactive and phase == Phase.QTE and not qte.is_empty():
		border = qte["color"]
		border.a = a * 0.8
	pad_style.border_color = border
	draw_style_box(pad_style, PAD_RECT)
	# bronze corner ticks
	var tick := Color(0.78, 0.67, 0.43, 0.4 * a)
	for corner: Array in [[28.0, 560.0, 1.0, 1.0], [412.0, 560.0, -1.0, 1.0],
			[28.0, 772.0, 1.0, -1.0], [412.0, 772.0, -1.0, -1.0]]:
		var c := Vector2(corner[0], corner[1])
		draw_line(c + Vector2(corner[2] * 10.0, 0), c, tick, 2.0)
		draw_line(c, c + Vector2(0, corner[3] * 10.0), tick, 2.0)
	draw_string(font, PAD_RECT.position + Vector2(16, 19), "SWIPE AREA",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.3 * a))


func _draw_offense_qte(font: Font) -> void:
	var color: Color = qte["color"]
	color.a = panel_alpha
	var period: float = qte["spec"]["periods"][qte["step"]]

	# step dots: one per swipe in this class's addition
	var n: int = qte["spec"]["periods"].size()
	for i in n:
		var dx: float = RING_POS.x + (i - (n - 1) / 2.0) * 18.0
		var dot := color if i < qte["step"] else Color(1, 1, 1, 0.25 * panel_alpha)
		draw_circle(Vector2(dx, RING_POS.y - 66.0), 5.0, dot)

	# target ring + required swipe direction
	draw_arc(RING_POS, RING_END, 0, TAU, 48, color, 3.0)
	_draw_swipe_arrow(RING_POS, SWIPE_DIRS[qte["spec"]["swipes"][qte["step"]]], color)

	# shrinking ring (only once the wind-up is over)
	if qte["step_t"] >= 0.0 and not qte["step_done"]:
		var k: float = minf(1.0, qte["step_t"] / period)
		var r := RING_START - (RING_START - RING_END) * k
		draw_arc(RING_POS, r, 0, TAU, 48, color, 4.0)

	draw_string(font, Vector2(RING_POS.x - 120, PAD_RECT.end.y - 14),
			"SWIPE WITH THE ARROW", HORIZONTAL_ALIGNMENT_CENTER, 240, 11,
			Color(1, 1, 1, 0.55 * panel_alpha))


func _draw_defense_qte(font: Font) -> void:
	var color: Color = qte["color"]
	color.a = panel_alpha
	var impact: float = qte["spec"]["windup"] + qte["spec"]["travel"]
	var total: float = impact + qte["spec"]["good"]
	var xa := 50.0
	var xb := 390.0
	var to_x := func(t: float) -> float:
		return xa + (xb - xa) * minf(1.0, t / total)
	var deflect: bool = qte.get("mode", "hold") == "deflect"
	var holding: bool = qte["state"] == "holding"

	# timing gauge across the top of the pad
	draw_line(Vector2(xa, GAUGE_Y), Vector2(xb, GAUGE_Y),
			Color(1, 1, 1, 0.3 * panel_alpha), 3.0)
	var gx1: float = to_x.call(impact - qte["spec"]["good"])
	var gx2: float = to_x.call(impact + qte["spec"]["good"])
	draw_rect(Rect2(gx1, GAUGE_Y - 8, gx2 - gx1, 16),
			Color(0.88, 0.28, 0.28, 0.30 * panel_alpha))
	var px1: float = to_x.call(impact - qte["spec"]["perfect"])
	var px2: float = to_x.call(impact + qte["spec"]["perfect"])
	draw_rect(Rect2(px1, GAUGE_Y - 8, px2 - px1, 16),
			Color(0.88, 0.28, 0.28, 0.65 * panel_alpha))
	var nx: float = to_x.call(impact)
	draw_line(Vector2(nx, GAUGE_Y - 14), Vector2(nx, GAUGE_Y + 14), color, 3.0)
	var mx: float = to_x.call(qte["step_t"])
	var marker := Color(1, 1, 1, panel_alpha if holding else 0.6 * panel_alpha)
	draw_line(Vector2(mx, GAUGE_Y - 11), Vector2(mx, GAUGE_Y + 11), marker,
			4.0 if holding else 3.0)

	if deflect:
		# the spot the finger must land on, plus the deflect direction
		var spot: Vector2 = qte["spot"]
		var armed: bool = holding and qte["armed"]
		var pulse := 0.65 + 0.35 * sin(qte["step_t"] * 8.0)
		var spot_col := color
		spot_col.a = panel_alpha * (0.95 if armed else 0.45 * pulse)
		draw_arc(spot, SPOT_RADIUS, 0, TAU, 40, spot_col, 5.0 if armed else 3.0)
		draw_circle(spot, 6.0, spot_col)
		_draw_swipe_arrow(spot + SWIPE_DIRS[qte["dir"]] * (SPOT_RADIUS + 22.0),
				SWIPE_DIRS[qte["dir"]], color)
	else:
		# shield arc on the player's unit while the guard is up
		var shield := color
		if holding:
			shield.a = panel_alpha * 0.95
		elif qte["state"] == "waiting":
			shield.a = panel_alpha * 0.3
		else:
			shield.a = panel_alpha * 0.15
		draw_arc(_fighter_pos(bot_f), 44.0, 0, TAU, 48, shield, 5.0 if holding else 2.0)

	var hint := ""
	if deflect:
		if qte["state"] == "waiting":
			hint = "HOLD THE SPOT…"
		elif holding and qte["armed"]:
			hint = "SWIPE %s AS IT LANDS!" % qte["dir"].to_upper()
		elif holding:
			hint = "WRONG SPOT — GUARDING ONLY"
	elif qte["state"] == "waiting":
		hint = "HOLD TO GUARD"
	elif holding:
		hint = "RELEASE AS THE BLOW LANDS!"
	if hint != "":
		draw_string(font, Vector2(CENTER_X - 140, PAD_RECT.end.y - 14), hint,
				HORIZONTAL_ALIGNMENT_CENTER, 280, 11, Color(1, 1, 1, 0.55 * panel_alpha))


func _draw_swipe_arrow(at: Vector2, dir: Vector2, color: Color) -> void:
	var tip := at + dir * 14.0
	var tail := at - dir * 12.0
	var side := Vector2(-dir.y, dir.x)  # perpendicular
	draw_line(tail, tip - dir * 6.0, color, 4.0)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * 10.0 + side * 7.0, tip - dir * 10.0 - side * 7.0,
	]), color)


func _draw_hp_box(f: Dictionary, by: float, font: Font) -> void:
	var unit: Unit = f["unit"]
	var a := panel_alpha
	var bx := 20.0
	var w := VW - 40.0
	draw_style_box(plate_style, Rect2(bx, by, w, 58))
	# team ribbon on the left edge
	var tc: Dictionary = GameData.team_colors[unit.team]
	var ribbon: Color = tc["main"]
	ribbon.a = a
	draw_rect(Rect2(bx + 1, by + 2, 5, 54), ribbon)
	draw_string(font, Vector2(bx + 16, by + 20), unit.unit_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.94, 0.93, 0.9, a))
	draw_string(font, Vector2(bx + 16, by + 35),
			"%s · %s" % [unit.u_class.display_name, unit.u_class.weapon],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.60, 0.63, 0.68, a))
	var bar_w := w - 84.0
	draw_rect(Rect2(bx + 16, by + 41, bar_w, 11), Color(0, 0, 0, 0.65 * a))
	var frac: float = maxf(0.0, f["shown_hp"] / unit.max_hp)
	var bar := Color("4fc94f") if frac > 0.5 \
			else (Color("e8c33a") if frac > 0.25 else Color("e05050"))
	bar.a = a
	draw_rect(Rect2(bx + 17, by + 42, (bar_w - 2.0) * frac, 9), bar)
	var sheen := bar.lightened(0.35)
	draw_rect(Rect2(bx + 17, by + 42, (bar_w - 2.0) * frac, 4), sheen)
	draw_string(font, Vector2(bx + w - 66, by + 52),
			"%d/%d" % [ceili(f["shown_hp"]), unit.max_hp],
			HORIZONTAL_ALIGNMENT_RIGHT, 56, 13, Color(0.94, 0.93, 0.9, a))
