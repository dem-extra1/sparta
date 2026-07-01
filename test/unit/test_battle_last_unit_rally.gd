extends GutTest
## A team's last unit routing must NOT end the battle while that unit is still on the
## field and eligible to rally. _check_victory counts a routing unit (in the "routers"
## group) as keeping its team in play, so the sim stays live long enough for the rout to
## resolve — the unit rallies back into the fight, or shatters and only THEN ends the
## battle. Regression guard for the "last unit can't rally" freeze.
##
## The scenario stages exactly two units far apart (well beyond RALLY_CONTACT_RADIUS), so
## the lone team-0 unit can flee, break contact, and rally without any live enemy nearby.


var _battle: Node = null


func after_each() -> void:
	# Free THIS test's battle before the next test spawns, so its units don't linger in the
	# shared "units"/"routers" groups and pollute a later test's group scan. Awaiting a frame
	# lets queue_free() settle. Also clear the tree pause show_end() sets, so a paused state
	# can't leak into the next test (GUT keeps running in the same tree).
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_two_unit_battle() -> Node:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	# One unit per side, far apart: team 0 up top, team 1 well below (out of rally-contact
	# range), so a routed team-0 unit fleeing up breaks contact and can rally.
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 200},
		{"team": 1, "type": "Infantry", "x": 500, "y": 1400},
	]
	add_child(_battle)
	return _battle


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


func test_last_unit_routing_keeps_the_battle_alive_and_can_rally() -> void:
	var battle := _spawn_two_unit_battle()
	await get_tree().physics_frame            # _ready spawns the scenario units

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone team-0 unit deployed")
	if mine == null:
		return
	assert_false(battle._ended, "a fresh two-unit battle has not ended")

	# Break the unit: it leaves the "units" group for "routers" and starts fleeing.
	mine._rout()
	assert_eq(mine.state, Unit.State.ROUTING, "the unit is routing")
	assert_false(mine.is_in_group("units"), "a router has left the fightable units group")
	assert_true(mine.is_in_group("routers"), "and joined the routers group")

	# The team still has a body on the field that might rally, so victory must NOT fire.
	battle._check_victory()
	assert_false(battle._ended,
		"the battle stays live while the team's last unit is merely routing")

	# Let the rout resolve. The unit is far from the enemy (broke contact) and keeps its
	# full strength, so it rallies rather than shatters. Shorten the timer so the rout
	# resolves within a couple of ticks instead of the full ROUT_TIME.
	mine._rout_timer = 0.01
	for _k in range(4):
		await get_tree().physics_frame

	assert_eq(mine.state, Unit.State.IDLE, "the routed unit rallied back under control")
	assert_true(mine.is_in_group("units"), "and rejoined the fightable units group")
	assert_false(mine.is_in_group("routers"), "leaving the routers group")
	assert_false(battle._ended,
		"the battle never ended: the last unit recovered instead of instantly losing")


func test_team_with_all_units_truly_gone_still_ends_the_battle() -> void:
	var battle := _spawn_two_unit_battle()
	await get_tree().physics_frame

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone team-0 unit deployed")
	if mine == null:
		return

	# The unit is destroyed for good — it leaves BOTH groups and frees. Team 0 now has
	# nothing on the field, so victory must fire for the enemy.
	mine._remove_from_play()
	await get_tree().physics_frame            # let queue_free() settle

	battle._check_victory()
	assert_true(battle._ended,
		"a team whose units are truly gone (not merely routing) still loses the battle")
