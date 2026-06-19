extends CanvasLayer
## On-screen UI, built in code (no .tscn needed):
##   - top hint bar
##   - top-right Menu button: restart the battle plus global options (#53)
##   - selected-unit info panel (bottom-left)
##   - victory/defeat overlay with a restart button

# Stable ids for the Menu popup's items (independent of index / separators).
enum { MENU_RESTART, MENU_RESTART_REPLAY, MENU_LOAD, MENU_EDGE_SCROLL, MENU_SFX }

var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _menu_button: MenuButton
var _status: Label
var _paused_label: Label
var _order_mode_label: Label
var _watch_button: Button
var _load_dialog: FileDialog
var _error_dialog: AcceptDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint.
	var hint := Label.new()
	hint.text = "LMB select / drag-box   •   RMB move or attack   •   Shift+RMB add waypoint   •   H/F/R/K/G order mode (Esc clear)   •   WASD pan   •   wheel zoom   •   P / Shift+Space pause   •   hold Space show orders"
	hint.position = Vector2(14, 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)

	# Recording / replay status (top-center).
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-90, 30)
	_status.custom_minimum_size = Vector2(180, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	if Replay.mode == Replay.Mode.PLAYBACK:
		_status.text = "▶ REPLAY"
		_status.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	else:
		_status.text = "● REC"
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	add_child(_status)

	# Active-pause indicator (top-center, below the REC/REPLAY status). Hidden
	# until the player toggles pause with Space.
	_paused_label = Label.new()
	_paused_label.text = "⏸ PAUSED"
	_paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_paused_label.position = Vector2(-90, 54)
	_paused_label.custom_minimum_size = Vector2(180, 0)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.add_theme_font_size_override("font_size", 18)
	_paused_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.35))
	_paused_label.visible = false
	add_child(_paused_label)

	# Armed order-mode indicator (#35), top-center below the pause banner. Hidden
	# for the default stance; SelectionManager calls set_order_mode() to update it.
	_order_mode_label = Label.new()
	_order_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_order_mode_label.position = Vector2(-120, 80)
	_order_mode_label.custom_minimum_size = Vector2(240, 0)
	_order_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_mode_label.add_theme_font_size_override("font_size", 16)
	_order_mode_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_order_mode_label.visible = false
	add_child(_order_mode_label)

	# Menu button (top-right) gathering the global options that used to be
	# scattered across the HUD — restart, replay loading, and the edge-scroll
	# toggle (#53). Its popup is PROCESS_MODE_ALWAYS so it stays usable while the
	# simulation is paused. Give the button an explicit width so its placement is
	# derived from that, not a font-metric-tuned magic offset.
	_menu_button = MenuButton.new()
	_menu_button.text = "☰ Menu"
	var menu_width := 120.0
	_menu_button.custom_minimum_size = Vector2(menu_width, 0)
	_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-menu_width - 6.0, 6)
	add_child(_menu_button)

	var popup := _menu_button.get_popup()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS   # usable while paused
	# "Restart Battle" works mid-fight, not just from the end-of-battle overlay;
	# it always starts a fresh LIVE battle (matching the overlay's "Fight Again").
	# "Restart Replay" instead rewinds the current playback to tick 0, so it's
	# only meaningful while watching a replay — disabled (greyed) in a live battle.
	popup.add_item("Restart Battle", MENU_RESTART)
	popup.add_item("Restart Replay", MENU_RESTART_REPLAY)
	popup.set_item_disabled(popup.get_item_index(MENU_RESTART_REPLAY),
			Replay.mode != Replay.Mode.PLAYBACK)
	popup.add_item("Load Replay…", MENU_LOAD)
	popup.add_separator()
	popup.add_check_item("Mouse-edge scroll", MENU_EDGE_SCROLL)
	popup.add_check_item("Sound effects", MENU_SFX)
	_sync_setting_toggles()
	popup.id_pressed.connect(_on_menu_id)
	# Keep the check items in sync if a setting changes elsewhere. Use a named
	# method (not a lambda) so the connection is tied to this node's lifetime and
	# torn down in _exit_tree() — otherwise it would dangle on the persistent
	# Settings autoload after reload_current_scene() frees this HUD.
	Settings.changed.connect(_sync_setting_toggles)

	# File picker for choosing a saved replay, plus an error popup for bad files.
	# Both stay responsive while the tree is paused (end-of-battle overlay).
	_load_dialog = FileDialog.new()
	_load_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_dialog.access = FileDialog.ACCESS_USERDATA
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.filters = PackedStringArray(["*.json ; Replay files"])
	_load_dialog.title = "Load Replay"
	_load_dialog.size = Vector2i(640, 480)
	_load_dialog.file_selected.connect(_on_replay_chosen)
	add_child(_load_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	# Neutral default; each caller sets a context-specific title before popping it.
	_error_dialog.title = "Replay"
	add_child(_error_dialog)

	# Selected-unit info panel, pinned above the bottom-left corner. The top
	# offset is derived from the panel's own min-height + bottom margin (not a
	# hand-tuned magic number), and grow_vertical = BEGIN lets it expand UPWARD
	# if a content row or a larger font is added — so it never clips past the
	# screen's bottom edge.
	var panel := PanelContainer.new()
	var panel_min := Vector2(240, 90)
	var panel_bottom_gap := 20.0   # clearance between the panel and the screen edge
	panel.custom_minimum_size = panel_min
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(14.0, -(panel_min.y + panel_bottom_gap))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	_info = Label.new()
	_info.text = "No unit selected"
	margin.add_child(_info)

	# End-of-battle overlay.
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_overlay_label = Label.new()
	_overlay_label.text = "Battle Over"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 48)
	box.add_child(_overlay_label)

	var restart := Button.new()
	restart.text = "Fight Again"
	restart.custom_minimum_size = Vector2(180, 44)
	restart.pressed.connect(_on_restart)
	box.add_child(restart)

	# Replay the battle that just finished (re-runs the saved log).
	_watch_button = Button.new()
	_watch_button.text = "Watch Again" if Replay.mode == Replay.Mode.PLAYBACK else "Watch Replay"
	_watch_button.custom_minimum_size = Vector2(180, 44)
	_watch_button.pressed.connect(_on_watch_replay)
	box.add_child(_watch_button)

	# Open an older saved replay (not just the one that just finished).
	var load_saved := Button.new()
	load_saved.text = "Load Replay…"
	load_saved.custom_minimum_size = Vector2(180, 44)
	load_saved.pressed.connect(_open_load_dialog)
	box.add_child(load_saved)


