extends GutTest
## A move order into the unit's REAR sector should about-face (conversio) in place,
## then march to the destination facing it -- NOT pivot the whole block 180° about its
## centre. Two layers: the pure UnitManeuver.is_rear_move classifier (no SceneTree), and
## a unit-level integration that seeds soldier bodies, arms the conversio, and steps
## _think tick by tick, asserting the unit reverses facing and only then starts marching.

const Maneuver = preload("res://scripts/UnitManeuver.gd")

const FACING_RIGHT := Vector2.RIGHT


# --- pure classifier -------------------------------------------------------

func test_move_straight_behind_is_a_rear_move() -> void:
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, Vector2(-100, 0)),
		"a destination directly behind (180°) is a rear move")


func test_move_straight_ahead_is_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(100, 0)),
		"marching forward is not a rear move")


func test_move_to_the_flank_is_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(0, 100)),
		"a 90° flank move is not in the rear sector")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2(0, -100)),
		"the other flank likewise")


func test_rear_boundary_is_135_degrees() -> void:
	# 140° behind facing -> rear; 130° behind -> not. Build the vectors by rotating
	# the reversed facing a little toward the flank.
	var just_rear := FACING_RIGHT.rotated(deg_to_rad(140.0)) * 100.0
	var just_outside_rear := FACING_RIGHT.rotated(deg_to_rad(130.0)) * 100.0
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, just_rear),
		"140° off facing is inside the rear sector")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, just_outside_rear),
		"130° off facing is just outside the rear sector (oblique-rear, not rear enough)")


func test_rear_move_is_symmetric_across_facing() -> void:
	# The classifier keys off the absolute angle, so a rear destination reads the same
	# whether it lies behind-left or behind-right.
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, FACING_RIGHT.rotated(deg_to_rad(150.0)) * 80.0),
		"behind and to one side is a rear move")
	assert_true(Maneuver.is_rear_move(FACING_RIGHT, FACING_RIGHT.rotated(deg_to_rad(-150.0)) * 80.0),
		"behind and to the other side is a rear move")


func test_degenerate_inputs_are_not_a_rear_move() -> void:
	assert_false(Maneuver.is_rear_move(Vector2.ZERO, Vector2(-10, 0)),
		"no facing -> no rear move")
	assert_false(Maneuver.is_rear_move(FACING_RIGHT, Vector2.ZERO),
		"a zero-length move -> no rear move")


# --- unit-level integration ------------------------------------------------

func _make_seeded_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()   # populate _sim_soldier_pos / _sim_soldier_facing so conversio can run
	return u


func test_rear_move_about_faces_then_marches() -> void:
	var u := _make_seeded_unit()
	var start_facing: Vector2 = u.facing   # DOWN
	# Arm the rear-move exactly as Battle does: conversio + park the destination behind.
	var dest := Vector2(0, -200)           # straight behind a DOWN-facing unit
	u.conversio()
	assert_ne(u._conversio_target, Vector2.ZERO, "the conversio armed (bodies were seeded)")
	u._pending_march_target = dest
	u._has_pending_march = true

	# While the about-face is turning, the unit must NOT be marching yet.
	u._think(0.016)
	assert_false(u.has_move_target, "no march starts until the about-face completes")
	assert_eq(u.position, Vector2.ZERO, "the block does not translate during the turn")

	# Step until the conversio finishes and the parked march commits.
	var started := false
	for _i in range(120):
		u._think(0.016)
		if u.has_move_target:
			started = true
			break
	assert_true(started, "the parked march commits once the about-face completes")
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading (about-faced, not pivoted mid-march)")
	assert_eq(u.move_target, dest, "it marches to the parked rear destination")
	assert_false(u._has_pending_march, "the pending-march flag is cleared once committed")


func test_rear_move_marches_toward_the_destination_not_backward() -> void:
	var u := _make_seeded_unit()
	var dest := Vector2(0, -200)
	u.conversio()
	u._pending_march_target = dest
	u._has_pending_march = true
	# Run well past the turn so the march is underway.
	for _i in range(200):
		u._think(0.016)
	assert_lt(u.position.y, 0.0,
		"the unit advances toward the rear destination (its y decreases toward -200)")
	assert_true(u.facing.y < 0.0,
		"and it faces the way it marches (upward), having about-faced rather than reversing")


func test_move_order_cancels_a_pending_rear_march() -> void:
	# A fresh interrupt mid-about-face drops the parked march (Battle re-issues the order,
	# and _think clears the pending flag when a move target arrives or combat pre-empts).
	var u := _make_seeded_unit()
	u.conversio()
	u._pending_march_target = Vector2(0, -200)
	u._has_pending_march = true
	# Simulate a new plain move order landing: has_move_target set true pre-empts the conversio.
	u.has_move_target = true
	u.move_target = Vector2(300, 0)
	u._think(0.016)
	assert_eq(u._conversio_target, Vector2.ZERO, "the interrupting order cancels the about-face")
	assert_false(u._has_pending_march, "and drops the now-stale parked rear march")
