extends GutTest
## Regression guard for the last-unit-rally demo (demos/inputs/last-unit-rally.json): staging
## that exact matchup in a live Battle produces a visible rout, without the battle instantly
## declaring defeat, followed by a rally. Team 0 fields a single full-strength (120) but
## jittery (morale 15) infantry block against an enemy infantry of equal size; contact breaks
## its brittle morale and it flees (drawn faded) while barely bloodied. Losing its last
## fightable unit must NOT end the battle outright -- the sim stays live while the router might
## still rally, per #495. This pins the demo's determinism against the #529 morale retune: if a
## balance change ever stops the unit routing (or breaks the "still in the fight while routing"
## invariant), this fails instead of the demo silently going stale.

# See test_rout_rally_demo_scenario.gd for the ticks-vs-frames rationale. This matchup's
# morale (15, not ~1) means the block absorbs more casualties before its morale erodes past
# 0, so the onset budget is at least as generous as the near-zero-morale demo's (observed
# around tick 784 for this matchup).
const ROUT_ONSET_BUDGET := 900   # ticks allowed for the block to break and start routing
const RALLY_MARGIN := 240        # slack past ROUT_TIME for the router to break contact and recover


var _battle: Node = null


func _rout_time_ticks() -> int:
	return int(ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS))


func _spawn_last_unit_rally_battle() -> void:
	# Seed deterministically, exactly as the demo does (last-unit-rally.json carries seed
	# "12345"); see test_rout_rally_demo_scenario.gd for why this matters.
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	_battle = battle
	# The exact matchup from demos/inputs/last-unit-rally.json.
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 440, "count": 120, "morale": 15.0},
		{"team": 1, "type": "Infantry", "x": 800, "y": 560, "count": 120},
	]
	add_child_autofree(battle)


func _team0_infantry() -> Unit:
	for g in ["units", "routers"]:
		for u in get_tree().get_nodes_in_group(g):
			var unit: Unit = u as Unit
			if unit != null and unit.team == 0:
				return unit
	return null


func test_scenario_routs_then_rallies_without_the_battle_ending() -> void:
	_spawn_last_unit_rally_battle()
	await get_tree().physics_frame

	assert_not_null(_team0_infantry(), "the lone jittery infantry unit spawns")
	if _team0_infantry() == null:
		return

	var budget: int = ROUT_ONSET_BUDGET + _rout_time_ticks() + RALLY_MARGIN

	var routed_tick: int = -1
	var rallied_tick: int = -1
	while _battle.current_tick() < budget:
		await get_tree().physics_frame
		var tick: int = _battle.current_tick()
		var unit: Unit = _team0_infantry()
		assert_not_null(unit, "team 0's last unit stays in play (routs/rallies, never shatters or ends the battle) through the arc")
		if unit == null:
			return
		if unit.state == Unit.State.ROUTING and routed_tick < 0:
			routed_tick = tick
		if routed_tick >= 0 and rallied_tick < 0 and unit.state == Unit.State.IDLE:
			rallied_tick = tick
			break

	assert_true(routed_tick >= 0, "the jittery unit breaks and ROUTS within the budget")
	assert_true(rallied_tick > routed_tick,
		"after routing it RALLIES back to IDLE within the budget (rout tick %d, rally tick %d)"
			% [routed_tick, rallied_tick])

	var rallied: Unit = _team0_infantry()
	assert_not_null(rallied, "the rallied unit is still on the field")
	if rallied != null:
		assert_true(rallied.is_in_group("units"), "the rallied unit rejoins the fightable units")
