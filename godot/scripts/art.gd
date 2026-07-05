# Procedural art for the portrait prototype — battle backdrops, class
# figures, and map tiles. No texture assets: everything is draw_* calls,
# which keeps the repo art-free and the whole look tweakable in code.
#
# All functions are static and take the CanvasItem to draw on, so both
# the board and the vignette share one art module. Detail placement uses
# a tiny deterministic LCG (same constants as the canvas prototype this
# was iterated in), so scenes are stable frame to frame.
class_name BattleArt
extends RefCounted

const SKY_TOP := Color("2e4270")
const SKY_MID := Color("5a6b9e")
const SKY_HORIZON := Color("c9906a")
const SUN := Color("f2d8a0")
const SKIN := Color("e8b98a")
const METAL := Color("9aa2b0")
const METAL_DARK := Color("6b7382")

const GROUND_TOP := {
	"plain": Color("6d9457"), "forest": Color("587f47"),
	"mountain": Color("8d8171"), "water": Color("6d9457"),
	"bridge": Color("6d9457"), "fort": Color("8b8b90"),
}
const GROUND_BOT := {
	"plain": Color("43602f"), "forest": Color("35502a"),
	"mountain": Color("5d5548"), "water": Color("43602f"),
	"bridge": Color("43602f"), "fort": Color("5a5a60"),
}


# Deterministic LCG so detail placement is stable and portable.
class Lcg:
	var s: int

	func _init(seed_v: int) -> void:
		s = seed_v & 0xFFFFFFFF

	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0


static func draw_ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color,
		from_ang := 0.0, to_ang := TAU) -> void:
	var pts := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var ang := from_ang + (to_ang - from_ang) * i / steps
		pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y))
	ci.draw_colored_polygon(pts, color)


# Vertical gradient faked with horizontal strips.
static func _grad_rect(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color,
		strips := 14) -> void:
	for i in strips:
		var c := top.lerp(bottom, float(i) / (strips - 1))
		ci.draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * i / strips,
				rect.size.x, rect.size.y / strips + 1.0), c)


# =============================================================================
# BATTLE BACKDROP — terrain-aware layered scene inside `rect`.
# =============================================================================


