extends GutTest
## The read-only "every shortcut" reference dialog (#389). Instantiating it also
## smoke-tests that it builds without a runtime error. The bottom section covers
## HUD's ? (Shift+/) keypress detection that opens it.

const ShortcutsOverlayScript = preload("res://scripts/ShortcutsOverlay.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const HUDScript = preload("res://scripts/HUD.gd")

var _orig_bindings: Dictionary


func before_each() -> void:
	_orig_bindings = Settings.order_bindings.duplicate()
	# Pin to the factory defaults; a developer's persisted cfg (or another test file's
	# residual state in the same suite run) can leave a binding non-default, which broke
	# test_stance_row_updates_after_a_live_rebind's "changed from before" assertion when
	# "skirmish" was already KEY_J going in. Restored via after_each like the snapshot.
	Settings.order_bindings = Settings.DEFAULT_ORDER_BINDINGS.duplicate()


func after_each() -> void:
	Settings.order_bindings = _orig_bindings.duplicate()


func _dialog() -> AcceptDialog:
	var d = ShortcutsOverlayScript.new()
	add_child_autofree(d)   # runs _ready(): builds the row grid
	return d


func test_dialog_builds_without_error() -> void:
	var d := _dialog()
	assert_not_null(d, "the dialog instantiates")
	assert_eq(d.title, "Keyboard Shortcuts")


func test_stance_rows_are_tracked_for_every_hotkey_entry() -> void:
	var d := _dialog()
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		assert_true(d._stance_labels.has(entry["slug"]),
			"a key-label row exists for stance slug '%s'" % entry["slug"])


func test_stance_row_shows_the_current_binding() -> void:
	Settings.order_bindings["hold"] = KEY_J
	var d := _dialog()
	var key_label: Label = d._stance_labels["hold"]
	assert_eq(key_label.text, OS.get_keycode_string(KEY_J),
		"the row reflects the bound key at the time the dialog was built")


func test_stance_row_updates_after_a_live_rebind() -> void:
	var d := _dialog()
	var key_label: Label = d._stance_labels["skirmish"]
	var before: String = key_label.text
	# Mutate the dict directly + emit Settings.changed by hand, exactly like
	# test_selector_reads_rebound_key_from_settings does in test_selection_manager.gd --
	# this exercises the same signal path a real rebind would (Settings.set_order_binding
	# also calls _save(), which would persist to the developer's real user://settings.cfg;
	# a unit test must not have that side effect).
	Settings.order_bindings["skirmish"] = KEY_J
	Settings.changed.emit()
	assert_ne(key_label.text, before, "the row repaints after Settings.changed")
	assert_eq(key_label.text, OS.get_keycode_string(KEY_J))


# --- HUD's ?-key detection ---------------------------------------------------

func _key_event(physical_keycode: int, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)
	return hud


func test_shift_slash_is_a_shortcuts_keypress() -> void:
	var hud := _hud()
	assert_true(hud._is_shortcuts_keypress(_key_event(KEY_SLASH, true)),
		"Shift+/ (the ? key) opens the shortcuts overlay")


func test_plain_slash_is_not_a_shortcuts_keypress() -> void:
	var hud := _hud()
	assert_false(hud._is_shortcuts_keypress(_key_event(KEY_SLASH, false)),
		"/ without Shift does not (it's not a recognized hotkey elsewhere either)")


func test_shift_with_another_key_is_not_a_shortcuts_keypress() -> void:
	var hud := _hud()
	assert_false(hud._is_shortcuts_keypress(_key_event(KEY_A, true)),
		"Shift+A is unrelated")
