class_name UnitSprites
## The per-type centre emblem and regimental flag drawn on a Unit's chrome layer,
## extracted from Unit.gd. Each function draws straight onto the passed-in unit (a
## CanvasItem), so it must be called from within that unit's `_draw()` — Unit's `_draw`
## dispatches by type to one of the four sprites, then the flag. Pure presentation:
## shapes are a function of the unit's type/colours only, nothing writes back into the
## simulation. Sizes key off `Unit.RADIUS` / `Unit.FLAG_*`.


## Infantry: kite (heater) shield with a cross motif and sword pommel.
static func infantry(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var R := Unit.RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var pts := PackedVector2Array([
		Vector2(0,          -R),
		Vector2( R * 0.82, -R * 0.30),
		Vector2( R * 0.90,  R * 0.42),
		Vector2(0,           R),
		Vector2(-R * 0.90,  R * 0.42),
		Vector2(-R * 0.82, -R * 0.30),
	])
	u.draw_colored_polygon(pts, body)
	u.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3],
			pts[4], pts[5], pts[0]]), dark, 2.0)
	# Cross on shield face.
	u.draw_line(Vector2(0,  -R + 5.0), Vector2(0,  R * 0.90), lite, 2.0)
	u.draw_line(Vector2(-R * 0.72, R * 0.05), Vector2(R * 0.72, R * 0.05), lite, 2.0)
	# Sword pommel / crossguard at the top of the shield.
	u.draw_line(Vector2(-5.0, -R + 8.0), Vector2(5.0, -R + 8.0), metal, 2.5)
	u.draw_line(Vector2(0, -R + 2.0), Vector2(0, -R + 9.0), metal, 2.0)


