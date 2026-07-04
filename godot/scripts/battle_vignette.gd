# Port of js/battle.js — the Fire Emblem style combat cut-in.
#
# Godot concepts on display:
#  - A full-screen Control with mouse_filter STOP shields everything under
#    it while visible: board clicks AND sidebar buttons are swallowed, and
#    _gui_input gives us the click-to-skip for free. When hidden, it's inert.
#  - The JS requestAnimationFrame loop becomes _process(delta): the engine
#    calls it every frame with the elapsed time — same dt-driven timeline,
#    no callback rescheduling.
#  - Completion is a SIGNAL (`finished`); main.gd `await`s it, so game flow
#    reads top-to-bottom instead of nesting continuations like the JS port.
extends Control

signal finished

const W := 560.0
const H := 300.0
const INTRO := 0.35       # seconds: panel fade-in, fighters slide in
const STRIKE := 0.95      # seconds per attack event
const IMPACT_AT := 0.35   # fraction of a strike beat where the blow lands
const OUTRO := 0.6
const OUTRO_KILL := 1.1
const HP_DRAIN_RATE := 30.0

var playing := false
var time_scale := 1.0
var left := {}
var right := {}
var beats: Array = []
var beat_index := 0
var beat_elapsed := 0.0
var popups: Array = []
var flash := 0.0
var panel_alpha := 0.0


# battle = { attacker, defender, attacker_hp_before, defender_hp_before, events }
func play(battle: Dictionary, p_time_scale := 1.0) -> void:
	time_scale = p_time_scale
	left = _make_fighter(battle["attacker"], -1, battle["attacker_hp_before"])
	right = _make_fighter(battle["defender"], 1, battle["defender_hp_before"])
	popups = []
	flash = 0.0
	panel_alpha = 0.0

	var killed := false
	for ev: Dictionary in battle["events"]:
		if ev["type"] == "hit" and ev["killed"]:
			killed = true
	beats = [{"type": "intro", "dur": INTRO}]
	for ev: Dictionary in battle["events"]:
		beats.append({"type": "strike", "dur": STRIKE, "ev": ev, "applied": false})
	beats.append({"type": "outro", "dur": OUTRO_KILL if killed else OUTRO,
			"death_shown": false})

	beat_index = 0
	beat_elapsed = 0.0
	playing = true
	visible = true


# `side` is -1 for the left fighter, +1 for the right — used to mirror
# lunge/dodge directions without branching on strings.
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


func skip() -> void:
	if playing:
		_finish()


# Hard stop without animation (used by Reset). Emits `finished` so any
# coroutine awaiting the vignette resumes; callers re-check state after.
func abort() -> void:
	if playing:
		_finish()


func _finish() -> void:
	playing = false
	visible = false
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		skip()


func _process(delta: float) -> void:
	if not playing:
		return
	var dt := minf(delta, 0.05) * time_scale
	beat_elapsed += dt

	var beat: Dictionary = beats[beat_index]
	var t: float = minf(1.0, beat_elapsed / beat["dur"])
	_update_beat(beat, t)
	_update_common(dt)
	queue_redraw()

	if t >= 1.0:
		beat_index += 1
		beat_elapsed = 0.0
		if beat_index >= beats.size():
			_finish()


func _update_beat(beat: Dictionary, t: float) -> void:
	match beat["type"]:
		"intro":
			panel_alpha = t
			var eased := _ease_out(t)
			left["x"] = left["home"] - 80.0 * (1.0 - eased)
			right["x"] = right["home"] + 80.0 * (1.0 - eased)
		"strike":
			panel_alpha = 1.0
			var ev: Dictionary = beat["ev"]
			var actor := _fighter_of(ev["from"])
			var victim := _fighter_of(ev["to"])
			# lunge toward the victim, land the blow, retreat
			var lunge: float
			if t < IMPACT_AT:
				lunge = t / IMPACT_AT
			elif t < 0.6:
				lunge = 1.0
			else:
				lunge = 1.0 - (t - 0.6) / 0.4
			actor["lunge"] = clampf(lunge, 0.0, 1.0)
			if not beat["applied"] and t >= IMPACT_AT:
				beat["applied"] = true
				_apply_impact(ev, victim)
		"outro":
			for f: Dictionary in [left, right]:
				if f["target_hp"] <= 0.0:
					f["alpha"] = maxf(0.0, 1.0 - t * 1.6)
					if not beat["death_shown"]:
						beat["death_shown"] = true
						_popup("%s falls!" % f["unit"].unit_name,
								Vector2(W / 2.0, 60), Color("ffe94d"), 20)
			var fade_start: float = 1.0 - 0.35 / beat["dur"]
			panel_alpha = 1.0 if t <= fade_start \
					else 1.0 - (t - fade_start) / (1.0 - fade_start)


func _apply_impact(ev: Dictionary, victim: Dictionary) -> void:
	var vx: float = victim["x"] + victim["side"] * 10.0
	if ev["type"] == "miss":
		victim["dodge"] = 0.35
		_popup("Miss", Vector2(vx, 120), Color("aab0be"), 18)
	else:
		victim["target_hp"] = maxf(0.0, victim["target_hp"] - ev["dmg"])
		victim["shake"] = 0.4 if ev["crit"] else 0.28
		if ev["crit"]:
			flash = 0.22
			_popup("CRITICAL!", Vector2(W / 2.0, 52), Color("ffe94d"), 22)
		_popup(str(ev["dmg"]), Vector2(vx, 118),
				Color("ffe94d") if ev["crit"] else Color.WHITE,
				30 if ev["crit"] else 24)


func _popup(text: String, pos: Vector2, color: Color, size_px: int) -> void:
	popups.append({"text": text, "pos": pos, "color": color,
			"size": size_px, "age": 0.0, "dur": 0.9})


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


func _fighter_of(unit: Unit) -> Dictionary:
	return left if left["unit"] == unit else right


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


# --- drawing (all in panel-local coordinates, offset to screen centre) --------


func _draw() -> void:
	if not playing:
		return
	# dim the battlefield behind the panel
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
