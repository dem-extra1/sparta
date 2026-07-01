extends GutTest
## Pure geometry of the shielded-stance overlay (UnitShields): the block half-width /
## half-depth, the locked shield-wall line along the front face, and the tiled testudo
## roof. All are pure functions of the block shape, so they're checked directly without
## a live unit or a render pass. Purely cosmetic geometry -- no sim/combat is exercised.


func test_block_half_width_spans_the_file_gaps() -> void:
	# f files span (f-1) gaps of `spacing`; half-width is half that span.
	assert_almost_eq(UnitShields.block_half_width(5, 9.0), 18.0, 0.001,
		"5 files at 9px: (5-1)/2 * 9 = 18")
	# A single file has zero width; clamped so it never goes negative.
	assert_eq(UnitShields.block_half_width(1, 9.0), 0.0, "one file: no width")
	assert_eq(UnitShields.block_half_width(0, 9.0), 0.0, "clamped to >= 1 file")


func test_block_half_depth_spans_the_rank_gaps() -> void:
	assert_almost_eq(UnitShields.block_half_depth(4, 9.0), 13.5, 0.001,
		"4 ranks at 9px: (4-1)/2 * 9 = 13.5")
	assert_eq(UnitShields.block_half_depth(1, 9.0), 0.0, "one rank: no depth")


func test_shield_wall_shields_tile_the_front_span_without_gaps() -> void:
	var count: int = 4
	var half_width: float = 20.0
	var pad: float = 5.0
	var shields: Array = UnitShields.shield_wall_shields(count, half_width, pad, -30.0, 8.0)
	assert_eq(shields.size(), count, "one polygon per shield")
	# The wall spans 2*(half_width+pad) = 50, centred: leftmost left edge at -25,
	# rightmost right edge at +25 (before the tiny per-shield inset).
	var span: float = 2.0 * (half_width + pad)
	var first: PackedVector2Array = shields[0]
	var last: PackedVector2Array = shields[count - 1]
	# first shield's leading-left corner x ~ -span/2 (plus inset); last's leading-right ~ +span/2.
	assert_lt(first[0].x, -span * 0.5 + 2.0, "wall starts at the left edge")
	assert_gt(last[1].x, span * 0.5 - 2.0, "wall ends at the right edge")
	# Each shield is a 4-corner quad, its leading (front) edge ahead of its rear edge.
	for poly in shields:
		assert_eq(poly.size(), 4, "each shield is a quad")
		assert_lt(poly[0].y, poly[3].y, "leading edge sits ahead of (more negative Y than) the rear")


func test_shield_wall_sits_ahead_of_the_front_rank() -> void:
	# front_y is the rear (inner) edge; the leading edge is thickness further forward (-Y).
	var front_y: float = -30.0
	var thickness: float = 8.0
	var shields: Array = UnitShields.shield_wall_shields(3, 15.0, 4.0, front_y, thickness)
	var poly: PackedVector2Array = shields[0]
	assert_almost_eq(poly[3].y, front_y, 0.001, "rear edge at front_y")
	assert_almost_eq(poly[0].y, front_y - thickness, 0.001, "leading edge one thickness ahead")


func test_testudo_shields_tile_the_whole_block() -> void:
	var cols: int = 3
	var rows: int = 2
	var shields: Array = UnitShields.testudo_shields(cols, rows, 20.0, 15.0, 4.0)
	assert_eq(shields.size(), cols * rows, "cols*rows roof tiles")
	# The roof covers 2*(half+pad) in each axis, centred on the origin.
	var span_x: float = 2.0 * (20.0 + 4.0)
	var span_y: float = 2.0 * (15.0 + 4.0)
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for poly in shields:
		for p in poly:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
	# Within the per-tile inset tolerance, the roof spans the full block, centred.
	assert_almost_eq(min_x, -span_x * 0.5, span_x * 0.1, "roof reaches the left edge")
	assert_almost_eq(max_x, span_x * 0.5, span_x * 0.1, "roof reaches the right edge")
	assert_almost_eq(min_y, -span_y * 0.5, span_y * 0.1, "roof reaches the front edge")
	assert_almost_eq(max_y, span_y * 0.5, span_y * 0.1, "roof reaches the rear edge")


func test_shield_counts_clamp_to_at_least_one() -> void:
	assert_eq(UnitShields.shield_wall_shields(0, 10.0, 2.0, -10.0, 5.0).size(), 1,
		"a zero count still yields one shield")
	assert_eq(UnitShields.testudo_shields(0, 0, 10.0, 10.0, 2.0).size(), 1,
		"zero cols/rows still yields one tile")
