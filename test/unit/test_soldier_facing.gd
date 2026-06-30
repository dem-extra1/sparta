extends GutTest
## Per-soldier facing layer (drill-maneuver foundation, #366). The bodies carry a
## facing index-aligned with _sim_soldier_pos; by default it tracks the unit
## heading, and a maneuver can take ownership to orient bodies individually. These
## pin the data layer's invariants -- seeding, the default sync, maneuver
## ownership, release, and index-alignment across casualties -- before the
## per-soldier maneuvers (#370 about-face, #371 quarter-turn) consume it.


func _make_unit(uid: int = 1, max_soldiers: int = 40) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _all_face(u: Unit, dir: Vector2, msg: String) -> void:
	for i in range(u._sim_soldier_facing.size()):
		assert_true(u._sim_soldier_facing[i].is_equal_approx(dir),
			"%s (body %d)" % [msg, i])


func test_seed_points_every_body_at_the_unit_heading() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	assert_eq(u._sim_soldier_facing.size(), u._sim_soldier_pos.size(),
		"facing is index-aligned with the bodies")
	_all_face(u, Vector2.DOWN, "seeded bodies face the unit heading")
	assert_false(u._per_soldier_facing, "no maneuver owns the facing after seeding")


func test_default_sync_tracks_the_unit_heading() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.facing = Vector2.RIGHT
	u.step_sim_soldiers(0.1)
	_all_face(u, Vector2.RIGHT, "with no maneuver, bodies follow the unit heading each tick")


func test_set_all_soldier_facing_takes_ownership() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.set_all_soldier_facing(Vector2.UP)
	assert_true(u._per_soldier_facing, "setting facings raises the maneuver flag")
	_all_face(u, Vector2.UP, "every body now faces the commanded direction")
	# A step must NOT re-sync the owned facings back to the unit heading.
	u.facing = Vector2.RIGHT
	u.step_sim_soldiers(0.1)
	_all_face(u, Vector2.UP, "owned facings survive a step at a different unit heading")


func test_set_one_soldier_facing_leaves_the_rest() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.set_soldier_facing(2, Vector2.LEFT)
	assert_true(u.soldier_facing(2).is_equal_approx(Vector2.LEFT), "body 2 took the new facing")
	assert_true(u.soldier_facing(0).is_equal_approx(Vector2.DOWN), "body 0 keeps the unit heading")
	assert_true(u._per_soldier_facing, "one set still takes ownership")


func test_release_resyncs_to_the_unit_heading() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.set_all_soldier_facing(Vector2.UP)
	u.facing = Vector2.RIGHT
	u.release_soldier_facing()
	assert_false(u._per_soldier_facing, "release clears the maneuver flag")
	_all_face(u, Vector2.RIGHT, "release snaps every body back to the unit heading")


func test_facing_survives_casualties_index_aligned() -> void:
	var u := _make_unit(1, 40)
	u.seed_sim_soldiers()
	u.set_all_soldier_facing(Vector2.UP)
	u.soldiers = 12                    # casualties trim the rear bodies
	u.step_sim_soldiers(0.1)
	assert_eq(u._sim_soldier_facing.size(), u._sim_soldier_pos.size(),
		"facing stays index-aligned with the bodies after casualties")
	_all_face(u, Vector2.UP, "the surviving bodies keep their owned facing")


func test_growth_during_an_owned_maneuver_keeps_alignment() -> void:
	# Bodies added back (e.g. reinforcement) during an owned maneuver: the array
	# stays index-aligned, existing bodies keep their owned facing, and fresh tail
	# bodies join at the unit heading.
	var u := _make_unit(1, 40)
	u.soldiers = 12
	u.seed_sim_soldiers()
	u.set_all_soldier_facing(Vector2.UP)
	u.soldiers = 30                    # grow back
	u.step_sim_soldiers(0.1)
	assert_eq(u._sim_soldier_facing.size(), u._sim_soldier_pos.size(),
		"facing stays index-aligned with the bodies after growth")
	assert_true(u.soldier_facing(0).is_equal_approx(Vector2.UP),
		"an existing body keeps its owned facing")
	assert_true(u.soldier_facing(25).is_equal_approx(Vector2.DOWN),
		"a fresh tail body joins at the unit heading")


func test_set_all_before_seed_takes_no_ownership() -> void:
	# Calling the setter before bodies exist must not silently arm the flag (the
	# bodies would otherwise emerge facing the unit heading, not the command).
	var u := _make_unit()
	u.set_all_soldier_facing(Vector2.UP)   # no bodies seeded yet
	assert_false(u._per_soldier_facing, "no ownership is taken with no bodies to orient")
	u.seed_sim_soldiers()
	_all_face(u, Vector2.DOWN, "seeded bodies face the unit heading, not a lost command")


func test_accessor_and_setters_guard_bad_input() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	assert_true(u.soldier_facing(9999).is_equal_approx(Vector2.DOWN),
		"an out-of-range index returns the unit heading, not a crash")
	u.set_all_soldier_facing(Vector2.ZERO)
	assert_false(u._per_soldier_facing, "a zero direction is a no-op (no ownership taken)")
	u.set_soldier_facing(0, Vector2.ZERO)
	assert_false(u._per_soldier_facing, "a zero per-body direction is a no-op too")