static func draw_backdrop(ci: CanvasItem, rect: Rect2, terrain: String) -> void:
	var rng := Lcg.new(7)
	var sx := rect.position.x
	var sy := rect.position.y
	var sw := rect.size.x
	var sh := rect.size.y
	var horizon := sy + sh * 0.22

	# sky
	_grad_rect(ci, Rect2(sx, sy, sw, horizon - sy), SKY_TOP, SKY_HORIZON, 16)
	# sun + glow (concentric rings stand in for a radial gradient)
	var sun := Vector2(sx + sw * 0.72, horizon - 18.0)
	for i in 5:
		var r := 60.0 - i * 10.0
		ci.draw_circle(sun, r, Color(0.95, 0.85, 0.63, 0.05 + i * 0.02))
	ci.draw_circle(sun, 14.0, SUN)
	# clouds
	for i in 3:
		var cx := sx + sw * (0.14 + i * 0.31) + rng.next() * 20.0
		var cy := sy + 34.0 + i * 26.0 + rng.next() * 12.0
		var s := 0.8 + rng.next() * 0.5
		draw_ellipse(ci, Vector2(cx, cy), Vector2(46 * s, 11 * s), Color(0.89, 0.87, 0.93, 0.11))
		draw_ellipse(ci, Vector2(cx - 18 * s, cy - 7 * s), Vector2(22 * s, 9 * s),
				Color(0.89, 0.87, 0.93, 0.09))
		draw_ellipse(ci, Vector2(cx + 16 * s, cy - 6 * s), Vector2(26 * s, 10 * s),
				Color(0.89, 0.87, 0.93, 0.09))
	# birds
	for i in 3:
		var bx := sx + sw * (0.2 + rng.next() * 0.4)
		var by := sy + 40.0 + rng.next() * 50.0
		ci.draw_arc(Vector2(bx - 4, by), 4.0, PI * 1.15, PI * 1.85, 6,
				Color(0.12, 0.13, 0.2, 0.55), 1.5)
		ci.draw_arc(Vector2(bx + 4, by), 4.0, PI * 1.15, PI * 1.85, 6,
				Color(0.12, 0.13, 0.2, 0.55), 1.5)

	# two ridgelines
	for pass_i in 2:
		var pts := PackedVector2Array([Vector2(sx, horizon)])
		for i in 9:
			var off := 16.0 * pass_i
			var hgt := (14.0 - 8.0 * pass_i) + rng.next() * (26.0 - 12.0 * pass_i) \
					+ ((i + pass_i) % 2) * (10.0 - 2.0 * pass_i)
			pts.append(Vector2(minf(sx + sw, sx + sw * i / 8.0 + off), horizon - hgt))
		pts.append(Vector2(sx + sw, horizon))
		ci.draw_colored_polygon(pts,
				Color(0.2, 0.23, 0.36, 0.9) if pass_i == 0 else Color(0.17, 0.2, 0.3, 0.95))

	# ground
	var gtop: Color = GROUND_TOP.get(terrain, GROUND_TOP["plain"])
	var gbot: Color = GROUND_BOT.get(terrain, GROUND_BOT["plain"])
	_grad_rect(ci, Rect2(sx, horizon, sw, sy + sh - horizon), gtop, gbot, 14)
	if terrain == "plain" or terrain == "forest" or terrain == "mountain":
		draw_ellipse(ci, Vector2(sx + sw / 2.0, horizon + 4.0), Vector2(sw * 0.55, 10.0),
				gtop, PI, TAU)

	match terrain:
		"forest":
			for i in 7:
				var tx := sx + 14.0 + (sw - 28.0) * (i / 6.0) + (rng.next() - 0.5) * 14.0
				_pine(ci, Vector2(tx, horizon + 8.0), 0.55 + rng.next() * 0.25, 0.75)
			_pine(ci, Vector2(sx + 30.0, sy + sh - 2.0), 1.0, 0.95)
			_pine(ci, Vector2(sx + sw - 28.0, sy + sh - 2.0), 1.15, 0.95)
		"mountain":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(sx, horizon + 4), Vector2(sx + sw * 0.3, horizon - 58),
				Vector2(sx + sw * 0.52, horizon + 10)]), Color("6a6055"))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(sx + sw * 0.3, horizon - 58), Vector2(sx + sw * 0.385, horizon - 34),
				Vector2(sx + sw * 0.24, horizon - 34)]), Color("e8e6e2"))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(sx + sw * 0.45, horizon + 6), Vector2(sx + sw * 0.75, horizon - 44),
				Vector2(sx + sw, horizon + 8)]), Color("7a6f61"))
			for i in 12:
				draw_ellipse(ci, Vector2(sx + 20 + rng.next() * (sw - 40),
						horizon + 24 + rng.next() * sh * 0.4),
						Vector2(5 + rng.next() * 8, 3 + rng.next() * 4),
						Color(0.27, 0.24, 0.2, 0.55))
		"water", "bridge":
			var wy := horizon + 8.0
			_grad_rect(ci, Rect2(sx, wy, sw, 38), Color("5d84b0"), Color("3c5f8a"), 6)
			for i in 8:
				var lx := sx + rng.next() * sw
				var ly := wy + 6.0 + rng.next() * 28.0
				ci.draw_line(Vector2(lx, ly),
						Vector2(minf(sx + sw, lx + 18 + rng.next() * 26), ly),
						Color(0.9, 0.94, 1.0, 0.35), 1.5)
			if terrain == "bridge":
				var deck_y := wy + 38.0
				ci.draw_rect(Rect2(sx, deck_y, sw, sy + sh - deck_y), Color("8a6f4d"))
				for i in range(1, 9):
					var py := deck_y + i * (sy + sh - deck_y) / 9.0
					ci.draw_line(Vector2(sx, py), Vector2(sx + sw, py),
							Color(0.22, 0.16, 0.09, 0.6), 2.0)
				ci.draw_rect(Rect2(sx, deck_y - 5, sw, 7), Color("6d5539"))
		"fort":
			var wall_y := horizon - 34.0
			ci.draw_rect(Rect2(sx, wall_y, sw, 46), Color("75757e"))
			for i in 9:
				ci.draw_rect(Rect2(sx + i * sw / 9.0 + 3, wall_y - 12, sw / 9.0 - 8, 12),
						Color("82828c"))
			for r in 3:
				for i in 8:
					ci.draw_rect(Rect2(sx + i * sw / 8.0 + (r % 2) * sw / 16.0,
							wall_y + 4 + r * 14, sw / 8.0, 14),
							Color(0.16, 0.16, 0.19, 0.35), false, 1.0)
			ci.draw_rect(Rect2(sx + sw * 0.47, wall_y - 30, 4, 30), Color("8c2f2f"))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(sx + sw * 0.47 + 4, wall_y - 30),
				Vector2(sx + sw * 0.47 + 30, wall_y - 24),
				Vector2(sx + sw * 0.47 + 4, wall_y - 16)]), Color("a83838"))

	# grass tufts (+ wildflowers on plains)
	if terrain == "plain" or terrain == "forest" or terrain == "mountain":
		for i in 26:
			var gx := sx + 10.0 + rng.next() * (sw - 20.0)
			var gy := horizon + 14.0 + rng.next() * sh * 0.44
			ci.draw_line(Vector2(gx, gy), Vector2(gx - 3, gy - 7),
					Color(0.13, 0.2, 0.09, 0.5), 1.5)
			ci.draw_line(Vector2(gx, gy), Vector2(gx + 2, gy - 8),
					Color(0.13, 0.2, 0.09, 0.5), 1.5)
			if terrain == "plain" and i % 4 == 0:
				ci.draw_circle(Vector2(gx + 4, gy - 5), 2.0,
						Color("d8d879") if i % 8 != 0 else Color("c9788a"))

	# edge vignette: stroked frames darkening outward
	for i in 4:
		ci.draw_rect(Rect2(sx + i * 5.0, sy + i * 5.0, sw - i * 10.0, sh - i * 10.0),
				Color(0, 0, 0, 0.16 - i * 0.04), false, 6.0)


