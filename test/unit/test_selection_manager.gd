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
var _orig_form_up_default: int
var _orig_form_up_cycle: Array
var _orig_reform_before_move: bool
var _orig_show_unit_speed: bool


func before_each() -> void:
	_orig_bindings = Settings.order_bindings.duplicate()
	_orig_form_up_default = Settings.form_up_dist_default
	_orig_form_up_cycle = Settings.form_up_dist_cycle.duplicate()
	_orig_reform_before_move = Settings.reform_before_move
	_orig_show_unit_speed = Settings.show_unit_speed
	# Pin the default cycle; a developer's persisted cfg can deviate and break these tests locally.
	Settings.form_up_dist_cycle = [EQUAL_DEPTH, EQUAL_WIDTH]


func after_each() -> void:
	Settings.order_bindings = _orig_bindings.duplicate()
	Settings.form_up_dist_default = _orig_form_up_default
	Settings.form_up_dist_cycle = _orig_form_up_cycle.duplicate()
	Settings.reform_before_move = _orig_reform_before_move
	Settings.show_unit_speed = _orig_show_unit_speed


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


# --- order-overlay unit-speed label (#444) -----------------------------------

func test_unit_speed_label_is_empty_when_toggle_off() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = false
	u._current_speed = 52.0
	assert_eq(sm._unit_speed_label(u), "", "no label when the toggle is off, whatever the speed")


func test_unit_speed_label_reports_metres_per_second_when_on() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = true
	# 52 world units/s at 20 u/m, speed_scale 1.0 -> 2.6 m/s.
	u._current_speed = 52.0
	assert_eq(sm._unit_speed_label(u), "2.6 m/s", "the live speed converts back to the loadout's m/s")


func test_unit_speed_label_reads_zero_for_a_halted_unit() -> void:
	var sm := _sm()
	var u := _unit()
	Settings.show_unit_speed = true
	u._current_speed = 0.0
	assert_eq(sm._unit_speed_label(u), "0.0 m/s", "a stationary unit reads 0.0 m/s")


# --- order-overlay distance label: route length (#413) -----------------------

func test_route_length_single_leg_is_the_straight_distance() -> void:
	var sm := _sm()
	var route: Array[Vector2] = [Vector2(300, 0)]
	assert_almost_eq(sm._route_length(Vector2.ZERO, route), 300.0, 0.0001,
		"a single-destination move is the straight origin->target distance")


func test_route_length_sums_each_leg_of_a_waypoint_route() -> void:
	var sm := _sm()
	# Origin (0,0) -> (300,0) -> (300,400): legs of 300 and 400 -> 700, not the 500
	# straight-line origin->destination. The label must report the real march.
	var route: Array[Vector2] = [Vector2(300, 0), Vector2(300, 400)]
	assert_almost_eq(sm._route_length(Vector2.ZERO, route), 700.0, 0.0001,
		"a multi-waypoint route sums its legs, exceeding the straight-line distance")


func test_route_length_of_an_empty_route_is_zero() -> void:
	var sm := _sm()
	var route: Array[Vector2] = []
	assert_eq(sm._route_length(Vector2.ZERO, route), 0.0, "no points -> no distance")


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


# --- frontage resize handles ----------------------------

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


# --- keystroke overlay capture --------------------------

