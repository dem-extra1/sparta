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


# --- diplomacy (#123) ------------------------------------------------------

func test_factions_at_war_by_default() -> void:
	var s := _state()
	assert_true(s.at_war(ROME, GAULS), "a war campaign starts with the factions at war")
	assert_true(s.at_war(GAULS, ROME), "stance is symmetric")
	assert_false(s.at_war(ROME, ROME), "a faction is never at war with itself")


func test_make_peace_then_declare_war() -> void:
	var s := _state()
	s.make_peace(ROME, GAULS)
	assert_false(s.at_war(ROME, GAULS), "make_peace ends the war")
	assert_false(s.at_war(GAULS, ROME), "...symmetrically")
	s.declare_war(GAULS, ROME)
	assert_true(s.at_war(ROME, GAULS), "declare_war (order-independent) restores the war")


func test_cannot_enter_a_faction_at_peace() -> void:
	var s := _state()
	assert_true(s.can_move(0, 1), "at war: Rome can attack the Gallic P1")
	assert_true(s.can_move(0, 2), "at war: Rome can occupy the undefended Gallic P2")
	s.make_peace(ROME, GAULS)
	assert_false(s.can_move(0, 1), "at peace: entering their province is not allowed")
	assert_false(s.can_move(0, 2),
			"at peace: even an undefended enemy province is blocked (gate fires before occupy)")
	# Peace doesn't block reinforcing your own province.
	var m := _map()
	m["provinces"][1]["owner"] = ROME
	var s2 := CampaignState.new(m, 1)
	s2.make_peace(ROME, GAULS)
	assert_true(s2.can_move(0, 1), "reinforcing your own province is always allowed")
	# Declaring war re-opens the attack.
	s.declare_war(ROME, GAULS)
	assert_true(s.can_move(0, 1), "after declaring war the attack is legal again")


func test_move_or_attack_blocked_by_peace() -> void:
	var s := _state()
	s.make_peace(ROME, GAULS)
	var r: Dictionary = s.move_or_attack(0, 1)
	assert_false(r["ok"], "an at-peace move is rejected by move_or_attack's can_move guard")
	assert_eq(s.owner_of(1), GAULS, "the target is untouched")
	assert_eq(s.army_of(0), 5, "and the mover keeps its army")


func test_initial_peace_from_map() -> void:
	# A map may seed starting stances; everything not listed stays at war.
	var m := _map()
	m["peace"] = [[ROME, GAULS]]
	var s := CampaignState.new(m, 1)
	assert_false(s.at_war(ROME, GAULS), "a map-listed pair starts at peace")


func test_result_reports_defender_owner() -> void:
	var s := _state()
	var r: Dictionary = s.move_or_attack(0, 1)
	assert_true(r["ok"])
	assert_eq(int(r["defender_owner"]), GAULS, "the result records who held the target before the move")