static func _pine(ci: CanvasItem, base: Vector2, s: float, alpha: float) -> void:
	var trunk := Color(0.25, 0.19, 0.15, alpha)
	ci.draw_rect(Rect2(base.x - 3 * s, base.y - 10 * s, 6 * s, 12 * s), trunk)
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -64 * s), base + Vector2(20 * s, -26 * s),
		base + Vector2(-20 * s, -26 * s)]), Color(0.18, 0.3, 0.17, alpha))
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -50 * s), base + Vector2(25 * s, -9 * s),
		base + Vector2(-25 * s, -9 * s)]), Color(0.21, 0.34, 0.19, alpha))


# =============================================================================
# FIGHTER FIGURES — enemy in 3/4 front view (top), player from behind
# (bottom). Flat-shaded vector figures, ~90 px tall at scale 1.
# =============================================================================


static func draw_figure(ci: CanvasItem, pos: Vector2, icon: String,
		team_main: Color, team_dark: Color, front: bool, s: float) -> void:
	var xf := func(local: Vector2) -> Vector2: return pos + local * s
	draw_ellipse(ci, xf.call(Vector2(0, 34)), Vector2(30 * s, 8 * s), Color(0.04, 0.04, 0.06, 0.45))
	match icon:
		"K": _fig_knight(ci, xf, s, front, team_main, team_dark)
		"M": _fig_merc(ci, xf, s, front, team_main, team_dark)
		"C": _fig_cavalier(ci, xf, s, front, team_main, team_dark)
		"A": _fig_archer(ci, xf, s, front, team_main, team_dark)
		"W": _fig_mage(ci, xf, s, front, team_main, team_dark)
		"H": _fig_healer(ci, xf, s, front, team_main, team_dark)
		_: _fig_pegasus(ci, xf, s, front, team_main, team_dark)


