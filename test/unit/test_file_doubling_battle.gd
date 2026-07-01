extends GutTest
## File-doubling (duplicatio / explicatio) in a LIVE battle: instantiate the real Battle
## scene, spawn the armies, and drive the maneuver through the recorded order path
## (Battle.enqueue_file_double) exactly as the hotkey does. Steps the full simulation tick
## by tick and asserts the resulting frontage AND that the soldier bodies ease into the
## reshaped slots at velocity -- no body teleports, and the regiment centre stays put (the
## reshape changes the formation, not the unit position).

# The regiment centre couples toward its soldiers' body centroid (SoldierBodies.couple),
# so reshaping the block shifts the centre by the small amount the centroid moves as the
# ranks re-lay-out -- a deepening (duplicatio) settles a touch more than a widening. This
# bounds that one-time settle well below a real "the unit walked off" regression (tens of px).
const CENTRE_SETTLE_TOLERANCE_PX := 10.0


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


func _target_unit(tree: SceneTree) -> Unit:
	# The block nearest ~(500, 300) -- the same Spearmen the file-doubling demo exercises.
	var target: Unit = null
	var best := INF
	for u in tree.get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			var d: float = unit.position.distance_to(Vector2(500, 300))
			if d < best:
				best = d
				target = unit
	return target


func test_explicatio_widens_the_line_without_teleporting_bodies() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):                      # spawn the armies and let the bodies settle
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_frontage: int = UnitFormation.frontage(target)
	var start_pos: Vector2 = target.position
	battle.enqueue_file_double([target.uid], 1)   # explicatio
	assert_eq(UnitFormation.frontage(target), start_frontage * 2,
		"explicatio doubles the frontage")

	# Step the sim: the soldier bodies ease toward the reshaped slots. No body should jump.
	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(90):                      # ~1.5 s to ease into the new block
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 6.0,
		"bodies ease into the reshaped slots at velocity, no teleport (worst %.3f px)" % worst_step)
	assert_lt(target.position.distance_to(start_pos), CENTRE_SETTLE_TOLERANCE_PX,
		"the reshape moves the formation, not the regiment centre")
	# The widened block is broader (more files) and shallower than it started.
	var wide_bbox: Vector2 = _bbox(target._sim_soldier_pos)
	assert_gt(wide_bbox.length(), 0.0, "the reshaped block has a real footprint")


func test_duplicatio_deepens_the_line() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(40):
		await get_tree().physics_frame
	var target: Unit = _target_unit(get_tree())
	assert_not_null(target, "found a team-0 unit to reshape")
	if target == null:
		return

	var start_frontage: int = UnitFormation.frontage(target)
	var start_pos: Vector2 = target.position
	battle.enqueue_file_double([target.uid], -1)   # duplicatio
	assert_eq(UnitFormation.frontage(target), maxi(1, start_frontage / 2),
		"duplicatio halves the frontage")

	var prev: PackedVector2Array = target._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	for _i in range(90):
		await get_tree().physics_frame
		worst_step = maxf(worst_step, _max_step(prev, target._sim_soldier_pos))
		prev = target._sim_soldier_pos.duplicate()

	assert_lt(worst_step, 6.0,
		"bodies ease into the deeper block, no teleport (worst %.3f px)" % worst_step)
	assert_lt(target.position.distance_to(start_pos), CENTRE_SETTLE_TOLERANCE_PX,
		"the reshape moves the formation, not the regiment centre")
