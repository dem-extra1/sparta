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


func test_rejects_degenerate_polygon() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["polygon"] = [[0, 0], [1, 1]]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "polygon with < 3 points -> rejected")


func test_rejects_malformed_polygon_point() -> void:
	var raw := _valid_raw()
	# A non-[x,y] vertex invalidates the polygon (no silent (0,0) substitution).
	raw["provinces"][0]["polygon"] = [[0, 0], [10, 0], "bad"]
	assert_true(CampaignLoader.parse_map(raw).is_empty(), "a malformed polygon point -> rejected")


func test_loads_real_gallic_war_file() -> void:
	var m := CampaignLoader.load_map(Campaigns.DEFAULT_PATH)
	assert_false(m.is_empty(), "the shipped Gallic War map loads")
	assert_eq(m["name"], "Gallic War")
	assert_eq(m["provinces"].size(), 7, "7 provinces")
	assert_eq(m["faction_names"].size(), 2)


func test_load_missing_file_returns_empty() -> void:
	assert_true(CampaignLoader.load_map("res://data/campaigns/does_not_exist.json").is_empty(),
			"a missing file loads as empty (caller falls back)")
