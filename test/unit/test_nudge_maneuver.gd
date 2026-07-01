extends GutTest
## Arrow-key nudge maneuvers: Left / Right side-step and Down back-step a small
## fixed distance while holding facing. Two layers: the pure Battle.nudge_offset
## geometry (no SceneTree), and a live battle stepped tick by tick to confirm the
## selection actually shifts laterally / backward and keeps its facing.

const BattleScript = preload("res://scripts/Battle.gd")


# --- pure geometry ---------------------------------------------------------

func test_left_and_right_offsets_are_lateral_and_opposite() -> void:
	# Facing UP (0,-1): the unit's right side is world +x, left is -x.
	var left: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.LEFT)
	var right: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.RIGHT)
	assert_almost_eq(left.x, -BattleScript.NUDGE_DISTANCE, 0.001, "left is world -x when facing up")
	assert_almost_eq(left.y, 0.0, 0.001, "left has no forward/back component")
	assert_almost_eq(right.x, BattleScript.NUDGE_DISTANCE, 0.001, "right is world +x when facing up")
	assert_almost_eq(right.y, 0.0, 0.001, "right has no forward/back component")


func test_back_offset_is_opposite_facing() -> void:
	# Facing UP (0,-1): back is straight down (+y).
	var back: Vector2 = BattleScript.nudge_offset(Vector2.UP, BattleScript.NudgeDir.BACK)
	assert_almost_eq(back.x, 0.0, 0.001, "back has no lateral component")
	assert_almost_eq(back.y, BattleScript.NUDGE_DISTANCE, 0.001, "back steps directly away from facing")


func test_offsets_are_fixed_length_and_relative_to_facing() -> void:
	# A different heading rotates the whole basis: facing RIGHT (1,0) -> back is -x.
	var back: Vector2 = BattleScript.nudge_offset(Vector2.RIGHT, BattleScript.NudgeDir.BACK)
	assert_almost_eq(back.x, -BattleScript.NUDGE_DISTANCE, 0.001, "back is -x when facing right")
	assert_almost_eq(back.y, 0.0, 0.001, "...with no lateral component")
	# Every nudge is the same fixed distance, whatever the direction.
	for d in [BattleScript.NudgeDir.LEFT, BattleScript.NudgeDir.RIGHT, BattleScript.NudgeDir.BACK]:
		var off: Vector2 = BattleScript.nudge_offset(Vector2.RIGHT, d)
		assert_almost_eq(off.length(), BattleScript.NUDGE_DISTANCE, 0.001,
			"a nudge is a fixed small distance")


func test_nudge_distance_stays_within_the_sidestep_ceiling() -> void:
	# Design guard on NUDGE_DISTANCE. The nudge bypasses UnitManeuver.is_sidestep()
	# entirely -- _apply_order_cmd sets ordered_facing directly -- but the distance
	# should stay small enough that it *would* read as a side-step if it ever went
	# through the classifier, so bumping it past the cap trips this test.
	assert_lt(BattleScript.NUDGE_DISTANCE, UnitManeuver.SIDESTEP_MAX_DISTANCE,
		"a lateral nudge is short enough to read as a side-step")


# --- live battle -----------------------------------------------------------

func _team0_unit_near(target: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0 and unit.state != Unit.State.DEAD:
			var d: float = unit.position.distance_to(target)
			if d < best_d:
				best_d = d
				best = unit
	return best


func test_left_nudge_shifts_laterally_and_holds_facing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # rehearse in isolation; no enemy to pull the unit into a fight
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var u: Unit = _team0_unit_near(Vector2(650, 300))
	assert_not_null(u, "found a team-0 unit to nudge")
	if u == null:
		return
	var start_pos: Vector2 = u.position
	var start_facing: Vector2 = u.facing
	var fwd: Vector2 = start_facing.normalized()
	var perp := Vector2(-fwd.y, fwd.x)   # unit's right-hand side

	battle.enqueue_nudge([u.uid], BattleScript.NudgeDir.LEFT)
	for _i in range(120):   # the order-response delay (~0.5 s) + the short walk + settle
		await get_tree().physics_frame

	var moved: Vector2 = u.position - start_pos
	var lateral: float = moved.dot(perp)    # to the unit's right (negative = left)
	var forward: float = moved.dot(fwd)
	assert_lt(lateral, -5.0, "a left nudge shifts the unit to its left")
	assert_lt(absf(forward), absf(lateral), "the shift is mainly lateral, not forward")
	assert_true(u.facing.is_equal_approx(start_facing),
		"a side-step holds facing — the unit does not pivot to face travel")


func test_down_nudge_steps_back_and_holds_facing() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var u: Unit = _team0_unit_near(Vector2(650, 300))
	assert_not_null(u, "found a team-0 unit to nudge")
	if u == null:
		return
	var start_pos: Vector2 = u.position
	var start_facing: Vector2 = u.facing
	var fwd: Vector2 = start_facing.normalized()

	battle.enqueue_nudge([u.uid], BattleScript.NudgeDir.BACK)
	for _i in range(120):   # the order-response delay (~0.5 s) + the short walk + settle
		await get_tree().physics_frame

	var moved: Vector2 = u.position - start_pos
	var forward: float = moved.dot(fwd)   # negative = backward
	assert_lt(forward, -5.0, "a down nudge steps the unit backward")
	assert_true(u.facing.is_equal_approx(start_facing),
		"a back-step holds facing — the unit does not turn around")
