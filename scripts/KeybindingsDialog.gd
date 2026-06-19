extends AcceptDialog
## Keybindings dialog (#87): view and rebind the order-mode selector hotkeys.
##
## Rows are built from Battle.ORDER_MODE_HOTKEYS (mode + stable cfg slug) and labelled
## via ORDER_MODE_NAMES; the current key for each comes from the Settings autoload
## (slug -> physical keycode), which persists changes. Clicking a row's button captures
## the next key press; a key already bound to another order mode is rejected with a
## message, and Esc cancels the capture (it stays the fixed "clear stance" key).
## "Reset to defaults" restores Settings.DEFAULT_ORDER_BINDINGS.
##
## Pure client-side input config — mode selection is local and only the resulting order
## is recorded, so there's no sim/replay/determinism impact (#87). The dialog UI itself
## is verified manually (#12); the binding logic lives in Settings and is unit-tested.

const BattleRef = preload("res://scripts/Battle.gd")

# slug -> the Button that shows the current key and captures a new one.
var _row_buttons: Dictionary = {}
# The slug currently waiting for a key press, or "" when not capturing.
var _capturing_slug: String = ""
var _status: Label


func _ready() -> void:
	title = "Keybindings"
	process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the battle is paused
	unresizable = true   # fixed 5-row grid; resizing would only add blank space / clip

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var heading := Label.new()
	heading.text = "Order-mode hotkeys — click a key to rebind. Esc clears a stance (fixed)."
	vbox.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for entry in BattleRef.ORDER_MODE_HOTKEYS:
		var slug: String = entry["slug"]
		var name_label := Label.new()
		name_label.text = str(BattleRef.ORDER_MODE_NAMES.get(entry["mode"], slug))
		grid.add_child(name_label)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 0)
		btn.pressed.connect(_begin_capture.bind(slug))
		grid.add_child(btn)
		_row_buttons[slug] = btn

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	vbox.add_child(_status)

	# "Reset to defaults" sits alongside the dialog's OK button.
	add_button("Reset to defaults", true, "reset")
	custom_action.connect(_on_custom_action)
	visibility_changed.connect(_on_visibility_changed)

	# Keep the labels live if a binding changes elsewhere (or via reset).
	Settings.changed.connect(_refresh_labels)
	_refresh_labels()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_refresh_labels):
		Settings.changed.disconnect(_refresh_labels)


## Repaint every row button: the captured slug shows a prompt, the rest show their key.
func _refresh_labels() -> void:
	for slug in _row_buttons:
		var btn: Button = _row_buttons[slug]
		if slug == _capturing_slug:
			btn.text = "Press a key…"
		else:
			btn.text = OS.get_keycode_string(Settings.order_binding(slug))


func _begin_capture(slug: String) -> void:
	_capturing_slug = slug
	_status.text = ""
	# Drop focus so the button itself doesn't swallow Space/Enter as a re-press, and
	# disable OK so a stray Enter during capture can't confirm/close the dialog.
	_row_buttons[slug].release_focus()
	get_ok_button().disabled = true
	_refresh_labels()


func _end_capture() -> void:
	_capturing_slug = ""
	get_ok_button().disabled = false


func _on_visibility_changed() -> void:
	if not visible and _capturing_slug != "":
		_end_capture()
		_refresh_labels()


func _on_custom_action(action: StringName) -> void:
	if action == "reset":
		_end_capture()
		Settings.reset_order_bindings()   # Settings.changed -> _refresh_labels
		_status.text = "Restored default hotkeys."


func _input(event: InputEvent) -> void:
	if _capturing_slug == "":
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Consume the key so it doesn't also leak to the order selector / camera (and so
	# Enter can't reach the OK button to confirm the dialog mid-capture).
	get_viewport().set_input_as_handled()
	var keycode: int = event.physical_keycode
	var slug := _capturing_slug
	_end_capture()

	# Esc cancels; Enter/Return is reserved (dialog confirm) and never bound.
	if keycode == KEY_ESCAPE:
		_status.text = "Rebind cancelled."
		_refresh_labels()
		return
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_status.text = "Enter is reserved and can't be bound."
		_refresh_labels()
		return
	var conflict := Settings.slug_for_keycode(keycode)
	if conflict != "" and conflict != slug:
		_status.text = "%s is already bound to %s." % [
			OS.get_keycode_string(keycode), _label_for(conflict)]
		_refresh_labels()
		return
	Settings.set_order_binding(slug, keycode)   # Settings.changed -> _refresh_labels
	_status.text = ""


## The display name for a mode slug (for conflict messages).
func _label_for(slug: String) -> String:
	for entry in BattleRef.ORDER_MODE_HOTKEYS:
		if entry["slug"] == slug:
			return str(BattleRef.ORDER_MODE_NAMES.get(entry["mode"], slug))
	return slug
