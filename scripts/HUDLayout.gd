extends RefCounted
## Static UI builders for HUD — one function per screen region so each can be
## modified independently without touching unrelated code.

static func build_hint_bar(parent: CanvasLayer) -> void:
	var hint := Label.new()
	hint.text = "LMB select / drag-box   •   RMB move or attack   •   WASD pan   •   wheel zoom   •   Space pause"
	hint.position = Vector2(14, 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.add_theme_font_size_override("font_size", 14)
	parent.add_child(hint)

static func build_pause_label(parent: CanvasLayer) -> Label:
	var lbl := Label.new()
	lbl.text = "❚❚ PAUSED — orders can still be given"
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.offset_top = 36
	lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.visible = false
	parent.add_child(lbl)
	return lbl

static func build_edge_toggle(parent: CanvasLayer) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = "Mouse-edge scroll"
	var w := 240.0
	btn.custom_minimum_size = Vector2(w, 0)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-w - 6.0, 6)
	btn.button_pressed = Settings.edge_scroll
	btn.toggled.connect(func(on: bool) -> void: Settings.edge_scroll = on)
	parent.add_child(btn)
	return btn

static func build_unit_panel(parent: CanvasLayer) -> Label:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(14, -110)
	panel.custom_minimum_size = Vector2(240, 90)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var info := Label.new()
	info.text = "No unit selected"
	margin.add_child(info)
	return info

static func build_end_overlay(parent: CanvasLayer, on_restart: Callable) -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var lbl := Label.new()
	lbl.text = "Battle Over"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	box.add_child(lbl)
	var btn := Button.new()
	btn.text = "Fight Again"
	btn.custom_minimum_size = Vector2(180, 44)
	btn.pressed.connect(on_restart)
	box.add_child(btn)
	return [overlay, lbl]
