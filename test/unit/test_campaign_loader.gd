extends GutTest
## CampaignLoader (#125): parse_map() validation/conversion in isolation, plus a
## load of the real Gallic War data file. An invalid map returns {} (empty) so the
## caller can fall back.

const CampaignLoader = preload("res://scripts/campaign/CampaignLoader.gd")
const Campaigns = preload("res://scripts/campaign/Campaigns.gd")


func _valid_raw() -> Dictionary:
	return {
		"name": "Test War",
		"factions": [{"name": "A", "color": "#ff0000"}, {"name": "B"}],
		"provinces": [
			{"id": 0, "name": "P0", "owner": 0, "army": 3, "adj": [1],
				"polygon": [[0, 0], [10, 0], [10, 10], [0, 10]], "label": [5, 5]},
			{"id": 1, "name": "P1", "owner": 1, "army": 2, "adj": [0],
				"polygon": [[20, 0], [30, 0], [30, 10]]},
		],
	}


func test_parse_valid_map() -> void:
	var m := CampaignLoader.parse_map(_valid_raw())
	assert_false(m.is_empty(), "a well-formed map parses")
	assert_eq(m["name"], "Test War")
	assert_eq(m["faction_names"], ["A", "B"] as Array[String])
	assert_eq(m["faction_colors"][0], Color("#ff0000"), "hex colour parsed")
	assert_eq(m["faction_colors"][1], CampaignLoader.DEFAULT_FACTION_COLOR, "missing colour -> default")
	assert_eq(m["provinces"].size(), 2)
	var p0: Dictionary = m["provinces"][0]
	assert_true(p0["polygon"] is PackedVector2Array, "polygon converted to PackedVector2Array")
	assert_eq(p0["label"], Vector2(5, 5), "explicit label parsed")


func test_missing_label_defaults_to_centroid() -> void:
	var m := CampaignLoader.parse_map(_valid_raw())
	var p1: Dictionary = m["provinces"][1]
	# Centroid of (20,0),(30,0),(30,10) = (26.67, 3.33)
	assert_almost_eq(p1["label"].x, 26.667, 0.01, "label falls back to the polygon centroid")
	assert_almost_eq(p1["label"].y, 3.333, 0.01)


func test_rejects_empty_factions() -> void:
	var raw := _valid_raw()
	raw["factions"] = []
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "no factions -> rejected")


func test_rejects_missing_province_key() -> void:
	var raw := _valid_raw()
	raw["provinces"][0].erase("army")
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "missing required key -> rejected")


func test_rejects_duplicate_ids() -> void:
	var raw := _valid_raw()
	raw["provinces"][1]["id"] = 0
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "duplicate id -> rejected")


func test_rejects_owner_out_of_range() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["owner"] = 5
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "owner outside faction range -> rejected")


func test_rejects_unknown_neighbour() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["adj"] = [99]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "adjacency to a missing id -> rejected")


func test_rejects_asymmetric_adjacency() -> void:
	var raw := _valid_raw()
	# P0 lists P1 as a neighbour but P1 does not list P0 -> one-way edge.
	raw["provinces"][1]["adj"] = []
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "asymmetric adjacency -> rejected")


func test_rejects_degenerate_polygon() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["polygon"] = [[0, 0], [1, 1]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "polygon with < 3 points -> rejected")


func test_rejects_malformed_polygon_point() -> void:
	var raw := _valid_raw()
	# A non-[x,y] vertex invalidates the polygon (no silent (0,0) substitution).
	raw["provinces"][0]["polygon"] = [[0, 0], [10, 0], "bad"]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "a malformed polygon point -> rejected")


func test_parses_peace_pairs() -> void:
	var raw := _valid_raw()
	raw["peace"] = [[0, 1]]
	var m := CampaignLoader.parse_map(raw)
	assert_false(m.is_empty(), "a valid peace pair parses")
	assert_eq(m["peace"], [[0, 1]], "peace pairs are carried through")


func test_peace_defaults_to_empty() -> void:
	var m := CampaignLoader.parse_map(_valid_raw())
	assert_eq(m["peace"], [], "no 'peace' key -> empty list (everyone at war)")


func test_rejects_peace_with_unknown_faction() -> void:
	var raw := _valid_raw()
	raw["peace"] = [[0, 9]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "peace referencing a missing faction -> rejected")


func test_rejects_malformed_peace_pair() -> void:
	var raw := _valid_raw()
	raw["peace"] = [[0]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "a peace entry that isn't a pair -> rejected")


func test_rejects_self_peace_pair() -> void:
	var raw := _valid_raw()
	raw["peace"] = [[0, 0]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "a faction at peace with itself -> rejected (likely a typo)")


func test_rejects_duplicate_peace_pair() -> void:
	var raw := _valid_raw()
	raw["peace"] = [[0, 1], [1, 0]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "a duplicate peace pair (even reversed) -> rejected")


func test_loads_real_gallic_war_file() -> void:
	var m := CampaignLoader.load_map(Campaigns.DEFAULT_PATH)
	assert_false(m.is_empty(), "the shipped Gallic War map loads")
	assert_eq(m["name"], "Gallic War")
	assert_eq(m["provinces"].size(), 9, "9 provinces (7 Gallic War + 2 Germanic)")
	assert_eq(m["faction_names"].size(), 3, "Rome, Gauls, Germanic tribes")
	# The Germanic tribes (faction 2) start at peace with both belligerents.
	assert_eq(m["peace"], [[0, 2], [1, 2]], "neutral faction's starting peace is loaded")


func test_real_gallic_war_adjacency_is_mutual() -> void:
	# Movement is two-way, so every listed neighbour must list us back. Guards against
	# hand-edit typos in the shipped map (the general validator is tracked in #128).
	var m := CampaignLoader.load_map(Campaigns.DEFAULT_PATH)
	assert_false(m.is_empty(), "gallic war must load for this test to be meaningful")
	var adj := {}
	for p in m["provinces"]:
		adj[int(p["id"])] = p["adj"]
	for id in adj:
		for n in adj[id]:
			assert_true(adj.has(n) and id in adj[n],
					"province %d <-> %d adjacency must be mutual" % [id, n])


func test_load_missing_file_returns_empty() -> void:
	assert_true(CampaignLoader.load_map("res://data/campaigns/does_not_exist.json").is_empty(),
			"a missing file loads as empty (caller falls back)")