static func _fig_poly(ci: CanvasItem, xf: Callable, pts: Array, color: Color) -> void:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(xf.call(p))
	ci.draw_colored_polygon(out, color)


static func _fig_rect(ci: CanvasItem, xf: Callable, x: float, y: float,
		w: float, h: float, s: float, color: Color) -> void:
	var tl: Vector2 = xf.call(Vector2(x, y))
	ci.draw_rect(Rect2(tl, Vector2(w * s, h * s)), color)


static func _head(ci: CanvasItem, xf: Callable, y: float, s: float, front: bool,
		r := 9.0) -> void:
	ci.draw_circle(xf.call(Vector2(0, y)), r * s, SKIN if front else Color("c79a6d"))
	if front:
		_fig_rect(ci, xf, -4, y - 2, 2.5, 3, s, Color("3a2c20"))
		_fig_rect(ci, xf, 1.5, y - 2, 2.5, 3, s, Color("3a2c20"))


static func _legs(ci: CanvasItem, xf: Callable, s: float,
		color := Color("3a3630")) -> void:
	_fig_rect(ci, xf, -9, 16, 7, 18, s, color)
	_fig_rect(ci, xf, 2, 16, 7, 18, s, color)
	_fig_rect(ci, xf, -10, 30, 9, 6, s, Color("26221c"))
	_fig_rect(ci, xf, 1, 30, 9, 6, s, Color("26221c"))


static func _torso(ci: CanvasItem, xf: Callable, s: float, color: Color,
		dark: Color, w := 24.0) -> void:
	_fig_poly(ci, xf, [Vector2(-w / 2, -8), Vector2(w / 2, -8),
			Vector2(w / 2 - 3, 18), Vector2(-w / 2 + 3, 18)], color)
	_fig_rect(ci, xf, -w / 2 + 3, 12, w - 6, 4, s, dark)
	_fig_poly(ci, xf, [Vector2(-w / 2, -8), Vector2(-w / 2 + 6, -8),
			Vector2(-w / 2 + 4, 18), Vector2(-w / 2 + 3, 18)], Color(0, 0, 0, 0.18))


static func _lance(ci: CanvasItem, pos: Vector2, s: float, up: bool) -> void:
	var ang := -0.45 if up else 0.45
	ci.draw_set_transform(pos + Vector2(15, -2) * s, ang, Vector2(s, s))
	ci.draw_rect(Rect2(-1.6, -34, 3.2, 56), Color("7d6748"))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(0, -42), Vector2(5, -30), Vector2(-5, -30)]), Color("c8ccd6"))
	ci.draw_set_transform(Vector2.ZERO)


static func _sword(ci: CanvasItem, pos: Vector2, s: float, up: bool) -> void:
	var ang := -0.7 if up else 0.7
	ci.draw_set_transform(pos + Vector2(16, -6) * s, ang, Vector2(s, s))
	ci.draw_rect(Rect2(-1.5, -30, 3, 30), Color("d7dbe4"))
	ci.draw_rect(Rect2(-5, -1, 10, 3), Color("8a6f35"))
	ci.draw_set_transform(Vector2.ZERO)


