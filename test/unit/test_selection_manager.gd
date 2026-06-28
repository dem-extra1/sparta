extends GutTest
## SelectionManager order-overlay helpers: the SUPPORT-ward resolution that
## decides whether the hold-Space overlay draws a supporter→ward link. The drawing
## itself is visual, but the ward-validity guard is pure logic and worth pinning.
## (The freed-instance `is_instance_valid(ward) == false` path isn't exercised — it
## needs a queue_free() plus a frame await, awkward in GUT; the alive/none/dead/
## routing/self cases below cover the rest of the guard.)

const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const BattleScript = preload("res://scripts/Battle.gd")

# Snapshot/restore the global Settings hotkeys around tests that rebind them,
# so a rebinding test can't leak into others or the real user://settings.cfg.
var _orig_bindings: Dictionary


func before_each() -> void:
	_orig_bindings = Settings.order_bindings.duplicate()


func after_each() -> void:
	Settings.order_bindings = _orig_bindings.duplicate()


func _sm() -> Node2D:
	var sm = SelectionManagerScript.new()
	add_child_autofree(sm)   # runs _ready(): only sets z_index / process_mode
	return sm


func _unit() -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	return u


func test_support_ward_resolves_a_valid_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	assert_eq(sm._support_ward_of(u), ward, "a live ward is returned for the overlay link")


func test_support_ward_is_null_without_a_ward() -> void:
	var sm := _sm()
	var u := _unit()
	assert_null(sm._support_ward_of(u), "no ward -> nothing to draw")


func test_support_ward_skips_a_dead_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.DEAD
	assert_null(sm._support_ward_of(u), "a dead ward is not drawn")


func test_support_ward_skips_a_routing_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.ROUTING
	assert_null(sm._support_ward_of(u), "a routing ward is not drawn")


func test_support_ward_skips_self() -> void:
	# Parity with UnitTargeting.support_valid's self-guard check. Battle never issues a
	# self-guard order, but the helper rejects it so the two stay in lockstep.
	var sm := _sm()
	var u := _unit()
	u.support_target = u
	assert_null(sm._support_ward_of(u), "a unit can't guard itself")


# --- order-mode hotkeys read from Settings ---------------------------

func test_selector_reads_rebound_key_from_settings() -> void:
	var sm := _sm()
	assert_eq(sm._order_mode_for_keycode(KEY_H), BattleScript.OrderMode.HOLD,
		"the default H arms Hold")
	assert_eq(sm._order_mode_for_keycode(KEY_Z), -1, "Z is unbound by default")
	# Rebind Hold to Z in-memory (after_each restores the global bindings).
	Settings.order_bindings["hold"] = KEY_Z
	assert_eq(sm._order_mode_for_keycode(KEY_Z), BattleScript.OrderMode.HOLD,
		"after rebinding, Z arms Hold")
	assert_eq(sm._order_mode_for_keycode(KEY_H), -1,
		"and the old default H no longer arms anything")


func test_escape_clears_stance_regardless_of_bindings() -> void:
	var sm := _sm()
	assert_eq(sm._order_mode_for_keycode(KEY_ESCAPE), BattleScript.OrderMode.NORMAL,
		"Esc always clears the stance — it's fixed, not rebindable")


# --- demo order overlay gating ---------------------------------------

func test_demo_orders_active_only_during_playback_with_the_flag() -> void:
	# The order overlay shows without a held key only when the demo recorder is
	# replaying with show_demo_orders set; in-app Watch Replay (flag off) and live
	# play keep it on the Space-held survey.
	var sm := _sm()
	var prev_mode = Replay.mode
	var prev_flag := Replay.show_demo_orders
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.show_demo_orders = true
	assert_true(sm._demo_orders_active(), "active during demo playback with the flag set")
	Replay.show_demo_orders = false
	assert_false(sm._demo_orders_active(), "off in Watch Replay (playback, flag clear)")
	Replay.mode = Replay.Mode.RECORD
	Replay.show_demo_orders = true
	assert_false(sm._demo_orders_active(), "off when not in playback")
	Replay.mode = prev_mode
	Replay.show_demo_orders = prev_flag