func _key_event(keycode: int, ctrl: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev


func test_key_label_uses_glyphs_for_brackets_and_escape() -> void:
	var sm := _sm()
	assert_eq(sm._key_label(_key_event(KEY_BRACKETLEFT)), "[", "left bracket shows as [")
	assert_eq(sm._key_label(_key_event(KEY_BRACKETRIGHT)), "]", "right bracket shows as ]")
	assert_eq(sm._key_label(_key_event(KEY_ESCAPE)), "Esc", "escape shows as Esc")
	assert_eq(sm._key_label(_key_event(KEY_T)), "T", "a letter shows as itself")
	assert_eq(sm._key_label(_key_event(KEY_1, true)), "Ctrl+1", "a chorded digit shows the modifier")


func test_take_keys_this_tick_drains_the_buffer() -> void:
	var sm := _sm()
	sm._note_key("]")
	sm._note_key("[")
	assert_eq(sm.take_keys_this_tick(), ["]", "["], "buffered keys are returned in order")
	assert_eq(sm.take_keys_this_tick(), [], "the buffer is cleared after draining")


func test_dispatch_key_routes_resize_and_reports_handled() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 9
	u.max_soldiers = 80
	b._by_uid[9] = u
	var start: int = UnitFormation.frontage(u)
	sm._select(u)
	assert_true(sm._dispatch_key(_key_event(KEY_BRACKETRIGHT)), "] is a handled hotkey")
	assert_eq(UnitFormation.frontage(u), start + 1, "and widens the selected unit")
	assert_false(sm._dispatch_key(_key_event(KEY_P)), "an unbound key is not handled")


# --- drag-to-form-up ------------------------------------

func test_form_up_facing_is_perpendicular_to_the_flank_line() -> void:
	var sm := _sm()
	# A left->right horizontal flank line: the unit faces up (perpendicular).
	var facing := Vector2.from_angle(sm._form_up_facing(Vector2(0, 0), Vector2(100, 0)))
	assert_almost_eq(facing.x, 0.0, 0.001, "a horizontal flank line gives a vertical facing")
	assert_almost_eq(facing.y, -1.0, 0.001, "and faces up for a left-to-right drag")


func test_can_form_up_requires_a_selection_and_width() -> void:
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)), "no selection -> plain move")
	sm._select(a)
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)), "one unit + wide drag -> form-up")
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(5, 0)), "too-short drag -> plain move")
	sm._select(c)
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(100, 0)),
			"a multi-selection + wide drag also forms up (distributed along the line)")


func test_can_form_up_needs_extra_width_for_each_inter_unit_gap() -> void:
	# Two units need FORM_UP_MIN_WIDTH plus one gap's worth of drag; a drag only wide enough
	# for a single unit falls back to a plain move (so the gaps can't eat all the usable width).
	var sm := _sm()
	var a := _unit()
	var c := _unit()
	sm._select(a)
	var one_unit_min: float = SelectionManagerScript.FORM_UP_MIN_WIDTH
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(one_unit_min, 0)), "one unit forms up at the base minimum")
	sm._select(c)
	assert_false(sm._can_form_up(Vector2.ZERO, Vector2(one_unit_min, 0)),
			"two units need more than the single-unit minimum (room for the gap)")
	var two_unit_min: float = one_unit_min + SelectionManagerScript.MULTI_FORM_UP_GAP
	assert_true(sm._can_form_up(Vector2.ZERO, Vector2(two_unit_min, 0)),
			"a drag wide enough for the gap forms up")


# --- clickable flags ------------------------------------

func test_flag_pick_distance_hits_the_standard_and_misses_the_body_and_empty_space() -> void:
	var sm := _sm()
	var u := _unit()
	u.position = Vector2(500, 500)
	# The standard's local centre, from the same geometry UnitSprites draws.
	var center: Vector2 = UnitSprites.standard_bounds(u.render_block_extent()).get_center()
	var flag_world: Vector2 = u.global_position + center
	assert_almost_eq(sm._flag_pick_distance(u, flag_world), 0.0, 0.001,
			"a cursor on the standard's centre is zero distance from it")
	assert_eq(sm._flag_pick_distance(u, u.global_position), -1.0,
			"the body centre is well below the raised standard, so not a flag hit")
	assert_eq(sm._flag_pick_distance(u, u.global_position + Vector2(9999, 0)), -1.0,
			"empty space far from the standard is not a flag hit")


func test_unit_at_selects_a_unit_by_its_flag() -> void:
	var sm := _sm()
	var u := _unit()
	u.team = 0
	u.position = Vector2(500, 500)
	var flag_world: Vector2 = u.global_position \
			+ UnitSprites.standard_bounds(u.render_block_extent()).get_center()
	# The flag floats above the block, out of body-click range, yet resolves to the unit.
	# Read the body-pick pad from SelectionManager so this stays true if the threshold moves.
	var body_pick: float = UnitScript.RADIUS + SelectionManagerScript.BODY_PICK_PAD
	assert_gt(flag_world.distance_to(u.global_position), body_pick,
			"the flag sits beyond the body-click radius")
	assert_eq(sm._unit_at(flag_world, 0), u, "clicking the raised flag selects the unit")


