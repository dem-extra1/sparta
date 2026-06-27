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
	# Parity with Unit._support_valid's self-guard check. Battle never issues a
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