# --- demo pointer capture --------------------------------------------

func test_pointer_state_reports_live_selection_drag_and_stance() -> void:
	# The recorder samples this each tick; it must report the armed stance, the drag-box
	# state, and the selected units' uids (alive only).
	var sm := _sm()
	var u := _unit()
	u.uid = 7
	var dead := _unit()
	dead.uid = 9
	dead.state = UnitScript.State.DEAD
	sm._selected = [u, dead]
	sm._dragging = true
	sm._drag_start = Vector2(12, 34)
	sm._armed_mode = BattleScript.OrderMode.SKIRMISH

	sm.set_cursor_override(Vector2(640, 480))
	var ps: Dictionary = sm.pointer_state()
	assert_eq(ps["cursor"], Vector2(640, 480), "an injected cursor is reported as the cursor")
	assert_eq(ps["selection"], [7], "only living selected units' uids are reported")
	# Clearing the override returns to the live mouse, so the injected value no longer shows.
	sm.set_cursor_override(null)
	assert_ne(sm.pointer_state()["cursor"], Vector2(640, 480),
			"clearing the override falls back to the live OS mouse")
	assert_true(ps["dragging"], "the open drag-box is reported")
	assert_eq(ps["drag_start"], Vector2(12, 34), "the drag start corner is reported")
	assert_eq(ps["mode"], BattleScript.OrderMode.SKIRMISH, "the armed stance is reported")


# --- frontage resize handles (#266) ----------------------------

func test_file_axis_is_perpendicular_to_facing() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN   # forward is +Y, so the width axis is horizontal
	var axis: Vector2 = sm._file_axis(u)
	assert_almost_eq(axis.y, 0.0, 0.001, "a down-facing unit's file axis is horizontal")
	assert_almost_eq(absf(axis.x), 1.0, 0.001, "and is a unit vector")


func test_resize_handles_straddle_the_unit_along_the_file_axis() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN
	u.position = Vector2(100, 100)
	var hs: Array = sm._resize_handle_positions(u)
	assert_eq(hs.size(), 2, "two grips, one per flank")
	# Symmetric about the unit centre.
	var mid: Vector2 = (hs[0] + hs[1]) * 0.5
	assert_almost_eq(mid.distance_to(u.global_position), 0.0, 0.001,
			"the grips are centred on the unit")
	assert_gt(hs[0].distance_to(hs[1]), 0.0, "the grips are separated across the line")


func test_single_selected_unit_requires_exactly_one() -> void:
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	assert_null(sm._single_selected_unit(), "nothing selected -> no resize target")
	sm._select(a)
	assert_eq(sm._single_selected_unit(), a, "one selected unit is the resize target")
	sm._select(c)
	assert_null(sm._single_selected_unit(), "a multi-selection shows no single-unit grips")


func test_resize_handle_at_grabs_a_grip_and_ignores_empty_space() -> void:
	var sm := _sm()
	var u := _unit()
	u.facing = Vector2.DOWN
	u.position = Vector2(50, 50)
	sm._select(u)
	var grip: Vector2 = sm._resize_handle_positions(u)[0]
	assert_eq(sm._resize_handle_at(grip), u, "a cursor on a grip grabs that unit for resizing")
	assert_null(sm._resize_handle_at(u.global_position + Vector2(9999, 0)),
			"a cursor far from any grip grabs nothing")


func test_resize_frontage_routes_an_absolute_command_to_battle() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 5
	u.max_soldiers = 80
	b._by_uid[5] = u
	var start: int = UnitFormation.frontage(u)
	sm._select(u)
	sm._resize_frontage(1)
	assert_eq(UnitFormation.frontage(u), start + 1, "the keyboard widen steps the line out one file")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_FRONTAGE_ONLY,
			"routed as a recorded frontage command")
