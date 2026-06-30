extends GutTest
## The ☰-menu picker for the default multi-unit form-up distribution. Instantiating the HUD
## also smoke-tests that its menu builds (the radio items / labelled separator added for this
## picker) without a runtime error — nothing else instantiates the HUD headlessly.

const HUDScript = preload("res://scripts/HUD.gd")
const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")

var _orig_default: int
var _orig_cycle: Array
var _orig_reform: bool


func before_each() -> void:
	_orig_default = Settings.form_up_dist_default
	_orig_cycle = Settings.form_up_dist_cycle.duplicate()
	_orig_reform = Settings.reform_before_move
	# Pin the default cycle; a developer's persisted cfg can deviate and break these tests locally.
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH,
			SelectionManagerScript.FormUpDist.EQUAL_WIDTH]


func after_each() -> void:
	Settings.form_up_dist_default = _orig_default
	Settings.form_up_dist_cycle = _orig_cycle.duplicate()
	Settings.reform_before_move = _orig_reform


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)   # runs _ready(): builds the menu, info panel, overlay
	return hud


func _popup(hud) -> PopupMenu:
	return hud._menu_button.get_popup()


func test_menu_builds_with_the_form_up_radio_items() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH), 0,
			"the equal-depth radio item is present")
	assert_gte(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH), 0,
			"the equal-width radio item is present")


func test_radios_reflect_the_persisted_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_WIDTH
	var hud := _hud()   # _ready -> _sync_setting_toggles reads the default
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH)),
			"equal-depth is unchecked when the default is equal-width")
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH)),
			"equal-width is checked as the current default")


func test_picking_a_radio_sets_and_persists_the_default() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	# Drive the menu handler as the popup's id_pressed signal would.
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)
	assert_eq(Settings.form_up_dist_default, SelectionManagerScript.FormUpDist.EQUAL_WIDTH,
			"choosing the equal-width item sets the persisted default")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_WIDTH)),
			"and the radio re-syncs to the new default")


# --- reform-before-move menu item ---

func test_reform_menu_item_present() -> void:
	var hud := _hud()
	var popup := _popup(hud)
	assert_gte(popup.get_item_index(HUDScript.MENU_REFORM_BEFORE_MOVE), 0,
			"the reform-before-move check item is present in the menu")


func test_reform_menu_check_reflects_setting() -> void:
	Settings.reform_before_move = false
	var hud := _hud()
	var popup := _popup(hud)
	assert_false(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_REFORM_BEFORE_MOVE)),
			"item is unchecked when setting is false")


func test_reform_menu_toggle_flips_setting() -> void:
	Settings.reform_before_move = true
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_REFORM_BEFORE_MOVE)
	assert_false(Settings.reform_before_move,
			"toggling the menu item turns reform off when it was on")
	hud._on_menu_id(HUDScript.MENU_REFORM_BEFORE_MOVE)
	assert_true(Settings.reform_before_move,
			"toggling again turns it back on")


# --- form-up cycle checkboxes: the default mode can't be excluded -----------
# A player could uncheck the cycle entry for the battle DEFAULT, leaving it unreachable by
# the Y-key cycle with no feedback. Disable that one checkbox instead of allowing the
# inconsistency and warning after the fact.

func test_cycle_checkbox_for_the_default_mode_is_disabled() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	var popup := _popup(hud)
	assert_true(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_DEPTH)),
			"the cycle checkbox for the current default is disabled")
	assert_false(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the non-default cycle checkbox stays enabled")


func test_cycle_checkbox_disable_follows_the_default_when_it_changes() -> void:
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)   # change the default
	var popup := _popup(hud)
	assert_false(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_DEPTH)),
			"the old default's cycle checkbox re-enables")
	assert_true(popup.is_item_disabled(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the new default's cycle checkbox becomes disabled")


func test_changing_default_to_a_mode_excluded_from_the_cycle_adds_it() -> void:
	# The symmetric path to the bug: narrow the cycle to DEPTH only (allowed -- DEPTH is still
	# the default), then flip the default to the excluded mode (WIDTH). The default must stay
	# Y-key reachable, so WIDTH gets added back to the cycle automatically.
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	Settings.form_up_dist_cycle = [SelectionManagerScript.FormUpDist.EQUAL_DEPTH]
	var hud := _hud()
	hud._on_menu_id(HUDScript.MENU_FORMUP_EQUAL_WIDTH)
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_WIDTH),
			"changing the default to an excluded mode adds it back to the cycle")
	var popup := _popup(hud)
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_WIDTH)),
			"the newly-defaulted mode's cycle checkbox shows checked, not stuck unchecked")


func test_toggling_the_default_out_of_the_cycle_is_a_no_op() -> void:
	# Defense-in-depth: even if _toggle_form_up_cycle is reached for the disabled item, the
	# default stays in the cycle (the invariant the disabled checkbox is meant to guarantee).
	Settings.form_up_dist_default = SelectionManagerScript.FormUpDist.EQUAL_DEPTH
	var hud := _hud()
	hud._toggle_form_up_cycle(SelectionManagerScript.FormUpDist.EQUAL_DEPTH)
	assert_true(Settings.form_up_dist_cycle.has(SelectionManagerScript.FormUpDist.EQUAL_DEPTH),
			"the current default cannot be removed from the cycle")
