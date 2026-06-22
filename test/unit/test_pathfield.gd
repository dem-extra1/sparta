extends GutTest
## PathField: deterministic grid A* routing. With no obstacles the
## path is a straight line (movement unchanged); with a wall, units route around.

const FIELD := Rect2(0, 0, 640, 640)


func test_clear_line_steps_straight_to_target() -> void:
	var pf := PathField.new(FIELD)
	var target := Vector2(600, 50)
	assert_eq(pf.next_step(Vector2(50, 50), target), target,
		"with no obstacles the next step is the target itself")


func test_find_path_returns_a_route_between_distinct_cells() -> void:
	var pf := PathField.new(FIELD)
	# find_path always computes an A* route; the straight-line shortcut lives in
	# next_step(), so units skip A* when the line is clear (tested above).
	assert_gt(pf.find_path(Vector2(50, 50), Vector2(600, 50)).size(), 0,
		"A* returns a cell route between two distinct free cells")


func test_cell_aligned_wall_blocks_only_its_own_cell() -> void:
	# A wall sized exactly to one cell (CELL=64) must not spill into neighbours:
	# rect.end is exclusive, so the floor mapping must stay inside the wall.
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(64, 0, 64, 64))
	assert_true(pf.is_blocked(Vector2(70, 10)), "the wall's own cell is blocked")
	assert_false(pf.is_blocked(Vector2(140, 10)), "the cell to the right is clear")
	assert_false(pf.is_blocked(Vector2(70, 80)), "the cell below is clear")


func test_routes_around_a_wall_with_a_gap() -> void:
	var pf := PathField.new(FIELD)
	# A vertical wall across the upper field, leaving a gap along the bottom.
	pf.block_rect(Rect2(300, 0, 64, 480))
	var from := Vector2(50, 50)
	var to := Vector2(600, 50)
	# The straight line is blocked, so the next step must deviate from the target.
	assert_ne(pf.next_step(from, to), to, "a blocked line forces a detour")
	var path := pf.find_path(from, to)
	assert_gt(path.size(), 0, "an A* route around the wall exists")
	# Every waypoint avoids the wall.
	for p in path:
		assert_false(pf.is_blocked(p), "no waypoint sits inside the wall")


func test_path_is_deterministic() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(300, 0, 64, 480))
	var a := pf.find_path(Vector2(50, 50), Vector2(600, 50))
	var b := pf.find_path(Vector2(50, 50), Vector2(600, 50))
	assert_eq(a, b, "the same query yields the same route (replay-safe)")


func test_blocked_goal_falls_back_to_target() -> void:
	var pf := PathField.new(FIELD)
	pf.block_rect(Rect2(560, 0, 80, 120))   # the goal cell is inside terrain
	var to := Vector2(600, 50)
	# No reachable cell route; next_step falls back to the raw target rather than
	# stalling, so callers always make progress.
	assert_eq(pf.next_step(Vector2(50, 50), to), to,
		"an unreachable goal falls back to a straight step")


func test_speed_rect_returns_configured_scale() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var inside := Vector2(264, 264)   # centre of the rect
	assert_almost_eq(pf.speed_at(inside), 0.6, 0.001,
		"a cell inside a speed zone returns the configured scale")


func test_speed_at_returns_one_outside_any_zone() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var outside := Vector2(50, 50)
	assert_almost_eq(pf.speed_at(outside), 1.0, 0.001,
		"a cell with no speed zone returns full speed (1.0)")


func test_speed_zone_does_not_block_movement() -> void:
	var pf := PathField.new(FIELD)
	pf.set_speed_rect(Rect2(200, 200, 128, 128), 0.6)
	var inside := Vector2(264, 264)
	assert_false(pf.is_blocked(inside),
		"a speed zone does not block movement (units can enter)")