func test_unit_at_prefers_a_body_hit_over_an_overlapping_flag() -> void:
	# A body click always wins: place unit B's flag exactly over unit A's body, then click
	# there — A (the body) is selected, not B (the flag floating onto the same spot).
	var sm := _sm()
	var a := _unit()
	a.team = 0
	a.position = Vector2(300, 300)
	var b := _unit()
	b.team = 0
	# Put B's standard centre on A's body centre.
	var center: Vector2 = UnitSprites.standard_bounds(b.render_block_extent()).get_center()
	b.position = a.global_position - center
	assert_eq(sm._unit_at(a.global_position, 0), a,
			"the body under the cursor wins over another unit's overlapping flag")


func test_unit_at_flag_click_respects_team() -> void:
	var sm := _sm()
	var enemy := _unit()
	enemy.team = 1
	enemy.position = Vector2(700, 200)
	var flag_world: Vector2 = enemy.global_position \
			+ UnitSprites.standard_bounds(enemy.render_block_extent()).get_center()
	assert_null(sm._unit_at(flag_world, 0),
			"a team-0 query ignores an enemy's flag (team filter still applies)")
	assert_eq(sm._unit_at(flag_world, 1), enemy,
			"a team-1 query resolves the same flag to the enemy")


func test_issue_form_up_routes_a_recorded_order() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u := _unit()
	u.uid = 11
	u.max_soldiers = 120
	u.position = Vector2(0, 100)
	b._by_uid[11] = u
	sm._select(u)
	sm._issue_form_up(Vector2(400, 500), Vector2(540, 500))   # 140 px wide line
	assert_eq(u._reform_target, Vector2(470, 500), "deploys at the flank-line midpoint")
	assert_true(b._pending_orders[-1].has("face"), "routed as a recorded form-up order")


# --- multi-unit drag-to-form-up -------------------------

const EQUAL_DEPTH := SelectionManagerScript.FormUpDist.EQUAL_DEPTH
const EQUAL_WIDTH := SelectionManagerScript.FormUpDist.EQUAL_WIDTH


func test_form_up_equal_depth_gives_units_the_same_rank_depth() -> void:
	# Equal-depth (default): a bigger unit gets MORE files than a smaller one, but both
	# deploy at (about) the same number of ranks — the uniform battle-line look.
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var slices: Array = sm._form_up_slices([big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_DEPTH)
	assert_eq(slices.size(), 2, "one slice per unit")
	assert_lt(slices[0]["center"].x, slices[1]["center"].x, "slice centres run left to right")
	assert_gt(slices[0]["files"], slices[1]["files"], "the bigger unit deploys more files (wider)")
	var depth_big: int = int(ceil(200.0 / float(slices[0]["files"])))
	var depth_small: int = int(ceil(100.0 / float(slices[1]["files"])))
	assert_almost_eq(float(depth_big), float(depth_small), 1.0,
			"both units form up to within one rank of the same depth")


func test_form_up_equal_width_gives_units_the_same_frontage() -> void:
	# Equal-width: same files for equal-line-share regardless of size, so a big and a small
	# unit get the same frontage (the small one just ends up deeper).
	var sm := _sm()
	var big := _unit()
	big.max_soldiers = 200
	var small := _unit()
	small.max_soldiers = 100
	var slices: Array = sm._form_up_slices([big, small], Vector2(0, 0), Vector2(400, 0), EQUAL_WIDTH)
	assert_eq(slices[0]["files"], slices[1]["files"],
			"equal width gives both units the same frontage")


func test_form_up_single_unit_slice_fills_the_whole_line() -> void:
	# One unit collapses to the old behaviour: no gap, slice centre at the line midpoint,
	# regardless of mode.
	var sm := _sm()
	var u := _unit()
	u.max_soldiers = 120
	# A lone unit fills the 140 px drag with the same frontage the original single-unit deploy
	# used (files_for_halfwidth of the half-width) — in BOTH modes, since equal depth is vacuous.
	var want_files: int = UnitFormation.files_for_halfwidth(70.0, 120)
	for mode in [EQUAL_DEPTH, EQUAL_WIDTH]:
		var slices: Array = sm._form_up_slices([u], Vector2(400, 500), Vector2(540, 500), mode)
		assert_eq(slices.size(), 1, "a lone unit is one slice")
		assert_almost_eq(slices[0]["center"].x, 470.0, 0.001, "centred on the line midpoint")
		assert_eq(slices[0]["center"].y, 500.0, "on the line")
		assert_eq(slices[0]["files"], want_files, "fills the line at the original single-unit frontage")


func test_order_units_for_line_sorts_by_field_position_by_default() -> void:
	# Two units selected right-to-left of where they sit; the default field-position ordering
	# puts the physically-left unit on the left flank regardless of selection order.
	var sm := _sm()
	var left_on_field := _unit()
	left_on_field.position = Vector2(50, 0)
	var right_on_field := _unit()
	right_on_field.position = Vector2(900, 0)
	# Selected right-first, so selection order is [right, left].
	var sel: Array = [right_on_field, left_on_field]
	var by_field: Array = sm._order_units_for_line(sel, Vector2(0, 0), Vector2(1000, 0), false)
	assert_eq(by_field[0], left_on_field, "field order puts the left-positioned unit on the left flank")
	var by_sel: Array = sm._order_units_for_line(sel, Vector2(0, 0), Vector2(1000, 0), true)
	assert_eq(by_sel[0], right_on_field, "selection order keeps the first-selected unit on the left")


func test_issue_form_up_routes_one_order_per_selected_unit() -> void:
	var sm := _sm()
	var b = BattleScript.new()
	autofree(b)
	sm._battle = b
	var u1 := _unit()
	u1.uid = 21
	u1.max_soldiers = 100
	u1.position = Vector2(100, 500)
	var u2 := _unit()
	u2.uid = 22
	u2.max_soldiers = 100
	u2.position = Vector2(900, 500)
	b._by_uid[21] = u1
	b._by_uid[22] = u2
	sm._select(u1)
	sm._select(u2)
	var before: int = b._pending_orders.size()
	sm._issue_form_up(Vector2(0, 500), Vector2(1000, 500))
	assert_eq(b._pending_orders.size() - before, 2, "one recorded form-up order per unit")
	# Each order carries exactly one unit and a deploy facing, and their slice centres differ.
	var last_two: Array = b._pending_orders.slice(b._pending_orders.size() - 2)
	assert_eq(last_two[0]["units"].size(), 1, "each form-up order targets a single unit")
	assert_true(last_two[0].has("face") and last_two[1].has("face"), "both routed as form-up orders")
	assert_ne(last_two[0]["x"], last_two[1]["x"], "the two units deploy at distinct slice centres")


# --- form-up distribution mode (cycle + settings) -------

func test_form_up_dist_starts_at_the_persisted_default() -> void:
	Settings.form_up_dist_default = EQUAL_WIDTH
	var sm := _sm()   # _ready reads the default
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "the live mode starts at the persisted default")


