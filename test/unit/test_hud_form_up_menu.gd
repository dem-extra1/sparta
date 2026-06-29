extends GutTest
## The ☰-menu picker for the default multi-unit form-up distribution. Instantiating the HUD
## also smoke-tests that its menu builds (the radio items / labelled separator added for this
## picker) without a runtime error — nothing else instantiates the HUD headlessly.

const HUDScript = preload("res://scripts/HUD.gd")
const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")

var _orig_default: int
var _orig_reform: bool


func before_each() -> void:
	_orig_default = Settings.form_up_dist_default
	_orig_reform = Settings.reform_before_move


func after_each() -> void:
	Settings.form_up_dist_default = _orig_default
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
