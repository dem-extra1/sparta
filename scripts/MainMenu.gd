extends Control
## Title screen / entry point. Lets the player pick the self-contained tactical
## battle (M1) or the campaign map (M2, #70); kept as its own scene so Battle.tscn
## stays untouched for the eventual M3 campaign→battle hand-off. UI built in code,
## matching the rest of the project's HUDs.

const Campaigns = preload("res://scripts/campaign/Campaigns.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-160, -150)
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "SPARTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "grand strategy × real-time tactics"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(subtitle)

	box.add_child(_spacer(16))

	var battle_btn := _menu_button("Tactical Battle")
	battle_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Battle.tscn"))
	box.add_child(battle_btn)

	# One button per registered campaign (#125): selecting it records the map path,
	# then opens the shared campaign scene which loads that data file.
	for c in Campaigns.LIST:
		var path: String = c["path"]
		var btn := _menu_button("Campaign: %s" % c["name"])
		btn.pressed.connect(func(): _start_campaign(path))
		box.add_child(btn)

	var quit_btn := _menu_button("Quit")
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)


func _start_campaign(path: String) -> void:
	Campaigns.selected_path = path
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
