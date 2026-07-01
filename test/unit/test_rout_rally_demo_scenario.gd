extends GutTest
## Regression guard for the rout->rally demo (demos/inputs/rout-rally-recover.json): staging
## that exact matchup in a live Battle produces a visible rout FOLLOWED BY a rally. The lone
## low-morale infantry block breaks (enters ROUTING, drawn faded), the enemy cavalry lose it as
## a target (routers are untargetable) and stop pursuing, so it breaks contact; its morale then
## recovers asymptotically past the rally threshold and it returns to play (IDLE) still on the
## field. A second, safe player unit keeps the battle from declaring defeat (and freezing) the
## instant the infantry routs -- the same reason the demo scenario includes one. This pins the
## demo's determinism: if a balance change ever stops the unit routing or rallying, this fails
## instead of the demo silently going stale.

# Budget the arc in SIM ticks (Battle.current_tick()), not in await iterations. Under coverage
# instrumentation an `await physics_frame` no longer maps one-to-one onto a sim tick, so counting
# loop iterations against a fixed clip length races the interpreter's speed. Reading the battle's
# own tick counter measures sim progress directly, and the budget comes from the sim's own timing
# constants (with generous margin) rather than the demo's presentation clip length.
#
# A two-cavalry charge onto a morale-1 block routs it, then the recovery leg is bounded by
# ROUT_TIME (the router rallies or shatters when the timer expires, sooner if morale crosses the
# threshold with contact broken). ROUT_ONSET_BUDGET covers the charge-in and break; ROUT_TIME plus
# margin covers the flee-and-recover. The onset budget is deliberately generous so a physics
# retune (e.g. a change to the soldier-body arrival dynamics) that shifts *when* the block breaks
# doesn't push the arc past the budget: the onset has been observed anywhere from ~tick 100 to
# ~tick 365 depending on the body physics, and the whole arc still lands well inside this total.
const ROUT_ONSET_BUDGET := 600   # ticks allowed for the block to break and start routing
const RALLY_MARGIN := 240        # slack past ROUT_TIME for the router to break contact and recover


var _battle: Node = null


func _rout_time_ticks() -> int:
	# The sim's fixed step rate, from the canonical autoload constant, so the tick budget tracks
	# the real step rate if it ever changes rather than a duplicated literal.
	return int(ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS))


func _spawn_rout_rally_battle() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	_battle = battle
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


func test_scenario_routs_then_rallies_within_the_budget() -> void:
	_spawn_rout_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_infantry(), "the low-morale infantry unit spawns")
	if _infantry() == null:
		return

	# Tick budget derived from the sim's own timing constants: onset headroom, the rout timer, and
	# slack for the router to break contact and recover. Independent of interpreter speed.
	var budget: int = ROUT_ONSET_BUDGET + _rout_time_ticks() + RALLY_MARGIN

	var routed_tick: int = -1
	var rallied_tick: int = -1
	var min_y_while_routing: float = INF   # how far up the field it fled (team 0 flees toward y=0)
	while _battle.current_tick() < budget:
		await get_tree().physics_frame
		var tick: int = _battle.current_tick()
		var unit: Unit = _infantry()
		assert_not_null(unit, "the unit stays in play (routs/rallies, never shatters) through the arc")
		if unit == null:
			return
		if unit.state == Unit.State.ROUTING:
			min_y_while_routing = minf(min_y_while_routing, unit.position.y)
			if routed_tick < 0:
				routed_tick = tick
		if routed_tick >= 0 and rallied_tick < 0 and unit.state == Unit.State.IDLE:
			rallied_tick = tick
			break

	assert_true(routed_tick >= 0, "the weak unit breaks and ROUTS within the budget")
	assert_true(rallied_tick > routed_tick,
		"after routing it RALLIES back to IDLE within the budget (rout tick %d, rally tick %d)"
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
