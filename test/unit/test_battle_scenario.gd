extends GutTest
## Demo scenario staging: a Battle spawned with a custom `scenario` list deploys exactly
## those units (type, team, position, and count/morale/facing overrides) instead of the
## default two-line spawn. Tooling only -- the demo recorder sets `scenario` before the
## battle enters the tree; a normal battle leaves it empty and spawns the default lines.
##
## Standing up the full Battle scene is heavy, so everything is asserted from ONE spawn of a
## rich multi-unit scenario. (The empty-scenario = default two-line path is already covered
## by test_battle_drill and test_battle_spawn_formation, which spawn the default battle.)


func test_scenario_spawns_exactly_its_units_with_types_positions_and_overrides() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		# A spearman with every override: count, morale, and an explicit facing that must win
		# over the team default.
		{"team": 0, "type": "Spearmen", "x": 500, "y": 250, "count": 40, "morale": 30.0, "facing": [1, 0]},
		# A plain enemy cavalry unit: no facing override, so it takes the team-1 default (up).
		{"team": 1, "type": "Cavalry", "x": 500, "y": 750},
		# A second enemy cavalry with a MALFORMED facing (one element): must fall back to the
		# team default rather than crash, and its label must read "Cavalry 2" (per-type index).
		{"team": 1, "type": "Cavalry", "x": 700, "y": 750, "facing": [1]},
	]
	add_child_autofree(battle)
	await get_tree().physics_frame

	var team0: Array = []
	var team1: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		if unit.team == 0:
			team0.append(unit)
		elif unit.team == 1:
			team1.append(unit)

	# Exactly the listed units -- not the default 5-per-side lines.
	assert_eq(team0.size(), 1, "exactly the one listed team-0 unit spawns (not the default line)")
	assert_eq(team1.size(), 2, "exactly the two listed team-1 units spawn")
	if team0.is_empty() or team1.size() < 2:
		return

	var spear: Unit = team0[0]
	assert_true(spear.anti_cavalry, "type 'Spearmen' maps onto the spearmen loadout (anti-cavalry)")
	assert_almost_eq(spear.position.x, 500.0, 0.5, "the unit spawns at the spec's x")
	assert_almost_eq(spear.position.y, 250.0, 0.5, "and its y")
	assert_eq(spear.max_soldiers, 40, "the count override sets max_soldiers")
	assert_eq(spear.soldiers, 40, "and _ready() seeds the live soldier count from it")
	assert_almost_eq(spear.morale, 30.0, 0.001, "the morale override sets the starting morale")
	assert_almost_eq(spear.facing.x, 1.0, 0.001, "the explicit facing vector wins over the team default (x)")
	assert_almost_eq(spear.facing.y, 0.0, 0.001, "...and y")

	for horse: Unit in team1:
		assert_true(horse.is_cavalry, "type 'Cavalry' maps onto the cavalry loadout")
		# The first cavalry has no facing override, the second has a MALFORMED one -- both must
		# fall back to the team-1 default (facing up), and neither may crash on the bad array.
		assert_almost_eq(horse.facing.y, -1.0, 0.001,
			"an enemy with no / a malformed facing override defaults to facing up (no crash)")

	# Labels are numbered per type, not across all teams: the two cavalry read "Cavalry 1" and
	# "Cavalry 2" (not "Cavalry 2"/"Cavalry 3" offset by the team-0 spearman).
	var cav_labels := [str(team1[0].unit_name), str(team1[1].unit_name)]
	cav_labels.sort()
	assert_eq(cav_labels, ["Cavalry 1", "Cavalry 2"],
		"unit labels are numbered per type, so cross-team spawns still read 1, 2 within a type")
