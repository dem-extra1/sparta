class_name UnitShields
## Cosmetic shield overlay for the shielded close-order stances (shield wall & testudo),
## drawn on a Unit's chrome layer. Purely presentational: it reads the unit's formation
## block shape and formation_mode and draws locked shields on top -- nothing writes back
## into the simulation. Called from within the unit's _draw(), in the facing-rotated local
## frame (forward = up / -Y, files span X), the same frame the centre emblem uses.
##
## The geometry (block half-width along the file axis, block depth along ranks, and the
## per-shield rectangle layout) is factored into pure static helpers so it is directly
## unit-testable and independent of the unit's world position/facing.


## Half-width of the formation block along its FILE axis (local +X), in world units:
## how far the outermost file sits from the centre line. A grid of `files` files spans
## (files-1) gaps of `spacing`, so the half-width is (files-1)/2 * spacing. Pure.
static func block_half_width(files: int, spacing: float) -> float:
	return float(maxi(1, files) - 1) * 0.5 * spacing


## Half-depth of the formation block along its RANK axis (local Y), in world units: how
## far the front (and rear) rank sits from the centre along facing. `ranks` rows span
## (ranks-1) gaps of `spacing`, so the half-depth is (ranks-1)/2 * spacing. Pure.
static func block_half_depth(ranks: int, spacing: float) -> float:
	return float(maxi(1, ranks) - 1) * 0.5 * spacing


## The locked shield-wall line: a row of `count` edge-to-edge shield rectangles spanning
## the block's FRONT face, centred on the file axis and sitting just ahead of the front
## rank. Each rect is returned as its own PackedVector2Array of four local-space corners
## (front-left, front-right, back-right, back-left), ready to hand straight to
## draw_colored_polygon. The wall spans the full front width (2 * half_width, plus a
## `pad` overhang past the outermost marks on each side) divided into `count` shields;
## `front_y` is the local Y of the shields' inner (rear) edge -- pass the front rank's Y
## minus a mark radius so the wall sits just in front of the leading marks. Pure and
## deterministic: a function of the shape only, so it is unit-testable.
static func shield_wall_shields(count: int, half_width: float, pad: float,
		front_y: float, thickness: float) -> Array:
	var out: Array = []
	count = maxi(1, count)
	var span: float = 2.0 * (half_width + pad)
	var shield_w: float = span / float(count)
	var left: float = -(half_width + pad)
	var back_y: float = front_y            # inner (rear) edge, toward the block
	var lead_y: float = front_y - thickness  # outer (leading) edge, ahead of the block
	for i in range(count):
		var x0: float = left + float(i) * shield_w
		var x1: float = x0 + shield_w
		# A small inset between adjacent shields so the locked line still reads as
		# discrete overlapping shields rather than one solid bar.
		var inset: float = shield_w * 0.06
		out.push_back(PackedVector2Array([
			Vector2(x0 + inset, lead_y),
			Vector2(x1 - inset, lead_y),
			Vector2(x1 - inset, back_y),
			Vector2(x0 + inset, back_y),
		]))
	return out


## The testudo overhead-cover grid: shield rectangles tiled over the whole block (the
## "roof" of the turtle). Returns one PackedVector2Array of four local corners per shield.
## The roof covers a rectangle of half-width (`half_width` + `pad`) by half-depth
## (`half_depth` + `pad`), tiled `cols` x `rows`. `cols`/`rows` are clamped to at least 1.
## A small inset between tiles keeps the individual shields legible. Pure and deterministic.
static func testudo_shields(cols: int, rows: int, half_width: float, half_depth: float,
		pad: float) -> Array:
	var out: Array = []
	cols = maxi(1, cols)
	rows = maxi(1, rows)
	var span_x: float = 2.0 * (half_width + pad)
	var span_y: float = 2.0 * (half_depth + pad)
	var tile_w: float = span_x / float(cols)
	var tile_h: float = span_y / float(rows)
	var inset_x: float = tile_w * 0.08
	var inset_y: float = tile_h * 0.08
	var x_left: float = -(half_width + pad)
	var y_top: float = -(half_depth + pad)
	for r in range(rows):
		for c in range(cols):
			var x0: float = x_left + float(c) * tile_w
			var y0: float = y_top + float(r) * tile_h
			out.push_back(PackedVector2Array([
				Vector2(x0 + inset_x, y0 + inset_y),
				Vector2(x0 + tile_w - inset_x, y0 + inset_y),
				Vector2(x0 + tile_w - inset_x, y0 + tile_h - inset_y),
				Vector2(x0 + inset_x, y0 + tile_h - inset_y),
			]))
	return out


