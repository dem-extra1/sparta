extends GutTest
## Smoke test for the campaign scene (#70): instantiates Campaign.tscn so _ready,
## the CampaignMap/CampaignHUD signal wiring, and a click→move→end-turn round all run
## without error. Complements test_campaign_state.gd (which covers the rules in
## isolation) by exercising the Node/scene layer.

const CampaignScene = preload("res://scenes/Campaign.tscn")
const CampaignLoader = preload("res://scripts/campaign/CampaignLoader.gd")
const Campaigns = preload("res://scripts/campaign/Campaigns.gd")


# A point guaranteed inside the polygon: the centroid of one triangle from its
# triangulation lies within that triangle, hence within the polygon. (The vertex
# average can fall outside a concave polygon.)
func _interior_point(poly: PackedVector2Array) -> Vector2:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.size() >= 3:
		return (poly[tris[0]] + poly[tris[1]] + poly[tris[2]]) / 3.0
	var sum := Vector2.ZERO   # degenerate fallback
	for v in poly:
		sum += v
	return sum / poly.size()


# province id -> a point guaranteed inside its polygon.
func _centroids() -> Dictionary:
	var out := {}
	for p in CampaignLoader.load_map(Campaigns.DEFAULT_PATH)["provinces"]:
		out[int(p["id"])] = _interior_point(p["polygon"])
	return out


func _scene() -> Node:
	var s := CampaignScene.instantiate()
	add_child_autofree(s)   # runs _ready on CampaignMap + CampaignHUD
	# CampaignMap builds its state synchronously but defers the first HUD refresh
	# (its _ready runs before the sibling HUD's); let that deferred call run first.
	await get_tree().process_frame
	return s


func test_scene_comes_up() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_not_null(map._state, "campaign state is built on _ready")
	assert_eq(map._state.provinces.size(), 7, "the Gallic War map has 7 provinces")
	assert_eq(map._state.current_faction, 0, "Rome (player) moves first")
	assert_eq(map._selected, -1, "nothing selected initially")


func test_click_selects_then_orders() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var c := _centroids()

	# Click a Roman, manned province (Narbonensis = id 0) -> it becomes selected.
	map._on_click(c[0])
	assert_eq(map._selected, 0, "clicking your own army selects it")

	# Click adjacent Gallic Helvetia (id 6) -> issues a move/attack, clears selection.
	var before_owner: int = map._state.owner_of(6)
	map._on_click(c[6])
	assert_eq(map._selected, -1, "issuing an order clears the selection")
	assert_eq(map._state.army_of(0), 0, "the ordered army left its origin")
	# Either it was taken (owner flips) or the assault failed (still Gallic) — both fine,
	# we only assert the order resolved without error and consumed the army.
	assert_true(map._state.owner_of(6) == 0 or map._state.owner_of(6) == before_owner,
			"the order resolved to a valid outcome")


func test_falls_back_to_default_when_selected_missing() -> void:
	# An unreadable selected campaign must fall back to the default, not crash.
	Campaigns.selected_path = "res://data/campaigns/__does_not_exist__.json"
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_eq(map._state.provinces.size(), 7, "fell back to the default Gallic War map")
	Campaigns.selected_path = Campaigns.DEFAULT_PATH   # restore for other tests


func test_restart_re_enables_end_turn() -> void:
	# Regression: show_victory disables End Turn; restarting must re-enable it and
	# clear the end overlay, or "New Campaign" leaves an unplayable board.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	hud.show_victory("test")
	assert_true(hud._end_turn_button.disabled, "End Turn is disabled at game over")
	map._restart()
	assert_false(hud._end_turn_button.disabled, "restarting re-enables End Turn")
	assert_false(hud._overlay.visible, "and hides the end overlay")


func test_end_turn_runs_enemy_and_returns_to_player() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	map._on_end_turn()
	# Unless the AI somehow won outright (it can't from the start position), play
	# returns to Rome and the turn counter advances.
	if map._state.winner() == -1:
		assert_eq(map._state.current_faction, 0, "play returns to the player")
		assert_eq(map._state.turn, 2, "a full round advances the turn")
