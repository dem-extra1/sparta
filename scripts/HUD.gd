extends CanvasLayer
## On-screen UI, built in code (no .tscn needed):
##   - top hint bar
##   - selected-unit info panel (bottom-left)
##   - victory/defeat overlay with a restart button

var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _edge_toggle: CheckButton
var _status: Label
var _paused_label: Label
var _watch_button: Button
var _load_dialog: FileDialog
var _error_dialog: AcceptDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint.
	var hint := Label.new()
	hint.text = "LMB select / drag-box   •   RMB move or attack   •   WASD pan   •   wheel zoom   •   P / Ctrl+Space pause   •   hold Space show orders"
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

	# Settings: edge-scroll toggle (top-right). Give it an explicit width so the
	# placement is derived from that, not a font-metric-tuned magic offset.
	_edge_toggle = CheckButton.new()
	_edge_toggle.text = "Mouse-edge scroll"
	var toggle_width := 240.0
	_edge_toggle.custom_minimum_size = Vector2(toggle_width, 0)
	_edge_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_edge_toggle.position = Vector2(-toggle_width - 6.0, 6)
	_edge_toggle.button_pressed = Settings.edge_scroll
	_edge_toggle.toggled.connect(func(on: bool) -> void: Settings.edge_scroll = on)
	# Keep the checkbox in sync if the setting changes elsewhere. Use a named
	# method (not a lambda) so the connection is tied to this node's lifetime and
	# torn down in _exit_tree() — otherwise it would dangle on the persistent
	# Settings autoload after reload_current_scene() frees this HUD.
	Settings.changed.connect(_sync_edge_toggle)
	add_child(_edge_toggle)

	# Persistent "Load Replay" button (top-right, under the edge toggle) so a
	# saved replay can be opened any time — including right after launch.
	var load_btn := Button.new()
	load_btn.text = "Load Replay"
	var load_width := 140.0
	load_btn.custom_minimum_size = Vector2(load_width, 0)
	load_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	load_btn.position = Vector2(-load_width - 6.0, 44)
	load_btn.pressed.connect(_open_load_dialog)
	add_child(load_btn)

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
	_error_dialog.title = "Load Replay"
	add_child(_error_dialog)

	# Selected-unit panel.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(14, -132)
	panel.custom_minimum_size = Vector2(240, 112)
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
	if Settings.changed.is_connected(_sync_edge_toggle):
		Settings.changed.disconnect(_sync_edge_toggle)


func _sync_edge_toggle() -> void:
	_edge_toggle.button_pressed = Settings.edge_scroll


func _unhandled_input(event: InputEvent) -> void:
	# P toggles active pause: the sim freezes but selection and camera stay
	# live (they run as PROCESS_MODE_ALWAYS), so orders can be queued while paused
	# and apply on resume. Disabled once the end-of-battle overlay is up.
	if _is_pause_keypress(event) and not _overlay.visible:
		_toggle_pause()


func _is_pause_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	# P toggles pause; Ctrl+Space does too (plain Space is reserved for the
	# hold-to-show-orders overlay, so it must carry Ctrl to mean "pause").
	if event.keycode == KEY_P:
		return true
	return event.keycode == KEY_SPACE and event.ctrl_pressed


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
	var kind: String = "Cavalry" if u.is_cavalry else ("Spearmen" if u.anti_cavalry else "Infantry")
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d\nOrder: %s" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale), u.order_summary()
	]


func clear_unit() -> void:
	_info.text = "No unit selected"


func show_end(text: String) -> void:
	_paused_label.visible = false   # the end overlay supersedes the pause banner
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	# Fresh battle: drop back to IDLE so Battle._ready starts a new recording.
	Replay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_load_dialog() -> void:
	_load_dialog.current_dir = Replay.replays_dir()
	_load_dialog.popup_centered()


func _on_replay_chosen(path: String) -> void:
	if not Replay.start_playback(path):
		# Bad/incompatible file — report it without clobbering any result label.
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