func test_cycle_form_up_dist_hotkey_flips_the_live_mode() -> void:
	var sm := _sm()
	sm._form_up_dist = EQUAL_DEPTH
	assert_true(sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY)),
			"the cycle key is a handled hotkey")
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "one press advances to the next mode in the cycle")
	sm._dispatch_key(_key_event(SelectionManagerScript.FORM_UP_DIST_CYCLE_KEY))
	assert_eq(sm._form_up_dist, EQUAL_DEPTH, "a second press wraps back to the first mode")


func test_changing_the_default_snaps_the_live_mode_over() -> void:
	# A ☰-menu change to the default (Settings.form_up_dist_default) snaps the live mode to it.
	var sm := _sm()
	sm._form_up_dist = EQUAL_DEPTH
	Settings.form_up_dist_default = EQUAL_WIDTH   # fires Settings.changed -> _on_settings_changed
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "changing the default in settings updates the live mode")


func test_unrelated_setting_change_keeps_an_on_the_fly_cycle() -> void:
	# Cycling the live mode then toggling an unrelated setting must NOT reset the cycled mode.
	Settings.form_up_dist_default = EQUAL_DEPTH
	var sm := _sm()
	sm._form_up_dist = EQUAL_WIDTH   # cycled away from the default on the fly
	Settings.edge_scroll = not Settings.edge_scroll   # unrelated Settings.changed
	assert_eq(sm._form_up_dist, EQUAL_WIDTH, "an unrelated setting change leaves the cycled mode intact")
	Settings.edge_scroll = not Settings.edge_scroll   # restore


func test_form_up_dist_default_clamps_out_of_range() -> void:
	# A corrupt/hand-edited cfg can't propagate an out-of-range mode: the setter clamps it.
	Settings.form_up_dist_default = 99
	assert_eq(Settings.form_up_dist_default, Settings.FORM_UP_DIST_MAX,
			"an over-range default clamps to the last mode")
	Settings.form_up_dist_default = -5
	assert_eq(Settings.form_up_dist_default, 0, "a negative default clamps to the first mode")