static func _fig_knight(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, _dark: Color) -> void:
	_legs(ci, xf, s, METAL_DARK)
	_torso(ci, xf, s, METAL, METAL_DARK, 30)
	_fig_poly(ci, xf, [Vector2(-8, -6), Vector2(8, -6), Vector2(6, 14),
			Vector2(-6, 14)], main)
	ci.draw_circle(xf.call(Vector2(-13, -6)), 9 * s, METAL_DARK)
	ci.draw_circle(xf.call(Vector2(13, -6)), 9 * s, METAL_DARK)
	_fig_poly(ci, xf, [Vector2(-26, -12), Vector2(-12, -12), Vector2(-12, 16),
			Vector2(-19, 22), Vector2(-26, 16)], METAL)
	_fig_poly(ci, xf, [Vector2(-24, -10), Vector2(-14, -10), Vector2(-14, 15),
			Vector2(-19, 19), Vector2(-24, 15)], main)
	ci.draw_circle(xf.call(Vector2(0, -17)), 10 * s, METAL)
	if front:
		_fig_rect(ci, xf, -7, -19, 14, 4, s, Color("20242e"))
	_fig_poly(ci, xf, [Vector2(0, -30), Vector2(4, -22), Vector2(-4, -22)], main)
	_lance(ci, xf.call(Vector2.ZERO), s, not front)


static func _fig_merc(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, dark: Color) -> void:
	_legs(ci, xf, s)
	_torso(ci, xf, s, Color("7a5b3c"), Color("5c452f"))
	_fig_poly(ci, xf, [Vector2(-12, -8), Vector2(12, -8), Vector2(10, 2),
			Vector2(-10, 2)], main)
	_head(ci, xf, -16, s, front)
	draw_ellipse(ci, xf.call(Vector2(0, -20)), Vector2(9.5 * s, 5.5 * s), Color("6e4a2c"))
	_fig_rect(ci, xf, -9, -14, 18, 3, s, dark)
	_sword(ci, xf.call(Vector2.ZERO), s, not front)


static func _fig_cavalier(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, dark: Color) -> void:
	draw_ellipse(ci, xf.call(Vector2(0, 40)), Vector2(34 * s, 7 * s), Color(0.04, 0.04, 0.06, 0.4))
	draw_ellipse(ci, xf.call(Vector2(0, 16)), Vector2(26 * s, 12 * s), Color("6b4f35"))
	_fig_poly(ci, xf, [Vector2(20, 8), Vector2(34, -2), Vector2(30, 12)], Color("6b4f35"))
	ci.draw_circle(xf.call(Vector2(33, -3)), 6 * s, Color("5d452f"))
	for lx: float in [-16.0, -6.0, 8.0, 18.0]:
		_fig_rect(ci, xf, lx, 24, 5, 14, s, Color("4a3826"))
	_fig_poly(ci, xf, [Vector2(-24, 10), Vector2(-34, 20), Vector2(-28, 8)], Color("3f3122"))
	var rider := func(local: Vector2) -> Vector2:
		return xf.call(local + Vector2(0, -12))
	_torso(ci, rider, s, main, dark, 20)
	ci.draw_circle(rider.call(Vector2(-11, -6)), 6 * s, METAL)
	ci.draw_circle(rider.call(Vector2(11, -6)), 6 * s, METAL)
	_head(ci, rider, -14, s, front)
	ci.draw_circle(rider.call(Vector2(0, -15)), 8.5 * s, METAL)
	_lance(ci, rider.call(Vector2.ZERO), s, not front)


static func _fig_archer(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, dark: Color) -> void:
	_legs(ci, xf, s)
	_torso(ci, xf, s, Color("5f7a4a"), Color("48603a"))
	_fig_poly(ci, xf, [Vector2(-12, -8), Vector2(12, -8), Vector2(9, 0),
			Vector2(-9, 0)], main)
	_head(ci, xf, -16, s, front)
	_fig_poly(ci, xf, [Vector2(-10, -14), Vector2(0, -30), Vector2(10, -14),
			Vector2(0, -10)], dark)
	var bow_c: Vector2 = xf.call(Vector2(18, -6))
	ci.draw_arc(bow_c, 16 * s, -PI * 0.42, PI * 0.42, 16, Color("8a6f45"), 3.0)
	ci.draw_line(bow_c + Vector2(cos(-PI * 0.42), sin(-PI * 0.42)) * 16 * s,
			bow_c + Vector2(cos(PI * 0.42), sin(PI * 0.42)) * 16 * s,
			Color("d8d8d8"), 1.0)