## Draw the shield overlay for `u`'s current stance onto its chrome layer. No-op for any
## stance other than SHIELD_WALL / TESTUDO. Must be called from within `u._draw()`, with
## the draw transform ALREADY set to the facing-rotated local frame (forward = -Y), the
## same frame the centre emblem is drawn in; the caller restores the transform afterward.
## `body`/`dark`/`lite` are the unit's team-tinted chrome colours (so the shields read as
## this team's), matching the emblem's palette.
static func draw(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	if u.formation_mode == Unit.FORMATION_SHIELD_WALL:
		_draw_shield_wall(u, body, dark, lite)
	elif u.formation_mode == Unit.FORMATION_TESTUDO:
		_draw_testudo(u, body, dark, lite)


## Shield-wall: a locked edge-to-edge shield line along the block's front face.
static func _draw_shield_wall(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var files: int = UnitFormation.frontage(u)
	var spacing: float = Unit.FORMATION_SPACING * u.spacing_scale
	var ranks: int = UnitFormation.ranks_for(u.soldiers, files)
	var mark_r: float = u.soldier_body_radius()
	var half_width: float = block_half_width(files, spacing)
	var half_depth: float = block_half_depth(ranks, spacing)
	# One drawn shield per pair of files (a soldier locks his shield with his neighbour),
	# floored at 3 so a narrow column still reads as a wall, capped so a very wide line
	# doesn't shatter into slivers.
	var count: int = clampi(int(round(float(files) * 0.5)), 3, 12)
	var thickness: float = maxf(mark_r * 1.6, 7.0)
	# Sit the wall just ahead of the leading marks: front rank is at -half_depth.
	var front_y: float = -half_depth - mark_r * 0.4
	var shields: Array = shield_wall_shields(count, half_width, mark_r, front_y, thickness)
	for poly in shields:
		u.draw_colored_polygon(poly, body)
		u.draw_polyline(_closed(poly), dark, 1.5)
		# A boss highlight down the shield's outer face so the line reads as raised shields.
		var mid_x: float = (poly[0].x + poly[1].x) * 0.5
		u.draw_line(Vector2(mid_x, poly[0].y + 1.0), Vector2(mid_x, poly[3].y - 1.0), lite, 1.5)


## Testudo: an overhead shield roof tiled over the whole block (the turtle).
static func _draw_testudo(u: Unit, body: Color, dark: Color, lite: Color) -> void:
	var files: int = UnitFormation.frontage(u)
	var spacing: float = Unit.FORMATION_SPACING * u.spacing_scale
	var ranks: int = UnitFormation.ranks_for(u.soldiers, files)
	var mark_r: float = u.soldier_body_radius()
	var half_width: float = block_half_width(files, spacing)
	var half_depth: float = block_half_depth(ranks, spacing)
	# Tile the roof roughly one shield per two files / two ranks, floored so even a small
	# block shows a legible grid and capped so a big block doesn't dissolve into a mesh.
	var cols: int = clampi(int(round(float(files) * 0.5)), 2, 8)
	var rows: int = clampi(int(round(float(ranks) * 0.5)), 2, 8)
	var shields: Array = testudo_shields(cols, rows, half_width, half_depth, mark_r)
	# Semi-transparent so the individual soldiers/marks beneath still read through the roof.
	var roof := Color(body.r, body.g, body.b, body.a * 0.8)
	var edge := dark
	for poly in shields:
		u.draw_colored_polygon(poly, roof)
		u.draw_polyline(_closed(poly), edge, 1.0)
		# A short boss glint on each roof shield for the layered-scutes look.
		var cx: float = (poly[0].x + poly[2].x) * 0.5
		var cy: float = (poly[0].y + poly[2].y) * 0.5
		u.draw_line(Vector2(cx, cy - 1.5), Vector2(cx, cy + 1.5),
				Color(lite.r, lite.g, lite.b, lite.a * 0.7), 1.0)


## Close a polygon ring (append the first point) for draw_polyline outlining.
static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(poly)
	out.push_back(poly[0])
	return out
