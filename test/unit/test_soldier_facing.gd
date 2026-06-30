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


# --- Conversio (about-face, #370) -------------------------------------------

func test_conversio_sets_target_and_starts_turning() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.conversio()
	# The target is set; the turn starts on the first _think() tick, not immediately.
	assert_true(u._conversio_target.is_equal_approx(Vector2.UP),
		"conversio target is the reversed heading")
	assert_true(u.facing.is_equal_approx(Vector2.DOWN),
		"unit.facing has not moved yet (the turn starts on the first tick)")
	# Per-soldier ownership is not used — all soldiers rotate together via unit.facing,
	# which SoldierBodies.step auto-syncs each tick when _per_soldier_facing is false.
	assert_false(u._per_soldier_facing,
		"conversio does not take per-soldier ownership (uniform rotation tracks unit.facing)")


func test_conversio_blocked_while_fighting() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.conversio()
	assert_true(u._conversio_target.is_zero_approx(),
		"no conversio target set when blocked by combat")


func test_conversio_blocked_before_bodies_are_seeded() -> void:
	var u := _make_unit()
	# no seed_sim_soldiers() call
	u.conversio()
	assert_true(u._conversio_target.is_zero_approx(),
		"no conversio target when no bodies exist")


func test_conversio_reverses_any_starting_heading() -> void:
	var u := _make_unit()
	u.seed_sim_soldiers()
	u.facing = Vector2.RIGHT
	u.step_sim_soldiers(0.1)   # sync bodies to the new heading
	u.conversio()
	assert_true(u._conversio_target.is_equal_approx(Vector2.LEFT),
		"conversio target is LEFT when starting from RIGHT")
	assert_true(u.facing.is_equal_approx(Vector2.RIGHT),
		"unit.facing is unchanged at call time; the turn starts on the next tick")


# --- About-face completion: relabel, don't march -----------------------------

func test_about_face_relabel_preserves_world_positions() -> void:
	# The completion relabel is a pure reversal of the body arrays: the SET of world
	# positions is unchanged (nobody walks), each body just takes the reversed body's spot.
	var u := _make_unit()
	u.seed_sim_soldiers()
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var n: int = before.size()
	u._reverse_soldier_bodies()
	assert_eq(u._sim_soldier_pos.size(), n, "body count is unchanged by the relabel")
	for i in range(n):
		assert_true(u._sim_soldier_pos[i].is_equal_approx(before[n - 1 - i]),
			"body %d takes the reversed body's position (pure relabel, no movement)" % i)


func test_about_face_leaves_bodies_on_their_slots() -> void:
	# On a full (centrosymmetric) grid, flipping facing 180° and relabelling the bodies
	# lands every body exactly on its new-facing slot, so the arrival spring has ~zero
	# error and the block does not surge across itself after the turn.
	var u := _make_unit()
	u.frontage_override = 8        # 8 files x 5 ranks = 40: a full, centrosymmetric grid
	u.seed_sim_soldiers()
	u.facing = Vector2(-u.facing.x, -u.facing.y)   # the about-face end state
	u._reverse_soldier_bodies()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(u._sim_soldier_pos.size()):
		assert_lt(u._sim_soldier_pos[i].distance_to(slots[i]), 0.01,
			"body %d sits on its reversed-facing slot (no post-turn spring)" % i)
