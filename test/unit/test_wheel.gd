extends GutTest
## Wheel (circumductio, hinge pivot): one flank file stays FIXED while the rest of the block
## swings 90° about it, reorienting the whole line while preserving internal order. Distinct
## from a centre pivot (a move order) and the quarter-turn (every man turns in place, block does
## not move). These pin the pure hinge geometry and the bare-unit swing: the pivot flank holds,
## the far end sweeps, and facing ends 90° from the start. The full-scene, no-surge companion is
## test_wheel_battle.gd.


func _make_unit(uid: int = 1, max_soldiers: int = 40) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## Run the wheel to completion on a bare unit: drive _think (advances the maneuver) and the body
## layer each tick until facing settles or a tick cap is hit. Returns the tick count used.
func _run_wheel(u: Unit, dir: int, max_ticks: int = 200) -> int:
	u.seed_sim_soldiers()
	u.wheel(dir)
	var delta := 1.0 / 60.0
	var ticks := 0
	while u._wheel_target != Vector2.ZERO and ticks < max_ticks:
		u._physics_process(delta)
		u.step_sim_soldiers(delta)
		ticks += 1
	return ticks


func test_pivot_is_the_standing_flank_front_corner() -> void:
	var u := _make_unit(1, 40)
	# Facing DOWN => file axis = facing.rotated(+90°) = LEFT. The right-wheel (dir=+1) hinge sits
	# at +half_width along that axis, offset forward (down) by the block's front depth.
	var files: int = UnitFormation.frontage(u)
	var spacing: float = Unit.FORMATION_SPACING * u.spacing_scale
	var half_width: float = float(files - 1) * 0.5 * spacing
	var ranks: int = int(ceil(float(u.soldiers) / float(files)))
	var front_depth: float = float(ranks - 1) * 0.5 * spacing
	var axis: Vector2 = u.facing.rotated(PI * 0.5)
	var expected: Vector2 = u.position + axis * half_width + u.facing * front_depth
	var pivot: Vector2 = u._wheel_pivot_point(1)
	assert_almost_eq(pivot.x, expected.x, 0.001, "right-wheel hinge x = right flank front corner")
	assert_almost_eq(pivot.y, expected.y, 0.001, "right-wheel hinge y = right flank front corner")


func test_left_and_right_pivots_are_on_opposite_flanks() -> void:
	var u := _make_unit(1, 40)
	var left: Vector2 = u._wheel_pivot_point(-1)
	var right: Vector2 = u._wheel_pivot_point(1)
	# The two hinges straddle the centre along the file axis: their midpoint is the block's own
	# front centre, and they are mirror images across it.
	var mid: Vector2 = (left + right) * 0.5
	var axis: Vector2 = u.facing.rotated(PI * 0.5)
	var files: int = UnitFormation.frontage(u)
	var ranks: int = int(ceil(float(u.soldiers) / float(files)))
	var front_depth: float = float(ranks - 1) * 0.5 * Unit.FORMATION_SPACING * u.spacing_scale
	var front_centre: Vector2 = u.position + u.facing * front_depth
	assert_almost_eq(mid.x, front_centre.x, 0.001, "hinges straddle the front centre (x)")
	assert_almost_eq(mid.y, front_centre.y, 0.001, "hinges straddle the front centre (y)")
	# And each lies purely along the file axis from that centre (no cross-axis drift).
	var off_r: Vector2 = right - front_centre
	assert_gt(off_r.dot(axis), 1.0, "right hinge is toward +file-axis")


func test_right_wheel_ends_90_degrees_clockwise() -> void:
	var u := _make_unit()
	var start: Vector2 = u.facing
	_run_wheel(u, 1)
	assert_true(u.facing.is_equal_approx(start.rotated(PI * 0.5)),
		"a right wheel ends 90° clockwise from the start heading")


func test_left_wheel_ends_90_degrees_counterclockwise() -> void:
	var u := _make_unit()
	var start: Vector2 = u.facing
	_run_wheel(u, -1)
	assert_true(u.facing.is_equal_approx(start.rotated(-PI * 0.5)),
		"a left wheel ends 90° counter-clockwise from the start heading")