static func _fig_mage(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, dark: Color) -> void:
	_fig_poly(ci, xf, [Vector2(-14, 34), Vector2(14, 34), Vector2(8, -6),
			Vector2(-8, -6)], Color("4a3d63"))
	_fig_poly(ci, xf, [Vector2(-14, 34), Vector2(-6, 34), Vector2(-4, 0),
			Vector2(-8, -4)], Color(0, 0, 0, 0.2))
	_fig_rect(ci, xf, -8, 2, 16, 4, s, main)
	_head(ci, xf, -12, s, front)
	_fig_poly(ci, xf, [Vector2(-13, -14), Vector2(13, -14), Vector2(2, -36)],
			Color("3a3050"))
	_fig_rect(ci, xf, -13, -15, 26, 3, s, dark)
	_fig_rect(ci, xf, 14, -8, 12, 9, s, Color("7a2f2f"))
	_fig_rect(ci, xf, 15, -7, 10, 7, s, Color("e8e2d0"))
	ci.draw_circle(xf.call(Vector2(20, -16)), 7 * s, Color(0.49, 0.91, 0.63, 0.25))
	ci.draw_circle(xf.call(Vector2(20, -16)), 3.5 * s, Color("7de8a0"))


static func _fig_healer(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, _dark: Color) -> void:
	_fig_poly(ci, xf, [Vector2(-13, 34), Vector2(13, 34), Vector2(7, -6),
			Vector2(-7, -6)], Color("ded8ce"))
	_fig_rect(ci, xf, -7, 4, 14, 3, s, main)
	_head(ci, xf, -12, s, front)
	_fig_poly(ci, xf, [Vector2(-10, -14), Vector2(10, -14), Vector2(0, -26)],
			Color("c9c2b4"))
	_fig_rect(ci, xf, 14, -28, 3, 58, s, Color("8a7350"))
	ci.draw_circle(xf.call(Vector2(15.5, -30)), 9 * s, Color(0.55, 0.85, 0.94, 0.25))
	ci.draw_circle(xf.call(Vector2(15.5, -30)), 5 * s, Color("8dd8f0"))


static func _fig_pegasus(ci: CanvasItem, xf: Callable, s: float, front: bool,
		main: Color, dark: Color) -> void:
	for dir: float in [-1.0, 1.0]:
		_fig_poly(ci, xf, [Vector2(dir * 8, -2), Vector2(dir * 42, -26),
				Vector2(dir * 34, -6), Vector2(dir * 14, 8)], Color("e6e2da"))
		_fig_poly(ci, xf, [Vector2(dir * 10, 0), Vector2(dir * 36, -18),
				Vector2(dir * 30, -2), Vector2(dir * 14, 8)], Color("d1ccc0"))
	draw_ellipse(ci, xf.call(Vector2(0, 40)), Vector2(30 * s, 6 * s), Color(0.04, 0.04, 0.06, 0.35))
	draw_ellipse(ci, xf.call(Vector2(0, 16)), Vector2(22 * s, 11 * s), Color("d8d4cc"))
	for lx: float in [-14.0, -4.0, 7.0, 15.0]:
		_fig_rect(ci, xf, lx, 24, 4.5, 13, s, Color("c4bfb4"))
	var rider := func(local: Vector2) -> Vector2:
		return xf.call(local + Vector2(0, -10))
	_torso(ci, rider, s, main, dark, 18)
	_head(ci, rider, -13, s, front)
	ci.draw_circle(rider.call(Vector2(0, -14)), 8 * s, METAL)
	_lance(ci, rider.call(Vector2.ZERO), s, not front)


# =============================================================================
# MAP TILES — textured terrain for the tactical board.
# =============================================================================


