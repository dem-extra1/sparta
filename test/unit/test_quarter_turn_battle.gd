extends GutTest
## Quarter-turn in a LIVE battle: instantiate the real Battle scene and step it tick by tick
## through a quarter-turn on a spawned unit, exactly as the demo does (Battle._physics_process
## -> units -> _on_soldier_tick, with steering + couple). Guards that the maneuver causes no
## body surge in the full simulation context, not just an isolated unit — the gap that the
## first (transpose) cut hid and the render frames couldn't resolve.


func _bbox(ps: PackedVector2Array) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in ps:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return mx - mn


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


func test_quarter_turn_in_live_battle_has_no_surge() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	# Target the same unit the demo turns: the Infantry block at ~(650, 300). Its pointer
	# marks read cleanly under rotation, so test and demo exercise the same unit.
	var target: Unit = null
	var best := INF
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(Vector2(650, 300))
			if d < best:
				best = d
				target = unit
	assert_not_null(target, "found a team-0 unit to turn")
	if target == null:
		return

	var start_bbox: Vector2 = _bbox(target._sim_soldier_pos)
	var start_pos: Vector2 = target.position
	var start_facing: Vector2 = target.facing   # capture, don't assume the spawn heading
	target.quarter_turn(1)
	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	var worst_bbox_drift := 0.0
	for _i in range(50):                      # the ~0.25 s turn + settle
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		worst_bbox_drift = maxf(worst_bbox_drift, (_bbox(target._sim_soldier_pos) - start_bbox).length())
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 0.5,
		"no body jumps on any tick of a live-battle quarter-turn (worst %.3f px)" % worst_step)
	assert_lt(worst_bbox_drift, 1.0,
		"the block keeps its footprint — no collapse/re-expand (worst drift %.3f px)" % worst_bbox_drift)
	assert_lt(target.position.distance_to(start_pos), 1.0,
		"the regiment does not reposition")
	assert_true(target.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"the unit ended a quarter-turn (90° right) from its start heading")