## Archers: a light skirmisher body with a drawn bow + nocked arrow forward.
static func archer(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var R := Unit.RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var wood := Color(0.62, 0.48, 0.30, body.a)
	# Light round body — archers are unarmoured, so a smaller token than a shield.
	u.draw_circle(Vector2.ZERO, R * 0.60, body)
	u.draw_arc(Vector2.ZERO, R * 0.60, 0, TAU, 20, dark, 1.5)
	# Bow: an arc bulging forward (up = forward in this rotated local space), with
	# a bowstring across its tips.
	var bow_r: float = R * 1.05
	var a0: float = -PI * 0.5 - 0.7
	var a1: float = -PI * 0.5 + 0.7
	u.draw_arc(Vector2.ZERO, bow_r, a0, a1, 16, wood, 2.5)
	var tip0: Vector2 = Vector2.from_angle(a0) * bow_r
	var tip1: Vector2 = Vector2.from_angle(a1) * bow_r
	u.draw_line(tip0, tip1, lite, 1.0)
	# Nocked arrow at the string's midpoint, pointing forward with a metal head.
	var nock: Vector2 = (tip0 + tip1) * 0.5
	u.draw_line(nock, Vector2(0, -(bow_r + 9.0)), metal, 1.5)
	u.draw_colored_polygon(PackedVector2Array([
		Vector2(0, -(bow_r + 13.0)),
		Vector2(3.0, -(bow_r + 5.0)),
		Vector2(-3.0, -(bow_r + 5.0)),
	]), metal)


## Spearmen: round hoplon shield with a forward-pointing spear.
static func spear(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var R := Unit.RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var wood := Color(0.62, 0.48, 0.30, body.a)
	# Spear shaft (forward = up in rotated local space).
	var shaft_y: float = -(R + 15.0)
	u.draw_line(Vector2(0, -R * 0.05), Vector2(0, shaft_y), wood, 3.0)
	# Spear blade.
	var blade := PackedVector2Array([
		Vector2(0,    shaft_y - 9.0),
		Vector2( 3.5, shaft_y),
		Vector2(-3.5, shaft_y),
	])
	u.draw_colored_polygon(blade, metal)
	u.draw_polyline(PackedVector2Array([blade[0], blade[1], blade[2], blade[0]]), dark, 1.0)
	# Hoplon (round shield).
	u.draw_circle(Vector2.ZERO, R * 0.88, body)
	u.draw_arc(Vector2.ZERO, R * 0.88, 0, TAU, 24, dark, 2.0)
	# Shield boss.
	u.draw_circle(Vector2.ZERO, R * 0.26, lite)
	u.draw_arc(Vector2.ZERO, R * 0.26, 0, TAU, 12, dark, 1.5)
	# Inner ring detail.
	u.draw_arc(Vector2.ZERO, R * 0.60, 0, TAU, 20,
			Color(dark.r, dark.g, dark.b, dark.a * 0.6), 1.0)


## Cavalry: horse body (two overlapping ovals) with rider and lance.
static func cavalry(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var R := Unit.RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	# Horse body: forequarters + hindquarters bridged by a quad.
	u.draw_circle(Vector2(0, -R * 0.30), R * 0.62, body)
	u.draw_circle(Vector2(0,  R * 0.28), R * 0.68, body)
	u.draw_colored_polygon(PackedVector2Array([
		Vector2(-R * 0.60, -R * 0.30),
		Vector2(-R * 0.66,  R * 0.28),
		Vector2( R * 0.66,  R * 0.28),
		Vector2( R * 0.60, -R * 0.30),
	]), body)
	u.draw_arc(Vector2(0, -R * 0.30), R * 0.62, 0, TAU, 16, dark, 1.5)
	u.draw_arc(Vector2(0,  R * 0.28), R * 0.68, 0, TAU, 16, dark, 1.5)
	# Horse head / neck offset forward-right.
	var head := Vector2(R * 0.20, -R * 0.88)
	u.draw_circle(head, R * 0.28, lite)
	u.draw_arc(head, R * 0.28, 0, TAU, 12, dark, 1.5)
	# Four legs trailing behind.
	u.draw_line(Vector2(-R * 0.35, R * 0.60), Vector2(-R * 0.48, R + 4.0), dark, 2.5)
	u.draw_line(Vector2(-R * 0.12, R * 0.60), Vector2(-R * 0.18, R + 5.0), dark, 2.5)
	u.draw_line(Vector2( R * 0.12, R * 0.60), Vector2( R * 0.18, R + 5.0), dark, 2.5)
	u.draw_line(Vector2( R * 0.35, R * 0.60), Vector2( R * 0.48, R + 4.0), dark, 2.5)
	# Rider torso.
	u.draw_circle(Vector2(0, -R * 0.18), R * 0.42, lite)
	u.draw_arc(Vector2(0, -R * 0.18), R * 0.42, 0, TAU, 14, dark, 1.5)
	# Lance pointing forward-right with a triangular blade tip.
	var lance_tip := Vector2(R * 0.65, -R * 0.78)
	u.draw_line(Vector2(R * 0.15, -R * 0.18), lance_tip, metal, 2.5)
	var lance_dir := Vector2(0.50, -0.60).normalized()
	var lance_perp := Vector2(-lance_dir.y, lance_dir.x)
	var tip_blade := PackedVector2Array([
		lance_tip + lance_dir * 7.0,
		lance_tip + lance_perp * 3.0,
		lance_tip - lance_perp * 3.0,
	])
	u.draw_colored_polygon(tip_blade, metal)
	u.draw_polyline(PackedVector2Array([tip_blade[0], tip_blade[1], tip_blade[2], tip_blade[0]]),
			dark, 1.0)


## The local-space bounding box of a unit's raised standard (pole + flag), in the same
## unrotated screen frame `flag()` draws in (origin = the unit centre). Single-sources the
## standard's geometry so a hit test (clicking the flag to select the unit) stays in step
## with what's drawn. `extent` is the unit's render block half-size.
static func standard_bounds(extent: float) -> Rect2:
	# Pole foot sits FLAG_POLE_BASE_GAP above the block; the pole rises FLAG_POLE_HEIGHT to
	# the flag attachment. Width spans the flag rectangle (the pole sits on its left edge).
	# The flag hangs from the pole tip and FLAG_HEIGHT (8) < FLAG_POLE_HEIGHT (18), so it's
	# fully nested in the pole span — the height needn't add FLAG_HEIGHT. (If the flag were
	# ever re-anchored below the pole base, this bound would need to grow to cover it.)
	var top: float = -extent - Unit.FLAG_POLE_BASE_GAP - Unit.FLAG_POLE_HEIGHT
	return Rect2(0.0, top, Unit.FLAG_WIDTH, Unit.FLAG_POLE_HEIGHT)


## A regimental standard: a pole rising above the stat bars with a coloured flag bearing a
## per-type emblem. Drawn in screen space (called after draw_set_transform reset) so it
## always stands upright regardless of the unit's facing direction. Dead units skip it.
static func flag(u: Unit, body_c: Color, alpha: float, extent: float) -> void:
	if u.state == Unit.State.DEAD:
		return
	# Pole rises from just above the soldier-count text (which sits ~14 px above bar top).
	var pole_base := Vector2(0.0, -extent - Unit.FLAG_POLE_BASE_GAP)
	var pole_top  := Vector2(0.0, pole_base.y - Unit.FLAG_POLE_HEIGHT)
	u.draw_line(pole_base, pole_top, Color(0.85, 0.85, 0.85, alpha), 1.5)
	# Flag rectangle hangs below the pole tip (positive-Y in screen space = downward).
	var fx: float = pole_top.x
	var fy: float = pole_top.y
	u.draw_rect(Rect2(fx, fy, Unit.FLAG_WIDTH, Unit.FLAG_HEIGHT), body_c)
	u.draw_rect(Rect2(fx, fy, Unit.FLAG_WIDTH, Unit.FLAG_HEIGHT),
			Color(1.0, 1.0, 1.0, alpha * 0.5), false, 1.0)
	# Type emblem centred on the flag: spear = vertical, bow = arc, lance = diagonal, cross = infantry.
	var fc := Vector2(fx + Unit.FLAG_WIDTH * 0.5, fy + Unit.FLAG_HEIGHT * 0.5)
	var sym_c := Color(1.0, 1.0, 1.0, alpha)
	if u.is_cavalry:
		u.draw_line(fc + Vector2(-3.0, 2.5), fc + Vector2(3.0, -2.5), sym_c, 1.5)
	elif u.anti_cavalry:
		u.draw_line(fc + Vector2(0.0, 3.0), fc + Vector2(0.0, -3.0), sym_c, 1.5)
	elif u.is_ranged:
		u.draw_arc(fc, 2.5, -PI * 0.55, PI * 0.55, 6, sym_c, 1.5)
	else:
		u.draw_line(fc + Vector2(-2.5, 0.0), fc + Vector2(2.5, 0.0), sym_c, 1.5)
		u.draw_line(fc + Vector2(0.0, -2.5), fc + Vector2(0.0, 2.5), sym_c, 1.5)
