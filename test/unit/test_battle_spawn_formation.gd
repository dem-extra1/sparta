extends GutTest
## Spawn-time formation defaults: each loadout type's `formation` field sets its
## starting Tight/Normal/Loose density (still just a starting point -- every unit
## can cycle through all three live with the T hotkey). Spearmen brace tight
## against a charge, archers start loose, and swords/cavalry start at plain
## combat order.


func test_units_spawn_with_their_type_default_formation() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	var seen_by_name: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null or unit.team != 0:
			continue
		# unit_name is "<TypeName> <index>" -- take the type prefix (anti-cavalry
		# and ranged flags don't uniquely distinguish every future subtype, but the
		# name-to-formation mapping only needs to hold for the current loadout).
		var type_name: String = unit.unit_name.split(" ")[0]
		if not seen_by_name.has(type_name):
			seen_by_name[type_name] = unit.formation_mode

	assert_eq(seen_by_name.get("Spearmen"), Unit.FORMATION_TIGHT,
		"spearmen default to tight -- locked shields against a charge")
	assert_eq(seen_by_name.get("Infantry"), Unit.FORMATION_NORMAL,
		"sword-armed infantry default to plain combat order")
	assert_eq(seen_by_name.get("Archers"), Unit.FORMATION_LOOSE,
		"archers default to loose -- room to fire, less to lose from spreading out")
	assert_eq(seen_by_name.get("Cavalry"), Unit.FORMATION_NORMAL,
		"cavalry default to plain combat order")
