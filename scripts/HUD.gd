extends CanvasLayer
## On-screen UI, built in code (no .tscn needed):
##   - top hint bar
##   - selected-unit info panel (bottom-left)
##   - victory/defeat overlay with a restart button

var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _paused_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint.
	var hint := Label.new()
	hint.text = "LMB select / drag-box   •   RMB move or attack   •   WASD pan   •   wheel zoom   •   Space pause"
	hint.position = Vector2(14, 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)

	# Active-pause indicator (top-center). Hidden until the player pauses;
	# commands can still be issued while paused, so it reads as "PAUSED".
	_paused_label = Label.new()
	_paused_label.text = "❚❚ PAUSED — orders can still be given"
	# Span the top edge and center the text, so it stays centered across
	# resolutions/font/text changes without a hardcoded offset.
	_paused_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.offset_top = 36
	_paused_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_paused_label.add_theme_font_size_override("font_size", 18)
	_paused_label.visible = false
	add_child(_paused_label)

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


func _unhandled_input(event: InputEvent) -> void:
	# Spacebar toggles active pause. Disabled once the battle is over (the
	# end overlay owns the paused state and only "Fight Again" should resume).
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_SPACE and not _overlay.visible:
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
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale)
	]


func clear_unit() -> void:
	_info.text = "No unit selected"


func show_end(text: String) -> void:
	_paused_label.visible = false   # the end overlay owns the paused state now
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
