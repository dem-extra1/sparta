extends GutTest
## Regression guard for the rout->rally demo (demos/inputs/rout-rally-recover.json): staging
## that exact matchup in a live Battle produces a visible rout FOLLOWED BY a rally within the
## recorded clip's length. The lone low-morale infantry block breaks (enters ROUTING, drawn
## faded), the enemy cavalry lose it as a target (routers are untargetable) and stop pursuing,
## so it breaks contact; its morale then recovers asymptotically past the rally threshold and it
## returns to play (IDLE) still on the field. A second, safe player unit keeps the battle from
## declaring defeat (and freezing) the instant the infantry routs -- the same reason the demo
## scenario includes one. This pins the demo's determinism: if a balance change ever stops the
## unit routing or rallying inside the clip, this fails instead of the demo silently going stale.

# The recorded clip is 300 frames at fixed_fps 30; Movie Maker steps physics at 60 tps, so it
# covers 600 physics ticks. Assert the whole arc lands inside that budget.
const CLIP_PHYSICS_TICKS := 600


func _spawn_rout_rally_battle() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	# The exact matchup from demos/inputs/rout-rally-recover.json.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 430, "count": 140, "morale": 1.0},
		{"team": 0, "type": "Spearmen", "x": 300, "y": 300, "count": 140, "morale": 100.0},
		{"team": 1, "type": "Cavalry", "x": 740, "y": 560},
		{"team": 1, "type": "Cavalry", "x": 860, "y": 560},
	]
	add_child_autofree(battle)


## The infantry regiment (the one that routs and rallies), by name -- so we don't pick up the
## standing spearmen. A rallied unit rejoins "units"; a routing one is in "routers".
func _infantry() -> Unit:
	for g in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(g):
			var unit: Unit = u as Unit
			if unit != null and unit.team == 0 and str(unit.unit_name).begins_with("Infantry"):
				return unit
	return null


func test_scenario_routs_then_rallies_within_the_clip() -> void:
	_spawn_rout_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_infantry(), "the low-morale infantry unit spawns")
	if _infantry() == null:
		return

	var routed_tick: int = -1
	var rallied_tick: int = -1
	var min_y_while_routing: float = INF   # how far up the field it fled (team 0 flees toward y=0)
	for tick in range(CLIP_PHYSICS_TICKS):
		await get_tree().physics_frame
		var unit: Unit = _infantry()
		assert_not_null(unit, "the unit stays in play (routs/rallies, never shatters) through the clip")
		if unit == null:
			return
		if unit.state == Unit.State.ROUTING:
			min_y_while_routing = minf(min_y_while_routing, unit.position.y)
			if routed_tick < 0:
				routed_tick = tick
		if routed_tick >= 0 and rallied_tick < 0 and unit.state == Unit.State.IDLE:
			rallied_tick = tick
			break

	assert_true(routed_tick >= 0, "the weak unit breaks and ROUTS within the clip")
	assert_true(rallied_tick > routed_tick,
		"after routing it RALLIES back to IDLE before the clip ends (rout tick %d, rally tick %d)"
			% [routed_tick, rallied_tick])
	# It fled toward its own back edge but stayed on the field: clamped at y >= 0, never off-map.
	assert_true(min_y_while_routing >= 0.0,
		"the router stays on the field (clamped to the top edge), never running off the map")

	var rallied: Unit = _infantry()
	assert_not_null(rallied, "the rallied unit is still on the field")
	if rallied != null:
		assert_true(rallied.is_in_group("units"), "the rallied unit rejoins the fightable units")
		# Its morale recovered while fleeing: it comes back above the fragile rally floor, not at
		# the collapsed value it broke on. (Whether the threshold or the timer triggers the rally
		# depends on the exact tick; both are valid rally paths, so only the floor is asserted.)
		assert_true(rallied.morale >= Unit.RALLY_MORALE,
			"it reforms at or above the fragile rally floor, having recovered from the collapse")