func _exit_tree() -> void:
	# Settings is a persistent autoload; drop our connection so it doesn't
	# outlive this HUD (e.g. across reload_current_scene()).
	if Settings.changed.is_connected(_sync_setting_toggles):
		Settings.changed.disconnect(_sync_setting_toggles)


func _sync_setting_toggles() -> void:
	var popup := _menu_button.get_popup()
	popup.set_item_checked(popup.get_item_index(MENU_EDGE_SCROLL), Settings.edge_scroll)
	popup.set_item_checked(popup.get_item_index(MENU_SFX), Settings.sfx_enabled)


## Dispatch a Menu popup selection by its stable item id.
func _on_menu_id(id: int) -> void:
	match id:
		MENU_RESTART:
			_on_restart()
		MENU_RESTART_REPLAY:
			_on_restart_replay()
		MENU_LOAD:
			_open_load_dialog()
		MENU_EDGE_SCROLL:
			# Flip the setting; Settings.changed -> _sync_setting_toggles re-checks it.
			Settings.edge_scroll = not Settings.edge_scroll
		MENU_SFX:
			Settings.sfx_enabled = not Settings.sfx_enabled


func _unhandled_input(event: InputEvent) -> void:
	# P toggles active pause: the sim freezes but selection and camera stay
	# live (they run as PROCESS_MODE_ALWAYS), so orders can be queued while paused
	# and apply on resume. Disabled once the end-of-battle overlay is up.
	if _is_pause_keypress(event) and not _overlay.visible:
		_toggle_pause()


func _is_pause_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	# P toggles pause; Shift+Space does too (plain Space is reserved for the
	# hold-to-show-orders overlay, so it must carry Shift to mean "pause"). Use
	# physical_keycode so the binding is layout-independent and unaffected by the
	# held modifier. Shift+Space is used rather than Ctrl+Space because macOS
	# reserves Ctrl+Space for input-source switching, so it never reaches the app.
	if event.physical_keycode == KEY_P:
		return true
	return event.physical_keycode == KEY_SPACE and event.shift_pressed


func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	_paused_label.visible = paused
	get_viewport().set_input_as_handled()


func show_unit(u, group_count: int) -> void:
	if u == null or not is_instance_valid(u):
		clear_unit()
		return
	var extra: String = "" if group_count <= 1 else "  (+%d more)" % (group_count - 1)
	var kind: String
	if u.is_cavalry:
		kind = "Cavalry"
	elif u.anti_cavalry:
		kind = "Spearmen"
	elif u.is_ranged:
		kind = "Archers"
	else:
		kind = "Infantry"
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d\nOrder: %s" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale), u.order_summary()
	]


func clear_unit() -> void:
	_info.text = "No unit selected"


## Show the armed order mode (#35). Empty text hides the indicator (default stance).
func set_order_mode(text: String) -> void:
	if text == "":
		_order_mode_label.visible = false
	else:
		_order_mode_label.text = "Order: %s" % text
		_order_mode_label.visible = true


func show_end(text: String) -> void:
	_paused_label.visible = false   # the end overlay supersedes the pause banner
	_order_mode_label.visible = false   # armed-mode indicator is irrelevant on the end screen
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	# Fresh battle: drop back to IDLE so Battle._ready starts a new recording.
	Replay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_restart_replay() -> void:
	# Rewind the watched replay to tick 0: start_playback re-reads loaded_path and
	# resets the play index, then the scene reload replays from the start. PLAYBACK
	# only (the menu item is disabled otherwise); guarded in case it's reached anyway.
	if Replay.mode != Replay.Mode.PLAYBACK:
		return
	if not Replay.start_playback(Replay.loaded_path):
		# Loaded fine on entering PLAYBACK, so a failure now means it vanished
		# mid-watch — report it like _on_replay_chosen rather than bailing silently.
		_error_dialog.title = "Restart Replay"
		_error_dialog.dialog_text = "That replay is no longer available."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_load_dialog() -> void:
	_load_dialog.current_dir = Replay.replays_dir()
	_load_dialog.popup_centered()


func _on_replay_chosen(path: String) -> void:
	if not Replay.start_playback(path):
		# Bad/incompatible file — report it without clobbering any result label.
		_error_dialog.title = "Load Replay"
		_error_dialog.dialog_text = "That file isn't a compatible replay."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_watch_replay() -> void:
	# Re-run the battle just shown. While watching a replay, "Watch Again" must
	# re-run *that* file (loaded_path) — which may be an older one opened via the
	# picker — not the last live battle. After a live battle, replay what we just
	# saved. If neither exists, say so rather than playing the wrong battle.
	var path := Replay.loaded_path if Replay.mode == Replay.Mode.PLAYBACK else Replay.last_saved_path
	if path == "" or not Replay.start_playback(path):
		# Report on the button itself so the battle result label is preserved.
		_watch_button.text = "No replay available"
		_watch_button.disabled = true
		return
	get_tree().paused = false
	get_tree().reload_current_scene()
