extends GutTest
## Campaign-map rules (#70): exercises CampaignState directly (pure logic, no scene)
## with small hand-made maps. Geometry (polygons/labels) is omitted — CampaignState
## reads only owner/army/adj/name.

const CampaignState = preload("res://scripts/campaign/CampaignState.gd")

const ROME := 0
const GAULS := 1


func _map() -> Dictionary:
	# 0 (Rome, army 5) — 1 (Gauls, army 3) — 2 (Gauls, undefended). All mutually adjacent.
	return {
		"faction_names": ["Rome", "Gauls"],
		"provinces": [
			{"id": 0, "name": "P0", "owner": ROME, "army": 5, "adj": [1, 2]},
			{"id": 1, "name": "P1", "owner": GAULS, "army": 3, "adj": [0, 2]},
			{"id": 2, "name": "P2", "owner": GAULS, "army": 0, "adj": [0, 1]},
		],
	}


func _state(seed_val: int = 1) -> RefCounted:
	return CampaignState.new(_map(), seed_val)


func test_build_from_map() -> void:
	var s := _state()
	assert_eq(s.provinces.size(), 3, "all provinces loaded")
	assert_eq(s.owner_of(0), ROME)
	assert_eq(s.army_of(1), 3)
	assert_eq(s.faction_names, ["Rome", "Gauls"] as Array[String])
	assert_eq(s.current_faction, ROME, "Rome moves first")
	assert_eq(s.turn, 1)


func test_adjacency() -> void:
	var s := _state()
	assert_true(s.are_adjacent(0, 1))
	assert_true(s.are_adjacent(1, 2))
	assert_false(s.are_adjacent(0, 99), "unknown province is not adjacent")


func test_can_move_rules() -> void:
	var s := _state()
	assert_true(s.can_move(0, 1), "own, manned, adjacent army can move")
	assert_false(s.can_move(1, 0), "can't move an enemy faction's army on Rome's turn")
	assert_false(s.can_move(0, 0), "can't move onto itself")
	# Province 2 has no army of Rome's; and Rome doesn't own it.
	assert_false(s.can_move(2, 0), "an unowned/empty province can't move")


func test_move_into_undefended_occupies() -> void:
	var s := _state()
	var r: Dictionary = s.move_or_attack(0, 2)
	assert_true(r["ok"])
	assert_false(r["combat"], "no fight against an undefended province")
	assert_false(r["reinforced"], "occupying an enemy province isn't a reinforce")
	assert_eq(s.owner_of(2), ROME, "province changes hands")
	assert_eq(s.army_of(2), 5, "the whole army garrisons it")
	assert_eq(s.army_of(0), 0, "origin is left empty")
	assert_true(s.has_acted(2), "the moved army has acted this turn")
	assert_false(s.can_move(2, 1), "and can't move again until next turn")


func test_reinforce_friendly_merges() -> void:
	var m := _map()
	m["provinces"][1]["owner"] = ROME   # make P1 a friendly neighbour with an army
	var s := CampaignState.new(m, 1)
	var r: Dictionary = s.move_or_attack(0, 1)
	assert_true(r["ok"])
	assert_false(r["combat"])
	assert_true(r["reinforced"], "reinforce sets the flag _announce reads")
	assert_eq(s.army_of(1), 8, "stacks merge (5 + 3)")
	assert_eq(s.army_of(0), 0)


func test_strong_attacker_conquers() -> void:
	var m := _map()
	m["provinces"][0]["army"] = 20   # overwhelming attacker vs P1's 3
	var s := CampaignState.new(m, 7)
	var r: Dictionary = s.move_or_attack(0, 1)
	assert_true(r["ok"] and r["combat"], "a defended province triggers a fight")
	assert_true(r["attacker_won"], "20 vs 3 is a near-certain win")
	assert_eq(s.owner_of(1), ROME, "the province is taken")
	assert_eq(s.army_of(0), 0, "the attacking army left its origin")
	assert_true(s.army_of(1) >= 1, "at least one attacker survives to hold it")


func test_strong_defender_repels() -> void:
	var m := _map()
	m["provinces"][1]["army"] = 50   # hopeless attack by Rome's 5
	var s := CampaignState.new(m, 7)
	var r: Dictionary = s.move_or_attack(0, 1)
	assert_true(r["ok"] and r["combat"])
	assert_false(r["attacker_won"], "5 vs 50 should fail")
	assert_eq(s.owner_of(1), GAULS, "defender keeps the province")
	assert_eq(s.army_of(0), 0, "the attacking army is spent")


func test_end_turn_cycles_factions_and_clears_acted() -> void:
	var s := _state()
	s.move_or_attack(0, 2)
	assert_true(s.has_acted(2))
	s.end_turn()
	assert_eq(s.current_faction, GAULS, "play passes to the Gauls")
	assert_eq(s.turn, 1, "turn counter only advances when it wraps to faction 0")
	assert_false(s.has_acted(2), "acted flags reset for the new faction")
	s.end_turn()
	assert_eq(s.current_faction, ROME, "and back to Rome")
	assert_eq(s.turn, 2, "a full round increments the turn")


func test_winner_detection() -> void:
	var s := _state()
	assert_eq(s.winner(), CampaignState.NO_WINNER, "war is undecided at the start")
	for id in s.provinces:
		s.provinces[id]["owner"] = ROME
	assert_eq(s.winner(), ROME, "owning every province wins the war")


func test_movable_provinces_excludes_empty_and_acted() -> void:
	var s := _state()
	assert_eq(s.movable_provinces(ROME), [0] as Array[int], "only Rome's manned P0")
	assert_eq(s.movable_provinces(GAULS), [1] as Array[int], "Gauls' P1 (P2 is empty)")
	s.move_or_attack(0, 2)
	assert_true(s.has_acted(2), "the army now sits in P2 and has acted")
	assert_eq(s.movable_provinces(ROME), [] as Array[int],
			"so Rome has no army left to move this turn")
