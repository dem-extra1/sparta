extends CanvasLayer
## Campaign-map UI, built in code (same convention as the battle HUD): a turn /
## faction banner, a standings line, an End Turn button, a selection/help line, a
## transient action message, and a victory/defeat overlay. Talks to CampaignMap via
## signals (button presses) and plain update methods (state pushes).

signal end_turn_pressed
signal restart_pressed
signal menu_pressed

var _turn_label: Label
var _standings_label: Label
var _selection_label: Label
var _flash_label: Label
var _end_turn_button: Button
var _menu_button: Button
var _overlay: ColorRect
var _overlay_label: Label

var _flash_timer := 0.0


func _ready() -> void:
	# Title / turn banner (top-left).
	_turn_label = Label.new()
	_turn_label.position = Vector2(16, 12)
	_turn_label.add_theme_font_size_override("font_size", 22)
	add_child(_turn_label)

	# Province standings (top-left, under the banner).
	_standings_label = Label.new()
	_standings_label.position = Vector2(16, 44)
	_standings_label.add_theme_font_size_override("font_size", 15)
	_standings_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_child(_standings_label)

	# End Turn (top-right).
	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn"
	_end_turn_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_end_turn_button.position = Vector2(-128, 12)
	_end_turn_button.custom_minimum_size = Vector2(112, 34)
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_end_turn_button)

	# Menu (top-right, under End Turn).
	_menu_button = Button.new()
	_menu_button.text = "Main Menu"
	_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-128, 52)
	_menu_button.custom_minimum_size = Vector2(112, 30)
	_menu_button.pressed.connect(func(): menu_pressed.emit())
	add_child(_menu_button)

	# Selection / help line (bottom-left).
	_selection_label = Label.new()
	_selection_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_selection_label.position = Vector2(16, -54)
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	add_child(_selection_label)

	# Transient action message (bottom-left, above the help line).
	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_flash_label.position = Vector2(16, -82)
	_flash_label.add_theme_font_size_override("font_size", 16)
	_flash_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	add_child(_flash_label)

	# Victory / defeat overlay (hidden until the war is decided).
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_label.position = Vector2(-240, -60)
	_overlay_label.custom_minimum_size = Vector2(480, 0)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 26)
	_overlay.add_child(_overlay_label)

	var again := Button.new()
	again.text = "New Campaign"
	again.set_anchors_preset(Control.PRESET_CENTER)
	again.position = Vector2(-150, 10)
	again.custom_minimum_size = Vector2(140, 36)
	# reset_for_new_campaign() (via restart_pressed -> CampaignMap) hides the overlay.
	again.pressed.connect(func(): restart_pressed.emit())
	_overlay.add_child(again)

	var menu := Button.new()
	menu.text = "Main Menu"
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.position = Vector2(10, 10)
	menu.custom_minimum_size = Vector2(140, 36)
	menu.pressed.connect(func(): menu_pressed.emit())
	_overlay.add_child(menu)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_label.text = ""


func update_turn(turn: int, faction_name: String, color: Color) -> void:
	_turn_label.text = "Turn %d — %s" % [turn, faction_name]
	_turn_label.add_theme_color_override("font_color", color)


func update_standings(text: String) -> void:
	_standings_label.text = text


func update_selection(text: String) -> void:
	_selection_label.text = text


func flash(text: String) -> void:
	_flash_label.text = text
	_flash_timer = 3.0


func show_victory(text: String) -> void:
	_overlay_label.text = text
	_overlay.visible = true
	_end_turn_button.disabled = true


## Restore the HUD for a fresh campaign: hide the end overlay and re-enable End Turn
## (show_victory disables it). Called by CampaignMap when (re)starting a campaign.
func reset_for_new_campaign() -> void:
	_overlay.visible = false
	_end_turn_button.disabled = false
	_flash_label.text = ""
	_flash_timer = 0.0
