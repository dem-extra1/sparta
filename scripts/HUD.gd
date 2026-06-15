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
var _watch_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint.
	var hint := Label.new()
	hint.text = "LMB select / drag-box   •   RMB move or attack   •   WASD pan   •   wheel zoom"
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

	# Selected-unit panel.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(14, -110)
	panel.custom_minimum_size = Vector2(240, 90)
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


func _exit_tree() -> void:
	# Settings is a persistent autoload; drop our connection so it doesn't
	# outlive this HUD (e.g. across reload_current_scene()).
	if Settings.changed.is_connected(_sync_edge_toggle):
		Settings.changed.disconnect(_sync_edge_toggle)


func _sync_edge_toggle() -> void:
	_edge_toggle.button_pressed = Settings.edge_scroll


func show_unit(u, group_count: int) -> void:
	if u == null or not is_instance_valid(u):
		clear_unit()
		return
	var extra: String = "" if group_count <= 1 else "  (+%d more)" % (group_count - 1)
	var kind: String = "Cavalry" if u.is_cavalry else ("Spearmen" if u.anti_cavalry else "Infantry")
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale)
	]


func clear_unit() -> void:
	_info.text = "No unit selected"


func show_end(text: String) -> void:
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	# Fresh battle: drop back to IDLE so Battle._ready starts a new recording.
	Replay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_watch_replay() -> void:
	# Re-run the battle just played. Prefer the path we actually saved this
	# session; only fall back to a directory scan if that's unavailable, so a
	# failed save can't silently replay an older battle.
	var path := Replay.last_saved_path
	if path == "":
		path = Replay.latest_path()
	if path == "" or not Replay.start_playback(path):
		_overlay_label.text = "No replay available"
		return
	get_tree().paused = false
	get_tree().reload_current_scene()