func test_hinge_flank_stays_fixed_while_the_far_end_swings() -> void:
	var u := _make_unit(1, 40)
	u.seed_sim_soldiers()
	# The soldier nearest the right hinge should barely move; the one nearest the opposite (left)
	# flank should sweep a large arc. Pick them from the seeded slot positions before the wheel.
	var pivot: Vector2 = u._wheel_pivot_point(1)
	var near_hinge := 0
	var far := 0
	var dn := INF
	var df := -INF
	for i in range(u._sim_soldier_pos.size()):
		var d: float = u._sim_soldier_pos[i].distance_to(pivot)
		if d < dn:
			dn = d; near_hinge = i
		if d > df:
			df = d; far = i
	var hinge_start: Vector2 = u._sim_soldier_pos[near_hinge]
	var far_start: Vector2 = u._sim_soldier_pos[far]
	_run_wheel(u, 1)
	# Let the bodies finish easing onto the settled slots after facing snaps.
	for _i in range(40):
		u.step_sim_soldiers(1.0 / 60.0)
	var hinge_travel: float = u._sim_soldier_pos[near_hinge].distance_to(hinge_start)
	var far_travel: float = u._sim_soldier_pos[far].distance_to(far_start)
	assert_lt(hinge_travel, far_travel * 0.25,
		"the standing flank man barely moves next to the swinging far end (hinge %.1f vs far %.1f)"
			% [hinge_travel, far_travel])
	assert_gt(far_travel, 20.0, "the far end actually swings a meaningful arc")


func test_wheel_is_blocked_while_another_maneuver_runs() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.quarter_turn(1)   # arm a quarter-turn
	u.wheel(1)          # should be refused
	assert_eq(u._wheel_target, Vector2.ZERO, "a wheel is refused while a quarter-turn is armed")


func test_wheel_is_blocked_before_seeding() -> void:
	var u := _make_unit()
	u.wheel(1)   # no bodies seeded yet
	assert_eq(u._wheel_target, Vector2.ZERO, "a wheel is refused before the bodies are seeded")


## Run an in-place turn (conversio or quarter-turn) to completion on a bare unit, driving _think +
## the body layer each tick until it settles. Leaves _formation_angle at whatever the turn absorbed.
func _settle_quarter_turn(u: Unit, dir: int, max_ticks: int = 200) -> void:
	u.quarter_turn(dir)
	var delta := 1.0 / 60.0
	var ticks := 0
	while u._quarter_target != Vector2.ZERO and ticks < max_ticks:
		u._physics_process(delta)
		u.step_sim_soldiers(delta)
		ticks += 1


## Regression: chaining a wheel straight after a quarter-turn (no move order between) must hinge
## about the ACTUAL standing flank. A completed quarter-turn leaves _formation_angle non-zero (it
## absorbs the heading change to keep the slots put), so the pivot geometry has to fold that angle
## into its axes — otherwise it hinges about the wrong point and the "standing" flank sweeps.
func test_wheel_after_quarter_turn_still_hinges_on_the_standing_flank() -> void:
	var u := _make_unit(1, 40)
	u.seed_sim_soldiers()
	_settle_quarter_turn(u, 1)   # DOWN -> LEFT, _formation_angle now non-zero
	assert_almost_eq(u._formation_angle, -PI * 0.5, 0.01,
		"a right quarter-turn leaves _formation_angle at -PI/2 (precondition)")
	# The pivot must coincide with an actual body (the standing flank's front man), NOT the stale
	# axis a formation_angle-blind computation would produce.
	var pivot: Vector2 = u._wheel_pivot_point(1)
	var nearest_body_dist := INF
	var near := 0
	for i in range(u._sim_soldier_pos.size()):
		var d: float = u._sim_soldier_pos[i].distance_to(pivot)
		if d < nearest_body_dist:
			nearest_body_dist = d; near = i
	assert_lt(nearest_body_dist, 1.0,
		"the post-quarter-turn hinge lands on a real body (a formation_angle-blind pivot would not)")
	# And that hinge body barely moves through the wheel, while the far end sweeps.
	var far := 0
	var df := -INF
	for i in range(u._sim_soldier_pos.size()):
		var d: float = u._sim_soldier_pos[i].distance_to(pivot)
		if d > df:
			df = d; far = i
	var hinge_start: Vector2 = u._sim_soldier_pos[near]
	var far_start: Vector2 = u._sim_soldier_pos[far]
	# Wheel using the same path as _run_wheel but WITHOUT re-seeding (bodies already placed).
	u.wheel(1)
	var delta := 1.0 / 60.0
	var ticks := 0
	while u._wheel_target != Vector2.ZERO and ticks < 200:
		u._physics_process(delta)
		u.step_sim_soldiers(delta)
		ticks += 1
	for _i in range(40):
		u.step_sim_soldiers(delta)
	var hinge_travel: float = u._sim_soldier_pos[near].distance_to(hinge_start)
	var far_travel: float = u._sim_soldier_pos[far].distance_to(far_start)
	assert_lt(hinge_travel, far_travel * 0.25,
		"after a quarter-turn, the standing flank still holds (hinge %.1f vs far %.1f)"
			% [hinge_travel, far_travel])
	assert_gt(far_travel, 20.0, "the far end swings a real arc")
