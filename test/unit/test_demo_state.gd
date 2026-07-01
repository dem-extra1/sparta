extends GutTest
## Pure serialization for the scripted-input demo state-dump path (tools/demo/DemoState.gd).
## The enum-name mapping and the per-soldier summary are functions of their arguments only —
## no recorder/battle instance — so they're directly unit-testable like DemoFrames. The live
## dump (walking the units, writing JSON) reads a running battle and is verified by dumping a
## demo, not headlessly here.


# --- enum name mapping -----------------------------------------------------

func test_state_name_maps_each_enum_member() -> void:
	assert_eq(DemoState.state_name(0), "IDLE")
	assert_eq(DemoState.state_name(1), "MOVING")
	assert_eq(DemoState.state_name(2), "FIGHTING")
	assert_eq(DemoState.state_name(3), "ROUTING")
	assert_eq(DemoState.state_name(4), "DEAD")


func test_state_name_unknown_int_is_visible_token() -> void:
	assert_eq(DemoState.state_name(9), "STATE(9)",
		"an out-of-range state surfaces as a greppable token, not a dropped field")


func test_formation_name_maps_each_member() -> void:
	assert_eq(DemoState.formation_name(0), "NORMAL")
	assert_eq(DemoState.formation_name(1), "TIGHT")
	assert_eq(DemoState.formation_name(2), "LOOSE")
	assert_eq(DemoState.formation_name(3), "SQUARE")
	assert_eq(DemoState.formation_name(4), "SHIELD_WALL")
	assert_eq(DemoState.formation_name(5), "TESTUDO")


func test_formation_name_unknown_int_is_visible_token() -> void:
	assert_eq(DemoState.formation_name(9), "FORMATION(9)")


func test_order_mode_name_uses_supplied_table() -> void:
	var names := {0: "Normal", 1: "Hold"}
	assert_eq(DemoState.order_mode_name(names, 1), "Hold")


func test_order_mode_name_unknown_int_is_visible_token() -> void:
	assert_eq(DemoState.order_mode_name({0: "Normal"}, 5), "MODE(5)")


# --- rounding / vector formatting ------------------------------------------

func test_round_to_default_two_places() -> void:
	assert_almost_eq(DemoState.round_to(1.23456), 1.23, 0.0001)


func test_round_to_one_place() -> void:
	assert_almost_eq(DemoState.round_to(25.34, 1), 25.3, 0.0001)


func test_vec2_pair_rounds_both_components() -> void:
	var pair: Array = DemoState.vec2_pair(Vector2(1.23456, -7.891))
	assert_eq(pair.size(), 2)
	assert_almost_eq(pair[0], 1.23, 0.0001)
	assert_almost_eq(pair[1], -7.89, 0.0001)


# --- per-soldier summary ---------------------------------------------------

func test_soldier_summary_empty_is_zeroed() -> void:
	var s: Dictionary = DemoState.soldier_summary(PackedVector2Array(), PackedFloat32Array())
	assert_eq(s["count"], 0)
	assert_eq(s["centroid"], [0.0, 0.0])
	assert_eq(s["bbox"], [0.0, 0.0])
	assert_eq(s["prone_count"], 0, "a routed/empty unit still serializes without error")


func test_soldier_summary_centroid_and_bbox() -> void:
	# A 10x4 box: corners at (0,0),(10,0),(0,4),(10,4). Centroid (5,2); bbox 10 wide, 4 tall.
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 4), Vector2(10, 4)])
	var s: Dictionary = DemoState.soldier_summary(pos, PackedFloat32Array())
	assert_eq(s["count"], 4)
	assert_almost_eq(s["centroid"][0], 5.0, 0.0001)
	assert_almost_eq(s["centroid"][1], 2.0, 0.0001)
	assert_almost_eq(s["bbox"][0], 10.0, 0.0001)
	assert_almost_eq(s["bbox"][1], 4.0, 0.0001)


func test_soldier_summary_counts_prone() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	# prone > 0 means down: index 0 and 2 prone, index 1 standing.
	var prone := PackedFloat32Array([0.5, 0.0, 1.2])
	var s: Dictionary = DemoState.soldier_summary(pos, prone)
	assert_eq(s["prone_count"], 2, "counts soldiers with a nonzero prone timer")


func test_soldier_summary_shorter_prone_array_is_safe() -> void:
	# A prone array shorter than the positions (index-aligned but truncated) must not overrun.
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	var prone := PackedFloat32Array([1.0])   # only index 0
	var s: Dictionary = DemoState.soldier_summary(pos, prone)
	assert_eq(s["count"], 3)
	assert_eq(s["prone_count"], 1, "missing prone entries treated as standing, no out-of-range read")