static func draw_map_tile(ci: CanvasItem, cell: Vector2i, t: float, key: String) -> void:
	var rng := Lcg.new(cell.y * 31 + cell.x)
	var px := cell.x * t
	var py := cell.y * t
	if key == "water":
		_grad_rect(ci, Rect2(px, py, t, t), Color("4f7fae"), Color("426f9c"), 4)
		for i in 2:
			var wy := py + 12.0 + i * 18.0 + rng.next() * 6.0
			var wx := px + 6.0 + rng.next() * 10.0
			var pts := PackedVector2Array()
			for j in 13:
				pts.append(Vector2(wx + j * 2.5, wy - sin(j * 0.52) * 2.5))
			ci.draw_polyline(pts, Color(1, 1, 1, 0.3), 1.5)
		return
	ci.draw_rect(Rect2(px, py, t, t),
			Color("7a9e5f") if (cell.x + cell.y) % 2 == 0 else Color("74985a"))
	for i in 7:
		var c := Color(0.18, 0.28, 0.13, 0.30) if rng.next() > 0.5 \
				else Color(0.59, 0.71, 0.43, 0.35)
		ci.draw_rect(Rect2(px + 3 + rng.next() * (t - 6), py + 3 + rng.next() * (t - 6),
				2, 2), c)

	match key:
		"forest":
			draw_ellipse(ci, Vector2(px + t / 2 + 3, py + t - 8), Vector2(14, 4),
					Color(0.08, 0.12, 0.05, 0.35))
			ci.draw_rect(Rect2(px + t / 2 - 2, py + t - 16, 4, 8), Color("4a3626"))
			ci.draw_circle(Vector2(px + t / 2 - 6, py + t / 2), 8, Color("3d6132"))
			ci.draw_circle(Vector2(px + t / 2 + 6, py + t / 2 + 2), 7, Color("35572c"))
			ci.draw_circle(Vector2(px + t / 2, py + t / 2 - 7), 8, Color("457038"))
			ci.draw_circle(Vector2(px + t / 2 - 3, py + t / 2 - 4), 3,
					Color(0.75, 0.86, 0.59, 0.4))
		"mountain":
			draw_ellipse(ci, Vector2(px + t / 2, py + t - 7), Vector2(16, 4),
					Color(0.12, 0.09, 0.07, 0.35))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(px + 6, py + t - 8), Vector2(px + t / 2 - 2, py + 8),
				Vector2(px + t - 10, py + t - 8)]), Color("7d6f5c"))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(px + t / 2 - 2, py + 8), Vector2(px + t - 10, py + t - 8),
				Vector2(px + t / 2 + 6, py + t - 8)]), Color(0, 0, 0, 0.22))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(px + t / 2 - 2, py + 8), Vector2(px + t / 2 + 5, py + 20),
				Vector2(px + t / 2 - 9, py + 20)]), Color("ece9e4"))
		"bridge":
			ci.draw_rect(Rect2(px, py, t, t), Color("8a6f4d"))
			for i in range(1, 4):
				ci.draw_line(Vector2(px, py + t * i / 4.0), Vector2(px + t, py + t * i / 4.0),
						Color(0.22, 0.16, 0.09, 0.55), 2.0)
			ci.draw_rect(Rect2(px, py, t, 4), Color("5f4a30"))
			ci.draw_rect(Rect2(px, py + t - 4, t, 4), Color("5f4a30"))
		"fort":
			ci.draw_rect(Rect2(px + 5, py + 10, t - 10, t - 14), Color("80808a"))
			for i in 3:
				ci.draw_rect(Rect2(px + 6 + i * (t - 12) / 3.0, py + 4,
						(t - 12) / 3.0 - 3, 8), Color("8d8d97"))
			ci.draw_rect(Rect2(px + 5, py + 10, t - 10, t - 14),
					Color(0.16, 0.16, 0.19, 0.4), false, 1.0)
			ci.draw_line(Vector2(px + 5, py + t / 2 + 2), Vector2(px + t - 5, py + t / 2 + 2),
					Color(0.16, 0.16, 0.19, 0.4), 1.0)
			ci.draw_rect(Rect2(px + t / 2 - 5, py + t - 16, 10, 12), Color("3c3c46"))
